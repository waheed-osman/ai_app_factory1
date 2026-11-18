import 'package:uuid/uuid.dart';

import '../core/errors.dart';
import '../models/app_settings.dart';
import '../models/build_models.dart';
import '../models/project_file.dart';
import '../models/ai_profile.dart';
import 'ai_router.dart';
import 'github_builder.dart';
import 'http_transport.dart';
import 'project_packager.dart';
import 'project_validator.dart';
import 'prompts.dart';
import 'response_parser.dart';

class PipelineRequest {
  PipelineRequest({
    this.idea,
    this.files,
    required this.target,
    required this.autoFix,
    this.existingRepo,
  });

  /// مستودع سبق إنشاؤه لهذا المشروع (owner/name) لإعادة استخدامه.
  final String? existingRepo;

  /// وصف التطبيق (يُولَّد بالذكاء الاصطناعي).
  final String? idea;

  /// مشروع جاهز مرفوع (بدلاً من التوليد).
  final List<ProjectFile>? files;

  final BuildTarget target;
  final bool autoFix;

  bool get isUpload => files != null;
}

class PipelineListener {
  PipelineListener({
    required this.onStage,
    required this.onLog,
    required this.onBuilds,
    required this.onRepo,
    this.onFiles,
  });

  /// يُستدعى كلما توفرت نسخة جديدة من ملفات المشروع (للحفظ المبكر).
  final void Function(List<ProjectFile> files)? onFiles;

  final void Function(PipelineStage stage, String message) onStage;
  final void Function(String line) onLog;
  final void Function(List<TargetBuild> builds) onBuilds;
  final void Function(RepoRef repo) onRepo;
}

class PipelineResult {
  const PipelineResult({
    required this.success,
    required this.files,
    this.repo,
    this.builds = const [],
    this.error,
  });

  final bool success;
  final List<ProjectFile> files;
  final RepoRef? repo;
  final List<TargetBuild> builds;
  final String? error;
}

/// خط الإنتاج: (توليد | رفع مشروع) → فحص → مستودع → رفع → بناء → إصلاح ذاتي.
class FactoryPipeline {
  FactoryPipeline({
    required this.settings,
    required this.github,
    required this.transport,
    required this.listener,
    required this.cancel,
    this.router,
  });

  /// موجّه الذكاء الاصطناعي (تنقل تلقائي بين الأدوات). null إن لم تُضبط أي أداة.
  final AiRouter? router;

  final AppSettings settings;
  final GitHubBuilder github;
  final HttpTransport transport;
  final PipelineListener listener;
  final CancelToken cancel;

  final Map<SingleTarget, TargetBuild> _builds = {};
  BuildTarget _target = BuildTarget.apk;

  void _stage(PipelineStage s, [String? msg]) {
    listener.onStage(s, msg ?? s.label);
    listener.onLog('▶ ${msg ?? s.label}');
  }

  void _emit() => listener.onBuilds(_builds.values.toList());

  void _setBuild(SingleTarget t, TargetBuild Function(TargetBuild b) f) {
    _builds[t] = f(_builds[t] ?? TargetBuild(target: t));
    _emit();
  }

  Future<PipelineResult> run(PipelineRequest req) async {
    var files = <ProjectFile>[];
    RepoRef? repo;
    _target = req.target;
    {
      final llm = router;

      // 1) المصدر: توليد أو مشروع مرفوع.
      _stage(PipelineStage.preparing);
      if (req.isUpload) {
        files = List<ProjectFile>.of(req.files!);
        listener.onLog('تم تجهيز ${files.length} ملفاً من المشروع المرفوع.');
      } else {
        if (llm == null) {
          throw const FactoryException('أضف مفتاح الذكاء الاصطناعي في الإعدادات أولاً.');
        }
        _stage(PipelineStage.generating, 'توليد الكود بالذكاء الاصطناعي...');
        final raw = await llm.forRole(AiRole.generate, check: QualityChecks.project).complete(
          system: Prompts.system(target: req.target),
          user: Prompts.generate(req.idea ?? ''),
        );
        cancel.check();
        files = ResponseParser.parse(raw);
        listener.onLog('تم توليد ${files.length} ملفاً.');
      }

      // 2) الفحص (والإصلاح المحلي قبل الرفع للمشاريع المولَّدة).
      _stage(PipelineStage.validating);
      var validation = ProjectValidator.validate(files);
      var localFix = 0;
      while (!req.isUpload &&
          !validation.ok &&
          llm != null &&
          localFix < 2) {
        localFix++;
        _stage(PipelineStage.fixing, 'إصلاح أخطاء الفحص (محاولة $localFix)...');
        files = await _applyFix(llm, files, '', validation.allErrors);
        validation = ProjectValidator.validate(files);
      }
      if (validation.hasFatal) {
        throw FactoryException('المشروع غير صالح: ${validation.fatal.join(' | ')}');
      }
      for (final w in validation.issues) {
        listener.onLog('⚠ $w');
      }
      final projectName = validation.packageName ?? 'app';
      listener.onFiles?.call(List<ProjectFile>.of(files));

      // 3) المستودع.
      _stage(PipelineStage.creatingRepo);
      final owner = await github.currentUser();
      listener.onLog('الحساب: $owner');
      final repoName = _repoName(projectName);
      RepoRef? reused;
      if (req.existingRepo != null) {
        reused = await github.getRepo(req.existingRepo!);
        if (reused != null) listener.onLog('إعادة استخدام المستودع ${reused.fullName}');
      }
      repo = reused ?? await github.createRepo(
        repoName,
        private: settings.privateRepos,
        description: req.isUpload
            ? 'Uploaded Flutter project built by AI App Factory'
            : 'Flutter app generated by AI App Factory',
      );
      listener.onRepo(repo);
      listener.onLog('تم إنشاء المستودع ${repo.fullName}');

      for (final t in req.target.singles) {
        _builds[t] = TargetBuild(target: t);
      }
      _emit();

      // 4) رفع + بناء + إصلاح ذاتي.
      final canFix = req.autoFix && llm != null;
      final maxAttempts = canFix ? settings.maxFixAttempts : 0;
      String? lastError;
      for (var attempt = 0; attempt <= maxAttempts; attempt++) {
        cancel.check();
        final bundle = ProjectPackager.withWorkflows(
          files,
          target: req.target,
          projectName: projectName,
          repoName: repo.name,
          strictTests: !req.isUpload,
          publishPages: settings.publishWebToPages,
        );
        _stage(
          PipelineStage.uploading,
          'رفع ${bundle.length} ملفاً (المحاولة ${attempt + 1})...',
        );
        final sha = await github.pushFiles(
          repo,
          bundle,
          attempt == 0 ? 'Initial commit by AI App Factory' : 'Auto-fix attempt $attempt',
        );
        listener.onLog('Commit: ${sha.substring(0, 7)}');

        _stage(PipelineStage.building, 'البناء على GitHub Actions...');
        for (final t in req.target.singles) {
          _setBuild(
            t,
            (b) => TargetBuild(target: t, attempt: attempt + 1, status: BuildStatus.queued),
          );
        }
        final outcomes = await Future.wait(
          req.target.singles.map((t) => _buildOne(repo!, t, attempt + 1)),
        );

        if (outcomes.every((o) => o == null)) {
          await _afterSuccess(repo, req.target);
          _stage(PipelineStage.done, 'اكتمل البناء بنجاح');
          return PipelineResult(
            success: true,
            files: files,
            repo: repo,
            builds: _builds.values.toList(),
          );
        }

        final failures = outcomes.whereType<String>().toList();
        lastError = 'فشل البناء';
        if (attempt >= maxAttempts || llm == null) break;

        _stage(PipelineStage.fixing, 'الإصلاح الذاتي: تحليل الأخطاء (${attempt + 1}/$maxAttempts)...');
        final log = failures.join('\n\n');
        files = await _applyFix(
          llm,
          files,
          log,
          [...ProjectValidator.validate(files).allErrors],
        );
      }

      _stage(PipelineStage.failed, lastError ?? 'فشل البناء');
      return PipelineResult(
        success: false,
        files: files,
        repo: repo,
        builds: _builds.values.toList(),
        error: canFix
            ? 'فشل البناء بعد ${settings.maxFixAttempts} محاولات إصلاح ذاتي. راجع السجل في GitHub.'
            : 'فشل البناء. راجع سجل GitHub Actions أو فعّل الإصلاح الذاتي وأضف مفتاح الذكاء الاصطناعي.',
      );
    }
  }

  /// يبني منصة واحدة. يرجع null عند النجاح، أو نص سجل الفشل.
  Future<String?> _buildOne(RepoRef repo, SingleTarget t, int attempt) async {
    try {
      final run = await github.startWorkflow(repo, t.workflowFile);
      _setBuild(t, (b) => b.copyWith(runId: run.id, runUrl: run.htmlUrl, status: run.buildStatus));
      listener.onLog('[${t.label}] بدأ التشغيل #${run.id}');

      final done = await github.waitForRun(
        repo,
        run.id,
        onUpdate: (info) {
          final current = _builds[t];
          if (current != null && current.status != info.buildStatus) {
            _setBuild(t, (b) => b.copyWith(status: info.buildStatus));
          }
        },
      );
      _setBuild(t, (b) => b.copyWith(status: done.buildStatus, runUrl: done.htmlUrl));

      if (done.buildStatus == BuildStatus.success) {
        listener.onLog('[${t.label}] نجح البناء');
        try {
          final artifacts = await github.listArtifacts(repo, run.id);
          for (final a in artifacts) {
            if (a.name == t.artifactName && !a.expired) {
              _setBuild(t, (b) => b.copyWith(artifactId: a.id, artifactSize: a.sizeInBytes));
              break;
            }
          }
        } on FactoryException catch (e) {
          listener.onLog('[${t.label}] تعذر قراءة الملف الناتج: ${e.message}');
        }
        return null;
      }

      listener.onLog('[${t.label}] فشل البناء (${done.conclusion})');
      final summary = await github.failureSummary(repo, run.id);
      return '[${t.label}]\n$summary';
    } on CancelledException {
      rethrow;
    } on FactoryException catch (e) {
      _setBuild(t, (b) => b.copyWith(status: BuildStatus.failure, note: e.message));
      listener.onLog('[${t.label}] خطأ: ${e.message}');
      return '[${t.label}] ${e.message}';
    }
  }

  Future<void> _afterSuccess(RepoRef repo, BuildTarget target) async {
    if (!target.hasWeb || !settings.publishWebToPages) return;
    final b = _builds[SingleTarget.web];
    if (b == null || b.status != BuildStatus.success) return;
    try {
      final url = await github.enablePages(repo);
      if (url != null) {
        _setBuild(
          SingleTarget.web,
          (x) => x.copyWith(
            pagesUrl: url,
            note: 'قد يستغرق ظهور الموقع دقيقة أو دقيقتين بعد التفعيل.',
          ),
        );
        listener.onLog('رابط الموقع: $url');
      } else {
        _setBuild(
          SingleTarget.web,
          (x) => x.copyWith(
            note: 'تعذر تفعيل GitHub Pages تلقائياً (قد يتطلب مستودعاً عاماً). حمّل ملف الويب من الأسفل.',
          ),
        );
        listener.onLog('تعذر تفعيل GitHub Pages تلقائياً.');
      }
    } on FactoryException catch (e) {
      listener.onLog('تعذر تفعيل Pages: ${e.message}');
    }
  }

  Future<List<ProjectFile>> _applyFix(
    AiRouter llm,
    List<ProjectFile> files,
    String log,
    List<String> issues,
  ) async {
    cancel.check();
    final raw = await llm.forRole(AiRole.fix, check: QualityChecks.files).complete(
      system: Prompts.system(target: _target),
      user: Prompts.fix(files: files, log: log, issues: issues),
    );
    cancel.check();
    final changes = ResponseParser.parse(raw)
        .where((f) => !f.path.startsWith('.github/'))
        .toList();
    listener.onLog('الإصلاح الذاتي عدّل ${changes.length} ملفاً: ${changes.map((e) => e.path).join(', ')}');
    final merged = ProjectPackager.merge(files, changes);
    listener.onFiles?.call(List<ProjectFile>.of(merged));
    return merged;
  }

  String _repoName(String projectName) {
    final suffix = const Uuid().v4().substring(0, 6);
    final base = projectName.replaceAll('_', '-');
    return '$base-$suffix';
  }
}
