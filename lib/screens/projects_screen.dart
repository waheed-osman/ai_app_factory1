import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/errors.dart';
import '../models/project_meta.dart';
import '../providers/projects_controller.dart';
import '../services/project_importer.dart';
import '../services/project_templates.dart';
import 'project_detail_screen.dart';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  bool _busy = false;

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _add() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('رفع مشروع من ملف ZIP'),
              subtitle: const Text('يُحفظ في المكتبة دون بناء فوري'),
              onTap: () => Navigator.of(ctx).pop('zip'),
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('مشروع Flutter فارغ'),
              subtitle: const Text('قالب بسيط تعدّله بنفسك أو بالذكاء الاصطناعي'),
              onTap: () => Navigator.of(ctx).pop('blank'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'zip') await _addZip();
    if (choice == 'blank') await _addBlank();
  }

  Future<void> _addZip() async {
    final projects = context.read<ProjectsController>();
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      Uint8List? bytes = picked.bytes;
      if (bytes == null && picked.path != null) {
        bytes = await File(picked.path!).readAsBytes();
      }
      if (bytes == null) throw const FactoryException('تعذر قراءة الملف المحدد.');
      final project = await ProjectImporter.importInBackground(bytes);
      final now = DateTime.now();
      final meta = ProjectMeta(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: project.name,
        createdAt: now,
        updatedAt: now,
        source: 'upload',
      );
      await projects.save(meta, project.files);
      _toast('تمت إضافة «${project.name}» (${project.files.length} ملفاً)');
    } catch (e) {
      _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addBlank() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اسم المشروع'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'مثال: مدير المهام'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    final projects = context.read<ProjectsController>();
    try {
      final now = DateTime.now();
      final meta = ProjectMeta(
        id: now.microsecondsSinceEpoch.toString(),
        name: name,
        createdAt: now,
        updatedAt: now,
      );
      await projects.save(meta, ProjectTemplates.blank(name));
      _toast('تم إنشاء «$name»');
    } catch (e) {
      _toast(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = context.watch<ProjectsController>().items;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('مشروعاتي')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _add,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
        label: const Text('إضافة مشروع'),
      ),
      body: SafeArea(
        child: items.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 64, color: cs.outline),
                      const SizedBox(height: 12),
                      const Text(
                        'لا توجد مشاريع بعد.\nالمشاريع التي تصنعها أو ترفعها تُحفظ هنا تلقائياً.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final m = items[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(
                          m.source == 'idea'
                              ? Icons.auto_awesome
                              : (m.source == 'upload' ? Icons.folder_zip_outlined : Icons.edit_note),
                        ),
                      ),
                      title: Text(m.name),
                      subtitle: Text(
                        '${m.sourceLabel} • ${m.fileCount} ملفات • ${formatBytes(m.totalBytes)}\n'
                        '${m.statusLabel} • ${formatDate(m.updatedAt)}',
                      ),
                      isThreeLine: true,
                      trailing: Icon(
                        m.lastStatus == 'success'
                            ? Icons.check_circle
                            : (m.lastStatus == 'failure' ? Icons.error_outline : Icons.chevron_left),
                        color: m.lastStatus == 'success'
                            ? cs.primary
                            : (m.lastStatus == 'failure' ? cs.error : null),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => ProjectDetailScreen(projectId: m.id)),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
