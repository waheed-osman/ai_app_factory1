import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:yaml/yaml.dart';

import '../core/errors.dart';
import '../models/project_file.dart';
import 'project_packager.dart';
import 'project_validator.dart';

/// نتيجة قراءة ZIP مشروع جاهز.
class ImportedProject {
  const ImportedProject({
    required this.name,
    required this.files,
    required this.skipped,
    required this.notes,
    required this.warnings,
  });

  final String name;
  final List<ProjectFile> files;

  /// ملفات/مجلدات استُبعدت (build, .git, ...).
  final List<String> skipped;

  /// تعديلات أُجريت تلقائياً (مثل تحديث قيد sdk).
  final List<String> notes;

  /// تنبيهات من الفحص (واجهات قديمة...).
  final List<String> warnings;

  int get totalBytes => files.fold<int>(0, (s, f) => s + f.size);
}

/// يقرأ ZIP مشروع Flutter، ينظّفه ويجهّزه للرفع.
class ProjectImporter {
  ProjectImporter._();

  static const int maxFileBytes = 30 * 1024 * 1024;
  static const int maxTotalBytes = 80 * 1024 * 1024;

  static const Set<String> _excludedDirs = {
    '.git', '.dart_tool', 'build', '.idea', '.vscode', '.gradle',
    '.github', 'node_modules', '__MACOSX', '.fvm', '.pub-cache',
  };

  static const Set<String> _platformDirs = {
    'android', 'ios', 'web', 'linux', 'macos', 'windows',
  };

  static const Set<String> _excludedFiles = {
    'pubspec.lock', '.flutter-plugins', '.flutter-plugins-dependencies',
    '.packages', '.metadata', 'local.properties', '.DS_Store', 'Thumbs.db',
  };

  static const Set<String> _excludedExtensions = {'.apk', '.aab', '.iml', '.ipa'};

  /// قراءة ZIP في Isolate منفصل حتى لا تتجمد الواجهة.
  static Future<ImportedProject> importInBackground(
    Uint8List bytes, {
    bool keepPlatformFolders = false,
  }) {
    return Isolate.run(
      () => fromZipBytes(bytes, keepPlatformFolders: keepPlatformFolders),
    );
  }

  static ImportedProject fromZipBytes(
    Uint8List bytes, {
    bool keepPlatformFolders = false,
  }) {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FactoryException('الملف ليس مجلداً مضغوطاً (ZIP) صالحاً.');
    }

    final entries = <String, ArchiveFile>{};
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final path = _normalize(f.name);
      if (path == null) continue;
      entries[path] = f;
    }
    if (entries.isEmpty) {
      throw const FactoryException('الملف المضغوط فارغ.');
    }

    // إيجاد جذر المشروع: أقرب pubspec.yaml للجذر.
    String? root;
    for (final path in entries.keys) {
      if (path == 'pubspec.yaml' || path.endsWith('/pubspec.yaml')) {
        final dir = path == 'pubspec.yaml'
            ? ''
            : path.substring(0, path.length - 'pubspec.yaml'.length);
        if (_excludedPath(dir)) continue;
        if (root == null || dir.length < root.length) root = dir;
      }
    }
    if (root == null) {
      throw const FactoryException(
        'لم يُعثر على pubspec.yaml داخل الملف. تأكد أن الـ ZIP يحوي مشروع Flutter كاملاً.',
      );
    }

    final skipped = <String>[];
    final notes = <String>[];
    final files = <ProjectFile>[];
    var total = 0;

    for (final entry in entries.entries) {
      if (!entry.key.startsWith(root)) continue;
      final rel = entry.key.substring(root.length);
      if (rel.isEmpty) continue;

      final reason = _exclusionReason(rel, keepPlatformFolders);
      if (reason != null) {
        skipped.add(rel);
        continue;
      }
      final raw = entry.value.content;
      if (raw is! List<int>) continue;
      if (raw.length > maxFileBytes) {
        skipped.add('$rel (أكبر من ${maxFileBytes ~/ (1024 * 1024)}MB)');
        continue;
      }
      total += raw.length;
      if (total > maxTotalBytes) {
        throw FactoryException(
          'حجم المشروع يتجاوز ${maxTotalBytes ~/ (1024 * 1024)}MB. احذف الملفات الكبيرة (فيديو/صوت) وأعد المحاولة.',
        );
      }
      files.add(ProjectFile(rel, Uint8List.fromList(raw)));
    }

    final index = files.indexWhere((f) => f.path == 'pubspec.yaml');
    if (index < 0) {
      throw const FactoryException('pubspec.yaml is missing.');
    }

    final fixed = _fixSdkConstraint(files[index].text);
    if (fixed != null) {
      files[index] = ProjectFile.text('pubspec.yaml', fixed);
      notes.add('تم تحديث قيد sdk في pubspec.yaml ليتوافق مع أحدث Flutter.');
    }

    final validation = ProjectValidator.validate(files);
    if (validation.hasFatal) {
      throw FactoryException(
        'المشروع غير صالح: ${validation.fatal.join(' | ')}',
      );
    }

    final name = validation.packageName ??
        ProjectPackager.sanitizePackageName('project');
    return ImportedProject(
      name: name,
      files: files,
      skipped: skipped,
      notes: notes,
      warnings: [...validation.issues, ...validation.warnings],
    );
  }

  static String? _normalize(String raw) {
    var p = raw.replaceAll('\\', '/');
    while (p.startsWith('./')) {
      p = p.substring(2);
    }
    if (p.isEmpty || p.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(p)) {
      return null;
    }
    if (p.split('/').contains('..')) return null;
    return p;
  }

  static bool _excludedPath(String dir) {
    return dir.split('/').any(_excludedDirs.contains);
  }

  static String? _exclusionReason(String rel, bool keepPlatform) {
    final parts = rel.split('/');
    final name = parts.last;
    for (var i = 0; i < parts.length - 1; i++) {
      if (_excludedDirs.contains(parts[i])) return 'dir';
    }
    if (!keepPlatform && parts.length > 1 && _platformDirs.contains(parts.first)) {
      return 'platform';
    }
    if (_excludedFiles.contains(name)) return 'file';
    final dot = name.lastIndexOf('.');
    if (dot > 0 && _excludedExtensions.contains(name.substring(dot).toLowerCase())) {
      return 'ext';
    }
    return null;
  }

  /// يرفع قيد sdk إذا كان قديماً (<3.5 أو سقفه <4). يرجع null إن لم يلزم تعديل.
  static String? _fixSdkConstraint(String pubspec) {
    const wanted = '>=3.5.0 <4.0.0';
    try {
      final doc = loadYaml(pubspec);
      if (doc is! YamlMap) return null;
      final env = doc['environment'];
      final sdk = env is YamlMap ? env['sdk'] : null;
      if (sdk is! String) return null;
      final lower = RegExp(r'>=\s*(\d+)\.(\d+)').firstMatch(sdk);
      final upper = RegExp(r'<\s*(\d+)\.').firstMatch(sdk);
      var needs = false;
      if (lower != null) {
        final major = int.parse(lower.group(1)!);
        final minor = int.parse(lower.group(2)!);
        if (major < 3 || (major == 3 && minor < 5)) needs = true;
      }
      if (upper != null && int.parse(upper.group(1)!) < 4) needs = true;
      if (!needs) return null;
      final lines = pubspec.split('\n');
      var inEnv = false;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (RegExp(r'^environment\s*:').hasMatch(line)) {
          inEnv = true;
          continue;
        }
        if (inEnv) {
          if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('\t')) {
            inEnv = false;
            continue;
          }
          if (RegExp(r'^\s+sdk\s*:').hasMatch(line)) {
            lines[i] = line.replaceFirst(RegExp(r'sdk\s*:.*$'), 'sdk: "$wanted"');
            return lines.join('\n');
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
