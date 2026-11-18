/// بيانات وصفية لمشروع محفوظ في مكتبة «مشروعاتي».
class ProjectMeta {
  const ProjectMeta({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.source = 'manual',
    this.idea,
    this.repoFullName,
    this.repoUrl,
    this.pagesUrl,
    this.lastTarget = 'apk',
    this.lastStatus = 'never',
    this.fileCount = 0,
    this.totalBytes = 0,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// idea | upload | manual
  final String source;
  final String? idea;
  final String? repoFullName;
  final String? repoUrl;
  final String? pagesUrl;

  /// اسم BuildTarget الأخير.
  final String lastTarget;

  /// never | building | success | failure
  final String lastStatus;
  final int fileCount;
  final int totalBytes;

  String get sourceLabel {
    switch (source) {
      case 'idea':
        return 'من فكرة';
      case 'upload':
        return 'مرفوع';
      default:
        return 'يدوي';
    }
  }

  String get statusLabel {
    switch (lastStatus) {
      case 'success':
        return 'آخر بناء: نجح';
      case 'failure':
        return 'آخر بناء: فشل';
      case 'building':
        return 'قيد البناء';
      default:
        return 'لم يُبنَ بعد';
    }
  }

  ProjectMeta copyWith({
    String? name,
    DateTime? updatedAt,
    String? idea,
    String? repoFullName,
    String? repoUrl,
    String? pagesUrl,
    String? lastTarget,
    String? lastStatus,
    int? fileCount,
    int? totalBytes,
  }) {
    return ProjectMeta(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source,
      idea: idea ?? this.idea,
      repoFullName: repoFullName ?? this.repoFullName,
      repoUrl: repoUrl ?? this.repoUrl,
      pagesUrl: pagesUrl ?? this.pagesUrl,
      lastTarget: lastTarget ?? this.lastTarget,
      lastStatus: lastStatus ?? this.lastStatus,
      fileCount: fileCount ?? this.fileCount,
      totalBytes: totalBytes ?? this.totalBytes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'source': source,
        'idea': idea,
        'repoFullName': repoFullName,
        'repoUrl': repoUrl,
        'pagesUrl': pagesUrl,
        'lastTarget': lastTarget,
        'lastStatus': lastStatus,
        'fileCount': fileCount,
        'totalBytes': totalBytes,
      };

  factory ProjectMeta.fromJson(Map<String, dynamic> j) {
    DateTime date(Object? v) => DateTime.tryParse('$v') ?? DateTime.now();
    return ProjectMeta(
      id: '${j['id']}',
      name: '${j['name'] ?? 'مشروع'}',
      createdAt: date(j['createdAt']),
      updatedAt: date(j['updatedAt']),
      source: '${j['source'] ?? 'manual'}',
      idea: j['idea'] as String?,
      repoFullName: j['repoFullName'] as String?,
      repoUrl: j['repoUrl'] as String?,
      pagesUrl: j['pagesUrl'] as String?,
      lastTarget: '${j['lastTarget'] ?? 'apk'}',
      lastStatus: '${j['lastStatus'] ?? 'never'}',
      fileCount: (j['fileCount'] as num?)?.toInt() ?? 0,
      totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
    );
  }
}
