import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/errors.dart';
import '../models/build_models.dart';
import '../providers/factory_controller.dart';
import '../services/project_importer.dart';
import 'guide_screen.dart';
import 'projects_screen.dart';
import 'settings_screen.dart';

void _snack(BuildContext context, String? message) {
  if (message == null || !context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// دالة مستقلة (بدون التقاط حالة الواجهة) لتشغيل القراءة في Isolate.
Future<ImportedProject> _importInIsolate(Uint8List bytes, bool keep) {
  return Isolate.run(
    () => ProjectImporter.fromZipBytes(bytes, keepPlatformFolders: keep),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final f = context.watch<FactoryController>();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/icon/icon.png', width: 30, height: 30),
            ),
            const SizedBox(width: 8),
            const Text('مصنع التطبيقات'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'مشروعاتي',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProjectsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'الدليل',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GuideScreen()),
            ),
          ),
          IconButton(
            tooltip: 'الإعدادات',
            icon: const Icon(Icons.settings_outlined),
            onPressed: f.working
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
                    ),
          ),
        ],
      ),
      body: SafeArea(
        child: f.phase == FactoryPhase.idle ? const _InputView() : const _RunView(),
      ),
    );
  }
}

// ======================================================================
// واجهة الإدخال: تبويبان (فكرة / مشروع جاهز) + اختيار نوع البناء
// ======================================================================

class _InputView extends StatelessWidget {
  const _InputView();

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(icon: Icon(Icons.auto_awesome), text: 'من فكرة'),
              Tab(icon: Icon(Icons.folder_zip_outlined), text: 'رفع مشروع جاهز'),
            ],
          ),
          Expanded(
            child: TabBarView(children: [_IdeaTab(), _UploadTab()]),
          ),
        ],
      ),
    );
  }
}

class _TargetSelector extends StatelessWidget {
  const _TargetSelector();

  @override
  Widget build(BuildContext context) {
    final f = context.watch<FactoryController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('نوع البناء', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<BuildTarget>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: BuildTarget.apk,
                label: Text('APK'),
                icon: Icon(Icons.android),
              ),
              ButtonSegment(
                value: BuildTarget.web,
                label: Text('ويب'),
                icon: Icon(Icons.language),
              ),
              ButtonSegment(
                value: BuildTarget.both,
                label: Text('الاثنان'),
                icon: Icon(Icons.layers_outlined),
              ),
            ],
            selected: {f.target},
            onSelectionChanged: (s) => f.setTarget(s.first),
          ),
        ),
      ],
    );
  }
}

class _IdeaTab extends StatefulWidget {
  const _IdeaTab();

  @override
  State<_IdeaTab> createState() => _IdeaTabState();
}

class _IdeaTabState extends State<_IdeaTab> {
  final _controller = TextEditingController();
  final _draft = TextEditingController();
  final _tweak = TextEditingController();
  bool _enhancing = false;
  bool _hasDraft = false;
  String? _enhanceError;

  @override
  void dispose() {
    _controller.dispose();
    _draft.dispose();
    _tweak.dispose();
    super.dispose();
  }

  void _start() {
    final f = context.read<FactoryController>();
    final idea = _controller.text.trim();
    if (idea.length < 8) {
      _snack(context, 'اكتب وصفاً أوضح لفكرة التطبيق.');
      return;
    }
    final problem = f.preflight(needsLlm: true);
    if (problem != null) {
      _snack(context, problem);
      return;
    }
    f.startFromIdea(idea);
  }

  Future<void> _enhance({bool refine = false}) async {
    final f = context.read<FactoryController>();
    final rough = _controller.text.trim();
    if (rough.length < 4) {
      _snack(context, 'اكتب فكرة مختصرة أولاً (ولو بجملة واحدة).');
      return;
    }
    setState(() {
      _enhancing = true;
      _enhanceError = null;
    });
    try {
      final out = await f.enhancePrompt(
        rough,
        previous: refine ? _draft.text : null,
        instruction: refine ? _tweak.text : null,
      );
      if (!mounted) return;
      setState(() {
        _draft.text = out;
        _hasDraft = true;
        _enhancing = false;
        if (refine) _tweak.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enhanceError = friendlyError(e);
        _enhancing = false;
      });
    }
  }

  void _useDraft() {
    setState(() {
      _controller.text = _draft.text.trim();
      _hasDraft = false;
      _draft.clear();
    });
    _snack(context, 'تم وضع البرومبت في خانة الفكرة. راجعه ثم ابدأ التصنيع.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _controller,
          minLines: 5,
          maxLines: 12,
          decoration: const InputDecoration(
            labelText: 'ما التطبيق الذي تريد صنعه؟',
            hintText: 'مثال: تطبيق لتتبع المصروفات اليومية مع رسوم بيانية...',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_fix_high, color: theme.colorScheme.onSecondaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'مساعد البرومبتات الاحترافية',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'اكتب فكرتك بجملة بسيطة ودع الذكاء الاصطناعي يحوّلها إلى برومبت مفصّل '
                  '(المزايا، الشاشات، البيانات، التصميم) قبل التصنيع.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _enhancing ? null : () => _enhance(),
                  icon: _enhancing && !_hasDraft
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(_hasDraft ? 'إنشاء برومبت جديد من الفكرة' : 'حوّل فكرتي إلى برومبت احترافي'),
                ),
                if (_enhanceError != null) ...[
                  const SizedBox(height: 8),
                  Text(_enhanceError!, style: TextStyle(color: theme.colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
        if (_hasDraft) ...[
          const SizedBox(height: 12),
          Text('البرومبت المقترح (يمكنك تعديله يدوياً)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _draft,
            minLines: 8,
            maxLines: 20,
            decoration: const InputDecoration(alignLabelWithHint: true),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tweak,
            decoration: const InputDecoration(
              labelText: 'تعديل مطلوب (اختياري)',
              hintText: 'مثال: أضف وضعاً داكناً وتصدير PDF',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _enhancing ? null : _useDraft,
                icon: const Icon(Icons.check),
                label: const Text('استخدم هذا البرومبت'),
              ),
              OutlinedButton.icon(
                onPressed: _enhancing ? null : () => _enhance(refine: true),
                icon: _enhancing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('إعادة التوليد بالتعديل'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        const _TargetSelector(),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.rocket_launch_outlined),
          label: const Text('ابدأ التصنيع'),
        ),
      ],
    );
  }
}

class _UploadTab extends StatefulWidget {
  const _UploadTab();

  @override
  State<_UploadTab> createState() => _UploadTabState();
}

class _UploadTabState extends State<_UploadTab> {
  ImportedProject? _project;
  String? _fileName;
  String? _error;
  bool _loading = false;
  bool _keepPlatforms = false;
  Uint8List? _zipBytes;

  Future<void> _pick() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final picked = result.files.first;
      Uint8List? bytes = picked.bytes;
      if (bytes == null && picked.path != null) {
        bytes = await File(picked.path!).readAsBytes();
      }
      if (bytes == null) {
        throw const FactoryException('تعذر قراءة الملف المحدد.');
      }
      _zipBytes = bytes;
      _fileName = picked.name;
      await _parse();
    } catch (e) {
      if (mounted) {
        setState(() {
          _project = null;
          _error = friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _parse() async {
    final bytes = _zipBytes;
    if (bytes == null) return;
    final keep = _keepPlatforms;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final project = await _importInIsolate(bytes, keep);
      if (!mounted) return;
      setState(() {
        _project = project;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _project = null;
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  void _start() {
    final f = context.read<FactoryController>();
    final project = _project;
    if (project == null) return;
    final problem = f.preflight(needsLlm: false);
    if (problem != null) {
      _snack(context, problem);
      return;
    }
    f.startFromProject(project);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = _project;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'اختر ملف ZIP لمشروع Flutter جاهز (يحتوي pubspec.yaml ومجلد lib). '
              'سيقرأ التطبيق الملفات وينظّفها (build / .git ...) ثم يرفعها إلى مستودع جديد '
              'على حسابك ويبني المشروع على GitHub Actions.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _loading ? null : _pick,
          icon: const Icon(Icons.upload_file),
          label: Text(_fileName == null ? 'اختيار ملف ZIP' : 'تغيير الملف'),
        ),
        if (_loading) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ),
        ],
        if (project != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_fileName ?? '', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text('اسم المشروع: ${project.name}'),
                  Text('عدد الملفات: ${project.files.length}'),
                  Text('الحجم: ${_formatBytes(project.totalBytes)}'),
                  if (project.skipped.isNotEmpty)
                    Text('ملفات مستبعدة: ${project.skipped.length}'),
                  for (final n in project.notes) Text('• $n'),
                  if (project.warnings.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('تنبيهات (${project.warnings.length})'),
                      children: [
                        for (final w in project.warnings.take(30))
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text('• $w', style: theme.textTheme.bodySmall),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('الاحتفاظ بمجلدات المنصات (android / web)'),
          subtitle: const Text(
            'افتراضياً تُولَّد من جديد بأحدث قالب لتفادي أخطاء البناء. فعّلها فقط إن كانت لديك إعدادات أصلية مخصصة.',
          ),
          value: _keepPlatforms,
          onChanged: _loading
              ? null
              : (v) {
                  setState(() => _keepPlatforms = v);
                  if (_zipBytes != null) _parse();
                },
        ),
        const SizedBox(height: 8),
        const _TargetSelector(),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: (project == null || _loading) ? null : _start,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('رفع المشروع وبناؤه'),
        ),
      ],
    );
  }
}

// ======================================================================
// واجهة التنفيذ: التقدم + حالة كل منصة + المخرجات
// ======================================================================

class _RunView extends StatelessWidget {
  const _RunView();

  @override
  Widget build(BuildContext context) {
    final f = context.watch<FactoryController>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Color headerColor;
    IconData headerIcon;
    String headerTitle;
    switch (f.phase) {
      case FactoryPhase.success:
        headerColor = cs.primaryContainer;
        headerIcon = Icons.check_circle_outline;
        headerTitle = 'اكتمل بنجاح';
        break;
      case FactoryPhase.failure:
        headerColor = cs.errorContainer;
        headerIcon = Icons.error_outline;
        headerTitle = 'فشلت العملية';
        break;
      default:
        headerColor = cs.surfaceContainerHighest;
        headerIcon = Icons.hourglass_top;
        headerTitle = 'قيد التنفيذ';
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: headerColor,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(headerIcon),
                    const SizedBox(width: 8),
                    Text(headerTitle, style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                Text(f.working ? f.stageMessage : f.stage.label),
                if (f.working) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (f.error != null) ...[
                  const SizedBox(height: 8),
                  Text(f.error!, style: TextStyle(color: cs.error)),
                ],
              ],
            ),
          ),
        ),
        for (final b in f.builds) ...[
          const SizedBox(height: 12),
          _BuildCard(info: b),
        ],
        if (f.repo != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.source_outlined),
              title: Text(f.repo!.fullName),
              subtitle: const Text('مستودع GitHub'),
              trailing: IconButton(
                tooltip: 'فتح',
                icon: const Icon(Icons.open_in_new),
                onPressed: () async => _snack(context, await f.openUrl(f.repo!.htmlUrl)),
              ),
            ),
          ),
        ],
        if (f.files.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'حُفظ المشروع في «مشروعاتي» ويمكنك تعديله وإعادة بنائه.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        ExpansionTile(
          initiallyExpanded: f.phase != FactoryPhase.success,
          title: Text('السجل (${f.logs.length})'),
          children: [
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 280),
              padding: const EdgeInsets.all(8),
              color: cs.surfaceContainerHighest,
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  f.logs.join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (f.working)
          OutlinedButton.icon(
            onPressed: f.cancel,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('إلغاء'),
          )
        else ...[
          if (f.files.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () async => _snack(context, await f.exportProject()),
              icon: const Icon(Icons.archive_outlined),
              label: const Text('تصدير المشروع (ZIP)'),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: f.reset,
            icon: const Icon(Icons.add),
            label: const Text('مشروع جديد'),
          ),
        ],
      ],
    );
  }
}

class _BuildCard extends StatelessWidget {
  const _BuildCard({required this.info});

  final TargetBuild info;

  @override
  Widget build(BuildContext context) {
    final f = context.watch<FactoryController>();
    final cs = Theme.of(context).colorScheme;
    final b = info;

    Color chipColor;
    IconData icon;
    switch (b.status) {
      case BuildStatus.success:
        chipColor = cs.primaryContainer;
        icon = Icons.check_circle;
        break;
      case BuildStatus.failure:
        chipColor = cs.errorContainer;
        icon = Icons.cancel;
        break;
      case BuildStatus.cancelled:
        chipColor = cs.surfaceContainerHighest;
        icon = Icons.block;
        break;
      case BuildStatus.inProgress:
        chipColor = cs.tertiaryContainer;
        icon = Icons.autorenew;
        break;
      default:
        chipColor = cs.surfaceContainerHighest;
        icon = Icons.schedule;
    }

    final webLink = b.pagesUrl;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(b.target == SingleTarget.apk ? Icons.android : Icons.language),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    b.target.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  avatar: Icon(icon, size: 18),
                  label: Text(b.status.label),
                  backgroundColor: chipColor,
                  side: BorderSide.none,
                ),
              ],
            ),
            if (b.attempt > 1) Text('المحاولة ${b.attempt}'),
            if (b.note != null) ...[
              const SizedBox(height: 4),
              Text(b.note!, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (b.status == BuildStatus.inProgress || b.status == BuildStatus.queued) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (b.status == BuildStatus.success) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (b.hasArtifact)
                    FilledButton.icon(
                      onPressed: f.busy
                          ? null
                          : () async => _snack(context, await f.shareBuild(b)),
                      icon: f.busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: Text(
                        b.target == SingleTarget.apk
                            ? 'تنزيل APK${b.artifactSize != null ? ' (${_formatBytes(b.artifactSize!)})' : ''}'
                            : 'تنزيل نسخة الويب (ZIP)',
                      ),
                    ),
                  if (webLink != null) ...[
                    FilledButton.tonalIcon(
                      onPressed: () async => _snack(context, await f.openUrl(webLink)),
                      icon: const Icon(Icons.public),
                      label: const Text('فتح الموقع'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async => _snack(context, await f.shareLink(webLink, 'رابط الموقع')),
                      icon: const Icon(Icons.share),
                      label: const Text('مشاركة الرابط'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: webLink));
                        if (context.mounted) _snack(context, 'تم نسخ الرابط');
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('نسخ الرابط'),
                    ),
                  ],
                ],
              ),
            ],
            if (b.runUrl != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async => _snack(context, await f.openUrl(b.runUrl!)),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('عرض التشغيل على GitHub'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
