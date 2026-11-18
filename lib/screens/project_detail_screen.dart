import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/errors.dart';
import '../models/build_models.dart';
import '../models/project_file.dart';
import '../models/project_meta.dart';
import '../providers/factory_controller.dart';
import '../providers/projects_controller.dart';
import '../services/file_exporter.dart';
import '../services/response_parser.dart';
import 'file_editor_screen.dart';
import 'projects_screen.dart';

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  List<ProjectFile>? _files;
  String? _loadError;
  BuildTarget _target = BuildTarget.apk;
  final _instruction = TextEditingController();
  bool _aiBusy = false;

  @override
  void initState() {
    super.initState();
    final meta = context.read<ProjectsController>().byId(widget.projectId);
    if (meta != null) _target = BuildTargetX.fromName(meta.lastTarget);
    _load();
  }

  @override
  void dispose() {
    _instruction.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final files = await context.read<ProjectsController>().loadFiles(widget.projectId);
      files.sort((a, b) => a.path.compareTo(b.path));
      if (mounted) setState(() => _files = files);
    } catch (e) {
      if (mounted) setState(() => _loadError = friendlyError(e));
    }
  }

  void _toast(String? m) {
    if (m == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  ProjectMeta? get _meta => context.read<ProjectsController>().byId(widget.projectId);

  /// يحفظ قائمة الملفات الحالية في المكتبة.
  Future<void> _persist(List<ProjectFile> files) async {
    final meta = _meta;
    if (meta == null) return;
    files.sort((a, b) => a.path.compareTo(b.path));
    setState(() => _files = files);
    await context.read<ProjectsController>().save(meta, files);
  }

  Future<void> _editFile(ProjectFile f) async {
    if (!f.isEditableText) {
      _toast('هذا الملف ثنائي أو كبير جداً ولا يمكن تعديله هنا.');
      return;
    }
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => FileEditorScreen(path: f.path, initialText: f.text)),
    );
    if (text == null || !mounted) return;
    final files = List<ProjectFile>.of(_files!);
    final i = files.indexWhere((e) => e.path == f.path);
    if (i >= 0) files[i] = ProjectFile.text(f.path, text);
    await _persist(files);
    _toast('تم حفظ ${f.path}');
  }

  Future<void> _addFile() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ملف جديد'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(hintText: 'lib/screens/new_screen.dart'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text('إنشاء')),
        ],
      ),
    );
    controller.dispose();
    if (raw == null || raw.trim().isEmpty || !mounted) return;
    final path = ResponseParser.cleanPath(raw);
    if (path == null) {
      _toast('مسار غير صالح.');
      return;
    }
    if (_files!.any((f) => f.path == path)) {
      _toast('الملف موجود مسبقاً.');
      return;
    }
    await _persist([..._files!, ProjectFile.text(path, '')]);
    final created = _files!.firstWhere((f) => f.path == path);
    if (mounted) await _editFile(created);
  }

  Future<void> _deleteFile(ProjectFile f) async {
    final ok = await _confirm('حذف الملف؟', f.path);
    if (ok != true || !mounted) return;
    await _persist(_files!.where((e) => e.path != f.path).toList());
  }

  Future<bool?> _confirm(String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('تأكيد')),
        ],
      ),
    );
  }

  Future<void> _rename() async {
    final meta = _meta;
    if (meta == null) return;
    final controller = TextEditingController(text: meta.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة تسمية المشروع'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    await context.read<ProjectsController>().saveMeta(meta.copyWith(name: name));
  }

  Future<void> _delete() async {
    final meta = _meta;
    if (meta == null) return;
    final ok = await _confirm('حذف المشروع؟', 'سيُحذف «${meta.name}» من الجهاز (مستودع GitHub لن يتأثر).');
    if (ok != true || !mounted) return;
    final projects = context.read<ProjectsController>();
    final nav = Navigator.of(context);
    await projects.remove(meta.id);
    nav.pop();
  }

  Future<void> _aiEdit() async {
    final text = _instruction.text.trim();
    if (text.length < 4) {
      _toast('اكتب التعديل المطلوب أولاً.');
      return;
    }
    final factory = context.read<FactoryController>();
    final problem = factory.preflight(needsLlm: true);
    if (problem != null && problem.contains('الذكاء')) {
      _toast(problem);
      return;
    }
    setState(() => _aiBusy = true);
    try {
      final changes = await factory.aiEdit(_files!, text, _target);
      if (!mounted) return;
      final apply = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('سيتم تعديل ${changes.length} ملف'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in changes)
                  Text(
                    '${_files!.any((f) => f.path == c.path) ? '✎' : '＋'} ${c.path}',
                    textDirection: TextDirection.ltr,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('تجاهل')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('تطبيق')),
          ],
        ),
      );
      if (apply == true && mounted) {
        final map = <String, ProjectFile>{for (final f in _files!) f.path: f};
        for (final c in changes) {
          map[c.path] = c;
        }
        await _persist(map.values.toList());
        _instruction.clear();
        _toast('تم تطبيق التعديلات وحفظها. ابنِ المشروع للتحقق.');
      }
    } catch (e) {
      _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _build() async {
    final meta = _meta;
    final files = _files;
    if (meta == null || files == null) return;
    final factory = context.read<FactoryController>();
    if (factory.working) {
      _toast('هناك عملية بناء جارية حالياً.');
      return;
    }
    final problem = factory.preflight(needsLlm: false);
    if (problem != null) {
      _toast(problem);
      return;
    }
    Navigator.of(context).popUntil((r) => r.isFirst);
    factory.startFromLibrary(meta, files, _target);
  }

  @override
  Widget build(BuildContext context) {
    final meta = context.watch<ProjectsController>().byId(widget.projectId);
    final theme = Theme.of(context);
    final files = _files;
    if (meta == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('المشروع غير موجود.')));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(meta.name),
        actions: [
          IconButton(tooltip: 'إعادة تسمية', icon: const Icon(Icons.drive_file_rename_outline), onPressed: _rename),
          IconButton(
            tooltip: 'تصدير ZIP',
            icon: const Icon(Icons.archive_outlined),
            onPressed: files == null
                ? null
                : () async {
                    try {
                      await FileExporter.shareProjectZip(files, meta.name);
                    } catch (e) {
                      _toast(friendlyError(e));
                    }
                  },
          ),
          IconButton(tooltip: 'حذف', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: SafeArea(
        child: _loadError != null
            ? Center(child: Text(_loadError!))
            : files == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${meta.sourceLabel} • ${files.length} ملفات • ${formatBytes(meta.totalBytes)}'),
                              Text(meta.statusLabel),
                              Text('آخر تعديل: ${formatDate(meta.updatedAt)}', style: theme.textTheme.bodySmall),
                              if (meta.repoUrl != null)
                                TextButton.icon(
                                  onPressed: () async => _toast(await context.read<FactoryController>().openUrl(meta.repoUrl!)),
                                  icon: const Icon(Icons.open_in_new, size: 18),
                                  label: Text(meta.repoFullName ?? 'المستودع'),
                                ),
                              if (meta.pagesUrl != null)
                                TextButton.icon(
                                  onPressed: () async => _toast(await context.read<FactoryController>().openUrl(meta.pagesUrl!)),
                                  icon: const Icon(Icons.public, size: 18),
                                  label: const Text('فتح الموقع'),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('بناء المشروع', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<BuildTarget>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: BuildTarget.apk, label: Text('APK'), icon: Icon(Icons.android)),
                            ButtonSegment(value: BuildTarget.web, label: Text('ويب'), icon: Icon(Icons.language)),
                            ButtonSegment(value: BuildTarget.both, label: Text('الاثنان'), icon: Icon(Icons.layers_outlined)),
                          ],
                          selected: {_target},
                          onSelectionChanged: (s) => setState(() => _target = s.first),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _build,
                        icon: const Icon(Icons.build_circle_outlined),
                        label: Text(meta.repoFullName == null ? 'رفع وبناء' : 'تحديث المستودع وبناء'),
                      ),
                      const SizedBox(height: 24),
                      Text('تعديل بالذكاء الاصطناعي', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _instruction,
                        minLines: 2,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          hintText: 'مثال: أضف شاشة إعدادات ووضعاً داكناً',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FilledButton.tonalIcon(
                          onPressed: _aiBusy ? null : _aiEdit,
                          icon: _aiBusy
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.auto_fix_high),
                          label: const Text('نفّذ التعديل'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(child: Text('الملفات (${files.length})', style: theme.textTheme.titleMedium)),
                          TextButton.icon(
                            onPressed: _addFile,
                            icon: const Icon(Icons.add),
                            label: const Text('ملف جديد'),
                          ),
                        ],
                      ),
                      for (final f in files)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(f.isEditableText ? Icons.description_outlined : Icons.insert_drive_file_outlined),
                          title: Text(f.path, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13)),
                          subtitle: Text(formatBytes(f.size)),
                          onTap: () => _editFile(f),
                          trailing: IconButton(
                            tooltip: 'حذف',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => _deleteFile(f),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}
