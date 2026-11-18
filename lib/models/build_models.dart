/// نوع البناء المطلوب من المستخدم.
enum BuildTarget { apk, web, both }

extension BuildTargetX on BuildTarget {
  String get label {
    switch (this) {
      case BuildTarget.apk:
        return 'APK أندرويد';
      case BuildTarget.web:
        return 'نسخة ويب';
      case BuildTarget.both:
        return 'APK + ويب';
    }
  }

  bool get hasApk => this != BuildTarget.web;

  bool get hasWeb => this != BuildTarget.apk;

  List<SingleTarget> get singles => <SingleTarget>[
        if (hasApk) SingleTarget.apk,
        if (hasWeb) SingleTarget.web,
      ];

  static BuildTarget fromName(String? name) {
    for (final t in BuildTarget.values) {
      if (t.name == name) return t;
    }
    return BuildTarget.apk;
  }
}

/// منصة بناء واحدة (لكل منصة ملف workflow و Artifact مستقل).
enum SingleTarget { apk, web }

extension SingleTargetX on SingleTarget {
  String get label => this == SingleTarget.apk ? 'APK أندرويد' : 'نسخة ويب';

  String get workflowFile =>
      this == SingleTarget.apk ? 'build_apk.yml' : 'build_web.yml';

  String get artifactName => this == SingleTarget.apk ? 'apk' : 'web';
}

/// حالة البناء كما تُعرض للمستخدم.
enum BuildStatus { pending, queued, inProgress, success, failure, cancelled }

extension BuildStatusX on BuildStatus {
  String get label {
    switch (this) {
      case BuildStatus.pending:
        return 'في الانتظار';
      case BuildStatus.queued:
        return 'في الطابور';
      case BuildStatus.inProgress:
        return 'قيد التنفيذ';
      case BuildStatus.success:
        return 'نجح';
      case BuildStatus.failure:
        return 'فشل';
      case BuildStatus.cancelled:
        return 'أُلغي';
    }
  }

  bool get isFinished =>
      this == BuildStatus.success ||
      this == BuildStatus.failure ||
      this == BuildStatus.cancelled;
}

/// حالة بناء منصة واحدة.
class TargetBuild {
  const TargetBuild({
    required this.target,
    this.status = BuildStatus.pending,
    this.attempt = 1,
    this.runId,
    this.runUrl,
    this.artifactId,
    this.artifactSize,
    this.pagesUrl,
    this.note,
  });

  final SingleTarget target;
  final BuildStatus status;
  final int attempt;
  final int? runId;
  final String? runUrl;
  final int? artifactId;
  final int? artifactSize;
  final String? pagesUrl;
  final String? note;

  bool get hasArtifact => artifactId != null;

  TargetBuild copyWith({
    BuildStatus? status,
    int? attempt,
    int? runId,
    String? runUrl,
    int? artifactId,
    int? artifactSize,
    String? pagesUrl,
    String? note,
  }) {
    return TargetBuild(
      target: target,
      status: status ?? this.status,
      attempt: attempt ?? this.attempt,
      runId: runId ?? this.runId,
      runUrl: runUrl ?? this.runUrl,
      artifactId: artifactId ?? this.artifactId,
      artifactSize: artifactSize ?? this.artifactSize,
      pagesUrl: pagesUrl ?? this.pagesUrl,
      note: note ?? this.note,
    );
  }
}

/// مراحل خط الإنتاج.
enum PipelineStage {
  preparing,
  generating,
  validating,
  creatingRepo,
  uploading,
  building,
  fixing,
  done,
  failed,
}

extension PipelineStageX on PipelineStage {
  String get label {
    switch (this) {
      case PipelineStage.preparing:
        return 'تجهيز المشروع';
      case PipelineStage.generating:
        return 'توليد الكود بالذكاء الاصطناعي';
      case PipelineStage.validating:
        return 'فحص المشروع';
      case PipelineStage.creatingRepo:
        return 'إنشاء مستودع GitHub';
      case PipelineStage.uploading:
        return 'رفع الملفات إلى GitHub';
      case PipelineStage.building:
        return 'البناء على GitHub Actions';
      case PipelineStage.fixing:
        return 'الإصلاح الذاتي';
      case PipelineStage.done:
        return 'اكتمل';
      case PipelineStage.failed:
        return 'فشل';
    }
  }
}
