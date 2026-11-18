import '../models/build_models.dart';
import '../models/project_file.dart';

class Prompts {
  Prompts._();

  static const String _system = r'''
You are a senior Flutter/Dart engineer. You turn an app idea into a complete, compilable Flutter application.
OUTPUT FORMAT (strict, parsed by a program):
- For every file, write a header line exactly like: ### FILE: relative/path
- Right after the header, write ONE fenced code block with the COMPLETE content of that file.
- Write nothing outside file blocks: no explanations, no summaries, no notes.
- Paths are relative to the project root. Never use absolute paths or "..".
PROJECT RULES:
- Always include: pubspec.yaml, analysis_options.yaml, lib/main.dart and at least one unit test under test/ (never name it widget_test.dart).
- Do NOT output android/, ios/, web/, desktop folders or .github/. The factory generates them.
- pubspec.yaml: lower_snake_case package name; environment sdk ">=3.5.0 <4.0.0"; dependencies use caret versions of well-known pub.dev packages you are sure exist; keep dependencies minimal; dev_dependencies must contain flutter_test and flutter_lints (^5.0.0).
- Use Material 3, null safety and a clean structure: lib/core, lib/models, lib/providers or lib/services, lib/screens, lib/widgets.
- State management: provider unless the idea clearly needs something else. Persist data locally with shared_preferences when needed.
- Every file must be complete. No TODO comments, no placeholders, no "rest of the code" shortcuts.
- Every import must resolve: use package:<package_name>/... or correct relative paths, and every symbol you use must be defined.
- Do not require API keys or native platform configuration unless the idea demands it.
- Use the language of the idea for all UI strings. For right-to-left languages wrap the app with Directionality in MaterialApp.builder instead of adding localization packages.
- Use ONLY current, non-deprecated Flutter APIs: Color.withValues(alpha: x) instead of withOpacity, PopScope instead of WillPopScope, WidgetState/WidgetStateProperty instead of MaterialState*, ColorScheme.surface/onSurface instead of background/onBackground, textScaler instead of textScaleFactor, FilledButton/ElevatedButton/TextButton instead of RaisedButton/FlatButton, Theme.of(context).textTheme.titleLarge etc. instead of headline*/bodyText*.
''';

  static const String _webRules = r'''
- The app MUST also compile and run on Flutter Web: do not import dart:io or dart:html in shared code, and do not use plugins that lack web support (use only web-compatible packages).
''';

  static const String _fixFooter =
      'Return ONLY the files that must change or must be added, each one complete, using the same output format. Do not repeat unchanged files.';

  static String system({required BuildTarget target}) {
    return target.hasWeb ? '$_system$_webRules' : _system;
  }

  static const String _enhanceSystem = r'''
You are an expert product manager and prompt engineer for an AI app generator that builds complete Flutter apps.
Rewrite the user's rough app idea into ONE professional, detailed prompt that the generator can follow precisely.
RULES:
- Output ONLY the final prompt text. No preface, no explanations, no code, no markdown headings with #.
- Write in the SAME language as the user's idea (Arabic stays Arabic).
- Keep the user's intent; fill gaps with sensible, realistic decisions. Never invent paid services or API keys.
- Use this structure with short plain-text section titles followed by concise bullet lines starting with "- ":
  1. Overview (one or two sentences: what the app is and the problem it solves)
  2. Target users
  3. Core features (prioritized, 5-8 items, each concrete and testable)
  4. Screens and navigation (list every screen and what it contains)
  5. Data and storage (local-first: what is stored, simple models)
  6. UI/UX (Material 3, colors/mood, RTL when the language is right-to-left, empty/loading/error states)
  7. Edge cases and validation
  8. Constraints (single Flutter project, works offline, no external API keys, minimal dependencies, clean structure)
- Be specific and compact: 250-400 words total.
''';

  static String enhanceSystem({required BuildTarget target}) {
    final hint = target == BuildTarget.apk
        ? 'The app targets Android (APK).'
        : target == BuildTarget.web
            ? 'The app targets Flutter Web: responsive layout, no dart:io usage, web-compatible packages only.'
            : 'The app targets both Android (APK) and Flutter Web: responsive layout, no dart:io in shared code, web-compatible packages only.';
    return '$_enhanceSystem\n$hint';
  }

  static String enhance(String rough, {String? previous, String? instruction}) {
    final b = StringBuffer('ROUGH IDEA:\n${rough.trim()}');
    if (previous != null && previous.trim().isNotEmpty) {
      b.write('\n\nCURRENT PROMPT DRAFT:\n${previous.trim()}');
    }
    if (instruction != null && instruction.trim().isNotEmpty) {
      b.write('\n\nUSER REQUESTED CHANGES:\n${instruction.trim()}');
    }
    b.write('\n\nReturn the improved professional prompt now.');
    return b.toString();
  }

  static String generate(String idea) {
    return 'APP IDEA:\n${idea.trim()}\n\nReturn every project file in the required format.';
  }

  /// طلب إصلاح بعد فشل البناء أو فشل الفحص.
  static String fix({
    required List<ProjectFile> files,
    required String log,
    List<String> issues = const [],
    int maxChars = 120000,
  }) {
    final b = StringBuffer()
      ..writeln('The project below failed to build on CI. Fix every error.')
      ..writeln()
      ..writeln('BUILD OUTPUT:')
      ..writeln(log.trim().isEmpty ? '(no log available)' : log.trim());
    if (issues.isNotEmpty) {
      b
        ..writeln()
        ..writeln('KNOWN ISSUES:');
      for (final i in issues) {
        b.writeln('- $i');
      }
    }
    b
      ..writeln()
      ..writeln('PROJECT FILES:');

    final candidates = files.where(_isSource).toList()
      ..sort((a, c) {
        final ma = log.contains(a.path) ? 0 : 1;
        final mc = log.contains(c.path) ? 0 : 1;
        if (ma != mc) return ma - mc;
        return a.path.compareTo(c.path);
      });

    var used = b.length;
    for (final f in candidates) {
      final block = '### FILE: ${f.path}\n```\n${f.text}\n```\n';
      if (used + block.length > maxChars) continue;
      b.write(block);
      used += block.length;
    }
    b
      ..writeln()
      ..write(_fixFooter);
    return b.toString();
  }

  /// طلب تعديل مشروع قائم حسب تعليمات المستخدم.
  static String edit({
    required List<ProjectFile> files,
    required String instruction,
    int maxChars = 120000,
  }) {
    final b = StringBuffer()
      ..writeln('Apply the following change request to the Flutter project below.')
      ..writeln('Keep the project compilable, keep every import resolvable and keep all existing features working.')
      ..writeln()
      ..writeln('CHANGE REQUEST:')
      ..writeln(instruction.trim())
      ..writeln()
      ..writeln('PROJECT FILES:');
    var used = b.length;
    final sorted = files.where(_isSource).toList()
      ..sort((a, c) => a.path.compareTo(c.path));
    for (final f in sorted) {
      final block = '### FILE: ${f.path}\n```\n${f.text}\n```\n';
      if (used + block.length > maxChars) continue;
      b.write(block);
      used += block.length;
    }
    b
      ..writeln()
      ..write(_fixFooter);
    return b.toString();
  }

  static bool _isSource(ProjectFile f) {
    final p = f.path;
    if (p == 'pubspec.yaml' || p == 'analysis_options.yaml') return true;
    return (p.startsWith('lib/') || p.startsWith('test/')) &&
        (p.endsWith('.dart') || p.endsWith('.json') || p.endsWith('.yaml'));
  }
}
