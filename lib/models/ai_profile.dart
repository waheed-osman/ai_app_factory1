/// أدوار (تخصصات) المهام التي يمكن توجيهها لأداة ذكاء اصطناعي معيّنة.
enum AiRole { generate, fix, edit, enhance }

extension AiRoleX on AiRole {
  String get label {
    switch (this) {
      case AiRole.generate:
        return 'توليد';
      case AiRole.fix:
        return 'إصلاح';
      case AiRole.edit:
        return 'تعديل';
      case AiRole.enhance:
        return 'تحسين البرومبت';
    }
  }
}

/// نوع واجهة الأداة.
enum AiKind { openai, anthropic, gemini }

extension AiKindX on AiKind {
  String get label {
    switch (this) {
      case AiKind.openai:
        return 'متوافق مع OpenAI';
      case AiKind.anthropic:
        return 'Claude';
      case AiKind.gemini:
        return 'Gemini';
    }
  }
}

const Set<AiRole> kAllRoles = {AiRole.generate, AiRole.fix, AiRole.edit, AiRole.enhance};

/// أداة ذكاء اصطناعي واحدة ضمن قائمة التنقل التلقائي.
class AiProfile {
  const AiProfile({
    required this.id,
    required this.name,
    this.kind = AiKind.openai,
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.enabled = true,
    this.roles = kAllRoles,
    this.priority = 5,
    this.maxTokens = 8192,
  });

  final String id;
  final String name;
  final AiKind kind;

  /// رابط API الكامل حتى /v1 (لنوع OpenAI فقط).
  final String baseUrl;
  final String apiKey;
  final String model;
  final bool enabled;
  final Set<AiRole> roles;

  /// 1 = الأعلى أولوية، 9 = الأدنى.
  final int priority;
  final int maxTokens;

  bool get isUsable {
    if (!enabled || model.trim().isEmpty) return false;
    switch (kind) {
      case AiKind.openai:
        return baseUrl.trim().isNotEmpty;
      case AiKind.anthropic:
      case AiKind.gemini:
        return apiKey.trim().isNotEmpty;
    }
  }

  AiProfile copyWith({
    String? name,
    AiKind? kind,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? enabled,
    Set<AiRole>? roles,
    int? priority,
    int? maxTokens,
  }) {
    return AiProfile(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      enabled: enabled ?? this.enabled,
      roles: roles ?? this.roles,
      priority: priority ?? this.priority,
      maxTokens: maxTokens ?? this.maxTokens,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'enabled': enabled,
        'roles': roles.map((r) => r.name).toList(),
        'priority': priority,
        'maxTokens': maxTokens,
      };

  factory AiProfile.fromJson(Map<String, dynamic> j) {
    final roleNames = (j['roles'] is List) ? (j['roles'] as List).map((e) => '$e').toSet() : <String>{};
    final roles = AiRole.values.where((r) => roleNames.contains(r.name)).toSet();
    return AiProfile(
      id: '${j['id']}',
      name: '${j['name'] ?? 'أداة'}',
      kind: AiKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => AiKind.openai),
      baseUrl: '${j['baseUrl'] ?? ''}',
      apiKey: '${j['apiKey'] ?? ''}',
      model: '${j['model'] ?? ''}',
      enabled: j['enabled'] != false,
      roles: roles.isEmpty ? kAllRoles : roles,
      priority: ((j['priority'] as num?)?.toInt() ?? 5).clamp(1, 9).toInt(),
      maxTokens: (j['maxTokens'] as num?)?.toInt() ?? 8192,
    );
  }
}

/// قالب جاهز لأداة مجانية شائعة. النماذج الافتراضية اقتراحات: تحقق منها بزر «جلب النماذج».
class AiPreset {
  const AiPreset({
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.roles,
    required this.priority,
    required this.note,
    this.keyUrl = '',
    this.keyPrefixes = const [],
    this.kind = AiKind.openai,
    this.maxTokens = 8192,
  });

  final String name;
  final String baseUrl;
  final String model;
  final Set<AiRole> roles;
  final int priority;
  final String note;

  /// صفحة إنشاء مفتاح API لدى المزود.
  final String keyUrl;

  /// بدايات شكل المفتاح للتعرف عليه تلقائياً من الحافظة.
  final List<String> keyPrefixes;
  final AiKind kind;
  final int maxTokens;

  AiProfile toProfile(String id) => AiProfile(
        id: id,
        name: name,
        kind: kind,
        baseUrl: baseUrl,
        model: model,
        roles: roles,
        priority: priority,
        maxTokens: maxTokens,
      );

  static const List<AiPreset> all = [
    AiPreset(
      name: 'Gemini (مجاني)',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      model: 'gemini-flash-lite-latest',
      roles: kAllRoles,
      priority: 1,
      maxTokens: 16000,
      note: 'سياق كبير وحصة مجانية؛ مفتاح من Google AI Studio. مناسب للتوليد.',
      keyUrl: 'https://aistudio.google.com/apikey',
      keyPrefixes: ['AIza', 'AQ.'],
    ),
    AiPreset(
      name: 'Groq (الأسرع)',
      baseUrl: 'https://api.groq.com/openai/v1',
      model: 'llama-3.3-70b-versatile',
      roles: {AiRole.enhance, AiRole.fix, AiRole.edit},
      priority: 2,
      note: 'سرعة عالية جداً؛ ممتاز للإصلاح والتعديل وتحسين البرومبت.',
      keyUrl: 'https://console.groq.com/keys',
      keyPrefixes: ['gsk_'],
    ),
    AiPreset(
      name: 'Cerebras (سريع)',
      baseUrl: 'https://api.cerebras.ai/v1',
      model: 'llama-3.3-70b',
      roles: {AiRole.enhance, AiRole.fix, AiRole.edit},
      priority: 3,
      note: 'سرعة عالية بحصة مجانية. تأكد من اسم النموذج المتاح لحسابك.',
      keyUrl: 'https://cloud.cerebras.ai/platform',
      keyPrefixes: ['csk-'],
    ),
    AiPreset(
      name: 'OpenRouter (نماذج :free)',
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'deepseek/deepseek-chat-v3-0324:free',
      roles: {AiRole.generate, AiRole.fix},
      priority: 3,
      maxTokens: 16000,
      note: 'اختر نموذج برمجة ينتهي اسمه بـ :free من قائمة «الموديلات المتاحة».',
      keyUrl: 'https://openrouter.ai/settings/keys',
      keyPrefixes: ['sk-or-'],
    ),
    AiPreset(
      name: 'GitHub Models',
      baseUrl: 'https://models.github.ai/inference',
      model: 'openai/gpt-4.1',
      roles: kAllRoles,
      priority: 4,
      note: 'المفتاح: GitHub token بصلاحية models. له حدود استخدام مجانية.',
      keyUrl: 'https://github.com/settings/personal-access-tokens/new',
      keyPrefixes: ['github_pat_', 'ghp_'],
    ),
    AiPreset(
      name: 'Mistral',
      baseUrl: 'https://api.mistral.ai/v1',
      model: 'mistral-large-latest',
      roles: {AiRole.generate, AiRole.edit},
      priority: 4,
      note: 'مستوى مجاني للتجربة من لوحة Mistral.',
      keyUrl: 'https://console.mistral.ai/api-keys',
    ),
    AiPreset(
      name: 'NVIDIA NIM',
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      model: 'meta/llama-3.3-70b-instruct',
      roles: {AiRole.generate, AiRole.fix},
      priority: 5,
      note: 'رصيد مجاني للمطورين من build.nvidia.com.',
      keyUrl: 'https://build.nvidia.com/settings/api-keys',
      keyPrefixes: ['nvapi-'],
    ),
    AiPreset(
      name: 'OmniRoute',
      baseUrl: 'http://localhost:20128/v1',
      model: '',
      roles: kAllRoles,
      priority: 2,
      note: 'بوابة توجّه هي أيضاً بين مزودين؛ اكتب اسم الـ Combo أو النموذج.',
    ),
    AiPreset(
      name: 'Claude (Anthropic)',
      baseUrl: '',
      model: 'claude-sonnet-5-5',
      roles: kAllRoles,
      priority: 6,
      kind: AiKind.anthropic,
      maxTokens: 16000,
      note: 'مدفوع (ليس ضمن الخطط المجانية)، لكنه الأدق في توليد الكود.',
      keyUrl: 'https://console.anthropic.com/settings/keys',
      keyPrefixes: ['sk-ant-'],
    ),
  ];

  static String _norm(String s) => s.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();

  /// القالب المطابق لأداة موجودة (لمعرفة صفحة المفتاح).
  static AiPreset? matchFor(AiProfile p) {
    for (final x in all) {
      if (x.kind != p.kind) continue;
      if (p.kind == AiKind.openai) {
        if (x.baseUrl.isNotEmpty && _norm(x.baseUrl) == _norm(p.baseUrl)) return x;
      } else {
        return x;
      }
    }
    if (p.kind == AiKind.gemini) {
      return all.firstWhere((x) => x.keyPrefixes.contains('AIza'));
    }
    return null;
  }

  /// يتعرف على نوع المفتاح من شكله (مثل AIza... لجوجل و gsk_... لـ Groq).
  static AiPreset? detectFromKey(String key) {
    final k = key.trim();
    for (final x in all) {
      for (final prefix in x.keyPrefixes) {
        if (k.startsWith(prefix)) return x;
      }
    }
    return null;
  }
}
