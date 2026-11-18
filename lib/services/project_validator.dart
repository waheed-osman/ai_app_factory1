import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/project_file.dart';

class ValidationResult {
  const ValidationResult({
    this.packageName,
    this.fatal = const [],
    this.issues = const [],
    this.warnings = const [],
  });

  /// اسم الحزمة من pubspec.yaml (إن وُجد وكان صالحاً).
  final String? packageName;

  /// أخطاء بنيوية تمنع البناء كلياً (pubspec مفقود...).
  final List<String> fatal;

  /// أخطاء ستفشل التجميع غالباً (استيراد غير موجود...).
  final List<String> issues;

  /// تنبيهات (واجهات قديمة Deprecated...).
  final List<String> warnings;

  bool get hasFatal => fatal.isNotEmpty;

  bool get ok => fatal.isEmpty && issues.isEmpty;

  List<String> get allErrors => [...fatal, ...issues];
}

class ProjectValidator {
  ProjectValidator._();

  static final RegExp _importRe = RegExp(
    r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );

  static final RegExp _nameRe = RegExp(r'^[a-z][a-z0-9_]*$');

  /// واجهات أُزيلت أو أصبحت Deprecated: تُعرض كتنبيهات وتُرسل للنموذج عند الإصلاح.
  static final List<MapEntry<RegExp, String>> _deprecated = [
    MapEntry(RegExp(r'\b(FlatButton|RaisedButton|OutlineButton)\b'),
        'واجهة محذوفة: استخدم TextButton/ElevatedButton/OutlinedButton'),
    MapEntry(RegExp(r'\.withOpacity\('), 'Deprecated: استخدم Color.withValues(alpha:)'),
    MapEntry(RegExp(r'\bWillPopScope\b'), 'Deprecated: استخدم PopScope'),
    MapEntry(RegExp(r'\bMaterialState(Property)?\b'), 'Deprecated: استخدم WidgetState/WidgetStateProperty'),
    MapEntry(RegExp(r'\btextScaleFactor\b'), 'Deprecated: استخدم textScaler'),
    MapEntry(RegExp(r'\b(headline[1-6]|bodyText[12]|subtitle[12])\b'),
        'محذوف: استخدم titleLarge/bodyMedium... من textTheme'),
    MapEntry(RegExp(r'\bonBackground\b'), 'Deprecated: استخدم onSurface'),
    MapEntry(RegExp(r'\baccentColor\s*:'), 'محذوف من ThemeData: استخدم colorScheme'),
    MapEntry(RegExp(r"import\s+['\x22]dart:html['\x22]"), 'dart:html قديمة: استخدم package:web'),
  ];

  static ValidationResult validate(List<ProjectFile> files) {
    final fatal = <String>[];
    final issues = <String>[];
    final warnings = <String>[];
    final byPath = <String, ProjectFile>{for (final f in files) f.path: f};

    final pubspec = byPath['pubspec.yaml'];
    if (pubspec == null) {
      return const ValidationResult(fatal: ['pubspec.yaml is missing.']);
    }

    String? name;
    final declared = <String>{};
    try {
      final doc = loadYaml(pubspec.text);
      if (doc is! YamlMap) {
        fatal.add('pubspec.yaml ليس ملف YAML صالحاً.');
      } else {
        final n = doc['name'];
        if (n is String && _nameRe.hasMatch(n)) {
          name = n;
          declared.add(n);
        } else {
          fatal.add("pubspec.yaml has no valid top-level 'name:' field.");
        }
        final deps = doc['dependencies'];
        final hasFlutter = deps is YamlMap && deps['flutter'] != null;
        if (!hasFlutter) {
          fatal.add("pubspec.yaml must depend on the 'flutter' SDK package.");
        }
        for (final key in const ['dependencies', 'dev_dependencies', 'dependency_overrides']) {
          final section = doc[key];
          if (section is YamlMap) {
            for (final k in section.keys) {
              declared.add('$k');
            }
          }
        }
      }
    } catch (e) {
      fatal.add('تعذر قراءة pubspec.yaml: $e');
    }

    if (!byPath.containsKey('lib/main.dart')) {
      fatal.add('lib/main.dart مفقود.');
    }

    final analysis = byPath['analysis_options.yaml'];
    if (analysis != null &&
        analysis.text.contains('flutter_lints') &&
        !declared.contains('flutter_lints')) {
      warnings.add(
        'analysis_options.yaml includes flutter_lints but pubspec.yaml does not list flutter_lints in dev_dependencies.',
      );
    }

    if (fatal.isNotEmpty) {
      return ValidationResult(
        packageName: name,
        fatal: fatal,
        issues: issues,
        warnings: warnings,
      );
    }

    for (final f in files.where((f) => f.isDart)) {
      final text = f.text;
      for (final m in _importRe.allMatches(text)) {
        final uri = m.group(1)!;
        if (uri.startsWith('dart:')) continue;
        if (uri.endsWith('.g.dart') || uri.endsWith('.freezed.dart')) continue;
        if (uri.startsWith('package:')) {
          final rest = uri.substring('package:'.length);
          final slash = rest.indexOf('/');
          if (slash < 0) continue;
          final pkg = rest.substring(0, slash);
          final inner = rest.substring(slash + 1);
          if (pkg == name) {
            if (!byPath.containsKey('lib/$inner')) {
              issues.add("${f.path}: الاستيراد '$uri' يشير إلى ملف غير موجود (lib/$inner).");
            }
          } else if (!declared.contains(pkg)) {
            issues.add("${f.path}: imports '$pkg' which is not declared in pubspec.yaml.");
          }
        } else if (!uri.contains('://')) {
          final target = p.posix.normalize(p.posix.join(p.posix.dirname(f.path), uri));
          if (!byPath.containsKey(target)) {
            issues.add("${f.path}: الاستيراد '$uri' غير موجود (يتوقع $target).");
          }
        }
      }
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final d in _deprecated) {
          if (d.key.hasMatch(lines[i])) {
            warnings.add('${f.path}:${i + 1}: ${d.value}');
          }
        }
      }
    }

    return ValidationResult(
      packageName: name,
      fatal: fatal,
      issues: issues,
      warnings: warnings,
    );
  }
}
