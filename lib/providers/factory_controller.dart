import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/errors.dart';
import '../models/build_models.dart';
import '../models/project_file.dart';
import '../models/project_meta.dart';
import '../services/factory_pipeline.dart';
import '../services/background_service.dart';
import '../services/file_exporter.dart';
import '../services/github_builder.dart';
import '../services/http_transport.dart';
import '../models/ai_profile.dart';
import '../services/ai_router.dart';
import '../services/prompts.dart';
import '../services/project_importer.dart';
import '../services/response_parser.dart';
import 'projects_controller.dart';
import 'settings_controller.dart';

enum FactoryPhase { idle, working, success, failure }

class FactoryController extends ChangeNotifier {
  FactoryController(this._settings, this._projects) {
    _target = _settings.settings.defaultTarget;
  }

  final SettingsController _settings;
  final ProjectsController _projects;

  FactoryPhase phase = FactoryPhase.idle;
  PipelineStage stage = PipelineStage.preparing;
  String stageMessage = '';
  String? error;
  RepoRef? repo;
  List<TargetBuild> builds = const [];
  List<ProjectFile> files = const [];
  String projectName = 'app';
  bool busy = false;

  /// المشروع المحفوظ المرتبط بالتشغيل الحالي.
  String? projectId;
  String _source = 'idea';
  String? _idea;
  Future<void> _saveChain = Future<void>.value();

  final List<String> logs = [];

  BuildTarget _target = BuildTarget.apk;
  CancelToken? _cancel;
  HttpTransport? _transport;

  BuildTarget get target => _target;

  bool get working => phase == FactoryPhase.working;

  void setTarget(BuildTarget t) {
    _target = t;
    notifyListeners();
  }

  /// يتحقق من اكتمال الإعدادات قبل البدء. يرجع رسالة خطأ أو null.
  String? preflight({required bool needsLlm}) {
    final s = _settings.settings;
    if (!s.githubReady) {
      return 'أضف توكن GitHub في الإعدادات أولاً.';
    }
    if (needsLlm && !s.llmReady) {
      return 'أضف مفتاح الذكاء الاصطناعي في الإعدادات أولاً.';
    }
    return null;
  }

  /// يحوّل فكرة مختصرة إلى برومبت احترافي مفصّل (أو يعدّل مسودة سابقة).
  Future<String> enhancePrompt(
    String rough, {
    String? previous,
    String? instruction,
  }) async {
    final s = _settings.settings;
    final transport = HttpTransport();
    try {
      final router = AiRouter.create(settings: s, transport: transport, stats: _settings.stats);
      if (router == null) {
        throw const FactoryException('أضف أداة ذكاء اصطناعي واحدة على الأقل في الإعدادات أولاً.');
      }
      final out = await router.forRole(AiRole.enhance, check: QualityChecks.prompt).complete(
            system: Prompts.enhanceSystem(target: _target),
            user: Prompts.enhance(rough, previous: previous, instruction: instruction),
          );
      return _cleanPrompt(out);
    } finally {
      transport.close();
    }
  }

  static String _cleanPrompt(String raw) {
    var t = raw.trim();
    final fence = RegExp(r'^```[a-zA-Z]*\n([\s\S]*?)\n```$');
    final m = fence.firstMatch(t);
    if (m != null) t = m.group(1)!.trim();
    if (t.length > 1 && t.startsWith('"') && t.endsWith('"')) {
      t = t.substring(1, t.length - 1).trim();
    }
    return t;
  }

  Future<void> startFromIdea(String idea) {
    return _run(
      PipelineRequest(
        idea: idea.trim(),
        target: _target,
        autoFix: _settings.settings.autoFix,
      ),
      'app',
      source: 'idea',
      idea: idea.trim(),
    );
  }

  Future<void> startFromProject(ImportedProject project) {
    return _run(
      PipelineRequest(
        files: project.files,
        target: _target,
        autoFix: _settings.settings.autoFix && _settings.settings.llmReady,
      ),
      project.name,
      source: 'upload',
    );
  }

  /// بناء مشروع من المكتبة (على نفس المستودع إن وُجد).
  Future<void> startFromLibrary(
    ProjectMeta meta,
    List<ProjectFile> files,
    BuildTarget target,
  ) {
    _target = target;
    return _run(
      PipelineRequest(
        files: files,
        target: target,
        autoFix: _settings.settings.autoFix && _settings.settings.llmReady,
        existingRepo: meta.repoFullName,
      ),
      meta.name,
      source: meta.source,
      idea: meta.idea,
      existingId: meta.id,
    );
  }

  /// تعديل مشروع بالذكاء الاصطناعي. يرجع الملفات المعدّلة/المضافة فقط.
  Future<List<ProjectFile>> aiEdit(List<ProjectFile> files, String instruction, BuildTarget target) async {
    final transport = HttpTransport();
    try {
      final router = AiRouter.create(settings: _settings.settings, transport: transport, stats: _settings.stats);
      if (router == null) {
        throw const FactoryException('أضف أداة ذكاء اصطناعي واحدة على الأقل في الإعدادات أولاً.');
      }
      final raw = await router.forRole(AiRole.edit, check: QualityChecks.files).complete(
            system: Prompts.system(target: target),
            user: Prompts.edit(files: files, instruction: instruction),
          );
      return ResponseParser.parse(raw).where((f) => !f.path.startsWith('.github/')).toList();
    } finally {
      transport.close();
    }
  }

  /// حفظ مسلسل (لا يتداخل) لنسخة المشروع الحالية في المكتبة.
  void _queuePersist() {
    _saveChain = _saveChain.then((_) => _persistNow()).catchError((Object _) {});
  }

  Future<void> _persistNow() async {
    if (files.isEmpty) return;
    final now = DateTime.now();
    final existing = projectId == null ? null : _projects.byId(projectId!);
    final base = existing ??
        ProjectMeta(
          id: const Uuid().v4(),
          name: projectName,
          createdAt: now,
          updatedAt: now,
          source: _source,
          idea: _idea,
        );
    String? pages;
    for (final b in builds) {
      if (b.pagesUrl != null) pages = b.pagesUrl;
    }
    final status = phase == FactoryPhase.success
        ? 'success'
        : (phase == FactoryPhase.failure ? 'failure' : 'building');
    final meta = base.copyWith(
      repoFullName: repo?.fullName,
      repoUrl: repo?.htmlUrl,
      pagesUrl: pages,
      lastTarget: _target.name,
      lastStatus: status,
    );
    projectId = meta.id;
    await _projects.save(meta, files);
  }

  Future<void> _run(
    PipelineRequest req,
    String name, {
    String source = 'idea',
    String? idea,
    String? existingId,
  }) async {
    projectId = existingId;
    _source = source;
    _idea = idea;
    final s = _settings.settings;
    projectName = name;
    phase = FactoryPhase.working;
    error = null;
    repo = null;
    builds = const [];
    files = const [];
    logs.clear();
    stage = PipelineStage.preparing;
    stageMessage = PipelineStage.preparing.label;
    notifyListeners();

    final background = s.backgroundMode && BackgroundService.supported;
    _background = background;
    _stopTimer?.cancel();
    if (background) {
      await BackgroundService.requestPermissions();
      await BackgroundService.start(PipelineStage.preparing.label);
    }

    final cancel = CancelToken();
    final transport = HttpTransport();
    final github = GitHubBuilder(token: s.githubToken, transport: transport, cancel: cancel);
    _cancel = cancel;
    _transport = transport;

    final router = AiRouter.create(
      settings: s,
      transport: transport,
      stats: _settings.stats,
      onLog: _log,
    );
    final pipeline = FactoryPipeline(
      router: router,
      settings: s,
      github: github,
      transport: transport,
      cancel: cancel,
      listener: PipelineListener(
        onStage: (st, msg) {
          stage = st;
          stageMessage = msg;
          _syncNotification();
          notifyListeners();
        },
        onLog: _log,
        onBuilds: (b) {
          builds = b;
          _syncNotification();
          notifyListeners();
        },
        onRepo: (r) {
          repo = r;
          notifyListeners();
        },
        onFiles: (f) {
          files = f;
          _queuePersist();
        },
      ),
    );

    try {
      final result = await pipeline.run(req);
      files = result.files;
      repo = result.repo ?? repo;
      builds = result.builds;
      error = result.error;
      phase = result.success ? FactoryPhase.success : FactoryPhase.failure;
      stage = result.success ? PipelineStage.done : PipelineStage.failed;
    } on CancelledException {
      phase = FactoryPhase.failure;
      stage = PipelineStage.failed;
      error = 'تم إلغاء العملية.';
      logs.add('■ تم الإلغاء');
    } catch (e) {
      phase = FactoryPhase.failure;
      stage = PipelineStage.failed;
      error = friendlyError(e);
      logs.add('✖ ${friendlyError(e)}');
    } finally {
      _cancel = null;
      _transport?.close();
      _transport = null;
      _queuePersist();
      await _saveChain;
      await _finishBackground();
      notifyListeners();
    }
  }

  bool _background = false;
  Timer? _stopTimer;

  /// نص الإشعار الدائم: المرحلة + حالة كل منصة.
  void _syncNotification() {
    if (!_background) return;
    final parts = <String>[stageMessage];
    for (final b in builds) {
      parts.add('${b.target.label}: ${b.status.label}');
    }
    BackgroundService.update(parts.join(' • '));
  }

  /// يعرض النتيجة في الإشعار ثم يوقف الخدمة بعد دقيقتين.
  Future<void> _finishBackground() async {
    if (!_background) return;
    final text = phase == FactoryPhase.success
        ? 'اكتمل البناء بنجاح ✔ افتح التطبيق للتنزيل'
        : 'انتهت العملية: ${error ?? 'فشل'}';
    await BackgroundService.update(text);
    _stopTimer?.cancel();
    _stopTimer = Timer(const Duration(minutes: 2), () {
      BackgroundService.stop();
    });
  }

  void _log(String line) {
    logs.add(line);
    if (logs.length > 400) logs.removeRange(0, logs.length - 400);
    notifyListeners();
  }

  void cancel() {
    _cancel?.cancel();
  }

  void reset() {
    if (working) return;
    _stopTimer?.cancel();
    BackgroundService.stop();
    phase = FactoryPhase.idle;
    error = null;
    repo = null;
    builds = const [];
    files = const [];
    logs.clear();
    notifyListeners();
  }

  // ------------------------------------------------------------ مخرجات

  /// يحمّل الـ Artifact ويشاركه (APK مستخرج، أو ZIP للويب). يرجع خطأ أو null.
  Future<String?> shareBuild(TargetBuild b) async {
    final r = repo;
    final id = b.artifactId;
    if (r == null || id == null) return 'لا يوجد ملف ناتج لهذه المنصة.';
    if (busy) return null;
    busy = true;
    notifyListeners();
    final transport = HttpTransport();
    try {
      final github = GitHubBuilder(token: _settings.settings.githubToken, transport: transport);
      final zip = await github.downloadArtifact(r, id);
      if (b.target == SingleTarget.apk) {
        final apk = FileExporter.extractApk(zip);
        await FileExporter.shareFile('$projectName.apk', apk);
      } else {
        await FileExporter.shareFile('$projectName-web.zip', zip);
      }
      return null;
    } catch (e) {
      return friendlyError(e);
    } finally {
      transport.close();
      busy = false;
      notifyListeners();
    }
  }

  Future<String?> exportProject() async {
    if (files.isEmpty) return 'لا توجد ملفات لتصديرها.';
    try {
      await FileExporter.shareProjectZip(files, projectName);
      return null;
    } catch (e) {
      return friendlyError(e);
    }
  }

  Future<String?> openUrl(String url) async {
    try {
      await FileExporter.openUrl(url);
      return null;
    } catch (e) {
      return friendlyError(e);
    }
  }

  Future<String?> shareLink(String url, String title) async {
    try {
      await FileExporter.shareText(url, subject: title);
      return null;
    } catch (e) {
      return friendlyError(e);
    }
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    _cancel?.cancel();
    _transport?.close();
    super.dispose();
  }
}
