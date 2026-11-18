import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/build_models.dart';
import '../models/project_file.dart';
import 'workflow_templates.dart';

/// تجهيز المشروع للرفع (إضافة ملفات الـ workflow) وضغطه.
class ProjectPackager {
  ProjectPackager._();

  /// يدمج التغييرات فوق المشروع (الملف الجديد يستبدل القديم بنفس المسار).
  static List<ProjectFile> merge(List<ProjectFile> base, List<ProjectFile> changes) {
    final map = <String, ProjectFile>{for (final f in base) f.path: f};
    for (final c in changes) {
      map[c.path] = c;
    }
    return map.values.toList();
  }

  /// يزيل أي مجلد .github قديم ثم يضيف ملفات الـ workflow المطلوبة للمنصات.
  static List<ProjectFile> withWorkflows(
    List<ProjectFile> files, {
    required BuildTarget target,
    required String projectName,
    required String repoName,
    bool strictTests = false,
    bool publishPages = true,
  }) {
    final result = files.where((f) => !f.path.startsWith('.github/')).toList();
    for (final t in target.singles) {
      result.add(
        ProjectFile.text(
          WorkflowTemplates.pathFor(t),
          WorkflowTemplates.forTarget(
            t,
            projectName: projectName,
            repoName: repoName,
            strictTests: strictTests,
            publishPages: publishPages,
          ),
        ),
      );
    }
    return result;
  }

  /// ضغط الملفات في ZIP.
  static Uint8List zip(List<ProjectFile> files) {
    final archive = Archive();
    for (final f in files) {
      archive.addFile(ArchiveFile(f.path, f.size, f.bytes));
    }
    final List<int>? raw = ZipEncoder().encode(archive);
    return Uint8List.fromList(raw ?? const <int>[]);
  }

  /// فك ZIP محفوظ مسبقاً إلى ملفات.
  static List<ProjectFile> unzip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <ProjectFile>[];
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final c = f.content;
      if (c is List<int>) files.add(ProjectFile(f.name, Uint8List.fromList(c)));
    }
    return files;
  }

  /// اسم حزمة Dart صالح (lower_snake_case).
  static String sanitizePackageName(String input) {
    var s = input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    if (s.isEmpty) s = 'app';
    if (RegExp(r'^[0-9]').hasMatch(s)) s = 'app_$s';
    return s;
  }
}
