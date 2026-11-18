import 'dart:io';
import 'dart:typed_data';

import 'package:ai_app_factory/core/errors.dart';
import 'package:ai_app_factory/models/ai_profile.dart';
import 'package:ai_app_factory/models/build_models.dart';
import 'package:ai_app_factory/models/project_file.dart';
import 'package:ai_app_factory/models/project_meta.dart';
import 'package:ai_app_factory/services/ai_router.dart';
import 'package:ai_app_factory/services/http_transport.dart';
import 'package:ai_app_factory/services/llm_client.dart';
import 'package:ai_app_factory/services/project_importer.dart';
import 'package:ai_app_factory/services/project_packager.dart';
import 'package:ai_app_factory/services/project_store.dart';
import 'package:ai_app_factory/services/project_templates.dart';
import 'package:ai_app_factory/services/project_validator.dart';
import 'package:ai_app_factory/services/response_parser.dart';
import 'package:ai_app_factory/services/workflow_templates.dart';
import 'package:flutter_test/flutter_test.dart';

const String _pubspec = '''
name: demo_app
environment:
  sdk: ">=2.17.0 <3.0.0"
dependencies:
  flutter:
    sdk: flutter
''';

List<ProjectFile> _sampleProject() => [
      ProjectFile.text('pubspec.yaml', _pubspec),
      ProjectFile.text('lib/main.dart', "import 'package:flutter/material.dart';\nvoid main() {}\n"),
    ];

class _FakeLlm implements LlmClient {
  _FakeLlm(this.result, {this.error});

  final String result;
  final Object? error;
  int calls = 0;

  @override
  Future<String> complete({required String system, required String user}) async {
    calls++;
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  group('ResponseParser', () {
    test('parses file blocks', () {
      const raw = '### FILE: lib/main.dart\n```dart\nvoid main() {}\n```\n\n'
          '### FILE: pubspec.yaml\n```yaml\nname: a\n```\n';
      final files = ResponseParser.parse(raw);
      expect(files.length, 2);
      expect(files.first.path, 'lib/main.dart');
      expect(files.first.text, 'void main() {}\n');
    });

    test('rejects unsafe paths', () {
      expect(ResponseParser.cleanPath('../evil.dart'), isNull);
      expect(ResponseParser.cleanPath('/abs/path.dart'), isNull);
      expect(ResponseParser.cleanPath('lib/ok.dart'), 'lib/ok.dart');
    });

    test('throws on truncated output', () {
      expect(
        () => ResponseParser.parse('### FILE: lib/a.dart\n```dart\nvoid a() {'),
        throwsA(isA<FactoryException>()),
      );
    });
  });

  group('ProjectValidator', () {
    test('accepts a minimal project', () {
      final r = ProjectValidator.validate(_sampleProject());
      expect(r.hasFatal, isFalse);
      expect(r.packageName, 'demo_app');
    });

    test('reports missing pubspec', () {
      final r = ProjectValidator.validate([ProjectFile.text('lib/main.dart', 'void main() {}')]);
      expect(r.hasFatal, isTrue);
    });

    test('reports unresolved import', () {
      final files = [
        ..._sampleProject(),
        ProjectFile.text('lib/a.dart', "import 'missing.dart';\n"),
      ];
      final r = ProjectValidator.validate(files);
      expect(r.issues, isNotEmpty);
    });
  });

  group('ProjectImporter', () {
    test('imports zip, strips root folder and junk, fixes sdk', () {
      final zip = ProjectPackager.zip([
        ProjectFile.text('demo/pubspec.yaml', _pubspec),
        ProjectFile.text('demo/lib/main.dart', 'void main() {}\n'),
        ProjectFile.text('demo/build/out.txt', 'junk'),
        ProjectFile.text('demo/.git/config', 'junk'),
        ProjectFile.text('demo/android/app/build.gradle', 'junk'),
      ]);
      final project = ProjectImporter.fromZipBytes(Uint8List.fromList(zip));
      final paths = project.files.map((f) => f.path).toList()..sort();
      expect(paths, ['lib/main.dart', 'pubspec.yaml']);
      expect(project.name, 'demo_app');
      final pubspec = project.files.firstWhere((f) => f.path == 'pubspec.yaml');
      expect(pubspec.text.contains('>=3.5.0 <4.0.0'), isTrue);
    });

    test('rejects zip without pubspec', () {
      final zip = ProjectPackager.zip([ProjectFile.text('lib/main.dart', 'void main() {}')]);
      expect(
        () => ProjectImporter.fromZipBytes(Uint8List.fromList(zip)),
        throwsA(isA<FactoryException>()),
      );
    });
  });

  group('OmniRouteClient', () {
    test('builds OpenAI-compatible endpoints', () {
      expect(
        OmniRouteClient.endpoint('http://localhost:20128/', 'chat/completions').toString(),
        'http://localhost:20128/v1/chat/completions',
      );
      expect(
        OmniRouteClient.endpoint('https://x.example.com/v1', 'models').toString(),
        'https://x.example.com/v1/models',
      );
      expect(
        OmniRouteClient.endpoint('192.168.1.5:20128', 'models').toString(),
        'http://192.168.1.5:20128/v1/models',
      );
    });
  });

  group('ProjectStore', () {
    test('saves, lists, loads and deletes projects', () async {
      final dir = Directory.systemTemp.createTempSync('factory_store_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = ProjectStore(root: dir);
      final now = DateTime.now();
      final meta = ProjectMeta(id: 'p1', name: 'تجربة', createdAt: now, updatedAt: now);

      final saved = await store.save(meta, _sampleProject());
      expect(saved.fileCount, 2);

      final list = await store.list();
      expect(list.length, 1);
      expect(list.first.name, 'تجربة');

      final files = await store.loadFiles('p1');
      expect(files.map((f) => f.path).toList()..sort(), ['lib/main.dart', 'pubspec.yaml']);

      await store.delete('p1');
      expect(await store.list(), isEmpty);
    });

    test('blank template passes validation', () {
      final files = ProjectTemplates.blank('مدير المهام');
      final r = ProjectValidator.validate(files);
      expect(r.hasFatal, isFalse);
      expect(r.ok, isTrue);
    });
  });

  group('HttpTransport.explain', () {
    test('explains DNS and permission failures', () {
      expect(
        HttpTransport.explain(const SocketException('Failed host lookup: x.com')).contains('DNS'),
        isTrue,
      );
      expect(
        HttpTransport.explain(const SocketException('Connection failed (OS Error: Operation not permitted, errno = 1)')).contains('INTERNET'),
        isTrue,
      );
    });
  });

  group('AiPreset key detection', () {
    test('detects provider from key shape', () {
      expect(AiPreset.detectFromKey('AIzaSyExample')?.name, startsWith('Gemini'));
      expect(AiPreset.detectFromKey('AQ.Ab8example')?.name, startsWith('Gemini'));
      expect(AiPreset.detectFromKey('gsk_abc')?.name, startsWith('Groq'));
      expect(AiPreset.detectFromKey('sk-or-v1-abc')?.name, startsWith('OpenRouter'));
      expect(AiPreset.detectFromKey('sk-ant-abc')?.name, startsWith('Claude'));
      expect(AiPreset.detectFromKey('hello'), isNull);
    });

    test('matches an existing profile to its preset key page', () {
      final p = AiPreset.all.firstWhere((x) => x.name.startsWith('Groq')).toProfile('1');
      expect(AiPreset.matchFor(p)?.keyUrl, 'https://console.groq.com/keys');
    });
  });

  group('AiRouter', () {
    const goodFiles = '### FILE: lib/main.dart\n```dart\nvoid main() {}\n```\n';

    AiCandidate cand(String id, int priority, LlmClient c, {Set<AiRole> roles = kAllRoles}) =>
        AiCandidate(id: id, name: id, roles: roles, priority: priority, client: c);

    test('falls back to the next tool when the first fails', () async {
      final a = _FakeLlm('', error: const ApiException('limit', statusCode: 429));
      final b = _FakeLlm(goodFiles);
      final stats = ProviderStats();
      final router = AiRouter([cand('a', 1, a), cand('b', 2, b)], stats);
      final out = await router.forRole(AiRole.generate, check: QualityChecks.files).complete(system: 's', user: 'u');
      expect(out, goodFiles);
      expect(a.calls, 1);
      expect(b.calls, 1);
      expect(router.lastUsed, 'b');
      expect(stats.stat('a').fail, 1);
      expect(stats.cooldownLeftSeconds('a'), greaterThan(0));
      expect(stats.stat('b').ok, 1);
    });

    test('moves on when output fails the quality check', () async {
      final a = _FakeLlm('no files here');
      final b = _FakeLlm(goodFiles);
      final router = AiRouter([cand('a', 1, a), cand('b', 2, b)], ProviderStats());
      final out = await router.forRole(AiRole.fix, check: QualityChecks.files).complete(system: 's', user: 'u');
      expect(out, goodFiles);
    });

    test('prefers tools specialised for the role', () {
      final router = AiRouter([
        cand('fast', 1, _FakeLlm(''), roles: {AiRole.enhance}),
        cand('coder', 5, _FakeLlm(''), roles: {AiRole.generate}),
      ], ProviderStats());
      expect(router.order(AiRole.generate).first.id, 'coder');
      expect(router.order(AiRole.enhance).first.id, 'fast');
    });

    test('puts cooling-down tools last', () {
      final stats = ProviderStats();
      final router = AiRouter([cand('a', 1, _FakeLlm('')), cand('b', 3, _FakeLlm(''))], stats);
      stats.recordFailure('a', const ApiException('x', statusCode: 429));
      expect(router.order(AiRole.generate).first.id, 'b');
    });

    test('throws when every tool fails', () async {
      final router = AiRouter([cand('a', 1, _FakeLlm('', error: const NetworkException('down')))], ProviderStats());
      expect(
        () => router.forRole(AiRole.generate).complete(system: 's', user: 'u'),
        throwsA(isA<FactoryException>()),
      );
    });
  });

  group('WorkflowTemplates', () {
    test('web workflow builds web and uploads build/web', () {
      final y = WorkflowTemplates.web(projectName: 'demo_app', repoName: 'demo-app-abc123');
      expect(y.contains('flutter build web --release'), isTrue);
      expect(y.contains('path: build/web'), isTrue);
      expect(y.contains('--base-href "/demo-app-abc123/"'), isTrue);
      expect(y.contains('__'), isFalse);
    });

    test('apk workflow builds release apk', () {
      final y = WorkflowTemplates.apk(projectName: 'demo_app');
      expect(y.contains('flutter build apk --release'), isTrue);
      expect(y.contains('--project-name demo_app'), isTrue);
    });

    test('withWorkflows adds only requested targets', () {
      final files = ProjectPackager.withWorkflows(
        _sampleProject(),
        target: BuildTarget.web,
        projectName: 'demo_app',
        repoName: 'demo',
      );
      final paths = files.map((f) => f.path);
      expect(paths.contains(WorkflowTemplates.webPath), isTrue);
      expect(paths.contains(WorkflowTemplates.apkPath), isFalse);
    });
  });
}
