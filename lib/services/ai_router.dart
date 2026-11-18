import 'dart:async';
import 'dart:convert';

import '../core/errors.dart';
import '../models/ai_profile.dart';
import '../models/app_settings.dart';
import 'http_transport.dart';
import 'llm_client.dart';
import 'project_validator.dart';
import 'response_parser.dart';

/// إحصاءات أداء أداة واحدة (تُحفظ وتُستخدم لترتيب الأدوات تلقائياً).
class ProviderStat {
  int ok = 0;
  int fail = 0;
  double avgMs = 0;
  int cooldownUntilMs = 0;
  String? lastError;

  int get total => ok + fail;

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'fail': fail,
        'avgMs': avgMs,
        'cooldownUntilMs': cooldownUntilMs,
        'lastError': lastError,
      };

  static ProviderStat fromJson(Map<String, dynamic> j) {
    return ProviderStat()
      ..ok = (j['ok'] as num?)?.toInt() ?? 0
      ..fail = (j['fail'] as num?)?.toInt() ?? 0
      ..avgMs = (j['avgMs'] as num?)?.toDouble() ?? 0
      ..cooldownUntilMs = (j['cooldownUntilMs'] as num?)?.toInt() ?? 0
      ..lastError = j['lastError'] as String?;
  }
}

class ProviderStats {
  ProviderStats();

  final Map<String, ProviderStat> _map = {};

  /// يُستدعى بعد كل تغيير (للحفظ وتحديث الواجهة).
  void Function()? onChanged;

  ProviderStat stat(String id) => _map.putIfAbsent(id, ProviderStat.new);

  int cooldownLeftSeconds(String id) {
    final left = stat(id).cooldownUntilMs - DateTime.now().millisecondsSinceEpoch;
    return left > 0 ? (left / 1000).ceil() : 0;
  }

  void recordSuccess(String id, int ms) {
    final s = stat(id);
    s.avgMs = s.avgMs == 0 ? ms.toDouble() : s.avgMs * 0.7 + ms * 0.3;
    s.ok++;
    s.cooldownUntilMs = 0;
    s.lastError = null;
    onChanged?.call();
  }

  void recordFailure(String id, Object error) {
    final s = stat(id);
    s.fail++;
    s.lastError = friendlyError(error);
    s.cooldownUntilMs = DateTime.now().millisecondsSinceEpoch + cooldownFor(error).inMilliseconds;
    onChanged?.call();
  }

  void reset(String id) {
    _map.remove(id);
    onChanged?.call();
  }

  /// مدة إيقاف الأداة مؤقتاً حسب نوع الخطأ.
  static Duration cooldownFor(Object error) {
    if (error is ApiException) {
      final code = error.statusCode ?? 0;
      if (code == 429) return const Duration(minutes: 5);
      if (code == 401 || code == 403) return const Duration(minutes: 30);
      if (code == 400 || code == 404) return const Duration(minutes: 10);
      if (code >= 500) return const Duration(minutes: 2);
    }
    if (error is NetworkException || error is TimeoutException) {
      return const Duration(minutes: 2);
    }
    return const Duration(seconds: 30);
  }

  String toJsonString() => jsonEncode({for (final e in _map.entries) e.key: e.value.toJson()});

  void loadJsonString(String? raw) {
    _map.clear();
    if (raw == null || raw.isEmpty) return;
    try {
      final d = jsonDecode(raw);
      if (d is Map) {
        for (final e in d.entries) {
          if (e.value is Map) {
            _map['${e.key}'] = ProviderStat.fromJson(Map<String, dynamic>.from(e.value as Map));
          }
        }
      }
    } catch (_) {}
  }
}

/// فحوص جودة المخرجات: إن فشل الفحص ينتقل الموجّه للأداة التالية.
class QualityChecks {
  QualityChecks._();

  static String? files(String out) {
    try {
      ResponseParser.parse(out);
      return null;
    } on FactoryException catch (e) {
      return e.message;
    }
  }

  static String? project(String out) {
    try {
      final v = ProjectValidator.validate(ResponseParser.parse(out));
      return v.hasFatal ? v.fatal.join(' | ') : null;
    } on FactoryException catch (e) {
      return e.message;
    }
  }

  static String? prompt(String out) => out.trim().length < 80 ? 'البرومبت المُولَّد قصير جداً' : null;
}

/// أداة جاهزة للاستخدام داخل الموجّه.
class AiCandidate {
  AiCandidate({
    required this.id,
    required this.name,
    required this.roles,
    required this.priority,
    required this.client,
  });

  final String id;
  final String name;
  final Set<AiRole> roles;
  final int priority;
  final LlmClient client;
}

typedef OutputCheck = String? Function(String output);

/// موجّه التنقل التلقائي بين أدوات الذكاء الاصطناعي.
class AiRouter {
  AiRouter(this.candidates, this.stats, {this.onLog});

  final List<AiCandidate> candidates;
  final ProviderStats stats;
  final void Function(String line)? onLog;

  /// اسم آخر أداة نجحت.
  String? lastUsed;

  /// ينشئ عميلاً لأداة (يُستخدم أيضاً لاختبار الأداة من الواجهة).
  static LlmClient clientFor(AiProfile p, HttpTransport t) {
    switch (p.kind) {
      case AiKind.anthropic:
        return AnthropicClient(apiKey: p.apiKey.trim(), model: p.model.trim(), transport: t, maxTokens: p.maxTokens);
      case AiKind.gemini:
        return GeminiClient(apiKey: p.apiKey.trim(), model: p.model.trim(), transport: t, maxTokens: p.maxTokens);
      case AiKind.openai:
        return OmniRouteClient(
          baseUrl: p.baseUrl,
          apiKey: p.apiKey.trim(),
          model: p.model.trim(),
          transport: t,
          maxTokens: p.maxTokens,
          autoV1: false,
        );
    }
  }

  /// ينشئ الموجّه من الإعدادات، أو null إن لم توجد أي أداة جاهزة.
  static AiRouter? create({
    required AppSettings settings,
    required HttpTransport transport,
    required ProviderStats stats,
    void Function(String line)? onLog,
  }) {
    final list = <AiCandidate>[];
    if (settings.smartRouting) {
      for (final p in settings.profiles.where((p) => p.isUsable)) {
        list.add(AiCandidate(
          id: p.id,
          name: p.name,
          roles: p.roles,
          priority: p.priority,
          client: clientFor(p, transport),
        ));
      }
    }
    final legacy = LlmClient.fromSettings(settings, transport);
    if (legacy != null) {
      list.add(AiCandidate(
        id: 'legacy',
        name: 'الأداة الافتراضية',
        roles: kAllRoles,
        priority: 9,
        client: legacy,
      ));
    }
    if (list.isEmpty) return null;
    return AiRouter(list, stats, onLog: onLog);
  }

  /// ترتيب الأدوات لدور معيّن: الأولوية + معدل الفشل + بطء الاستجابة، والموقوفة مؤقتاً في الآخر.
  List<AiCandidate> order(AiRole role) {
    final now = DateTime.now().millisecondsSinceEpoch;
    var list = candidates.where((c) => c.roles.contains(role)).toList();
    if (list.isEmpty) list = List<AiCandidate>.of(candidates);
    double score(AiCandidate c) {
      final s = stats.stat(c.id);
      var v = c.priority * 10.0;
      if (s.total >= 2) {
        v += (s.fail / s.total) * 25.0;
        v += (s.avgMs / 60000.0).clamp(0.0, 3.0).toDouble() * 4.0;
      }
      if (s.cooldownUntilMs > now) v += 1000.0 + (s.cooldownUntilMs - now) / 1000.0;
      return v;
    }

    list.sort((a, b) => score(a).compareTo(score(b)));
    return list;
  }

  LlmClient forRole(AiRole role, {OutputCheck? check}) => _RoleClient(this, role, check);

  void _log(String line) => onLog?.call(line);
}

class _RoleClient implements LlmClient {
  _RoleClient(this._router, this._role, this._check);

  final AiRouter _router;
  final AiRole _role;
  final OutputCheck? _check;

  Duration get _attemptTimeout =>
      _role == AiRole.enhance ? const Duration(seconds: 120) : const Duration(minutes: 5);

  @override
  Future<String> complete({required String system, required String user}) async {
    final ordered = _router.order(_role);
    final errors = <String>[];
    for (var i = 0; i < ordered.length; i++) {
      final c = ordered[i];
      final sw = Stopwatch()..start();
      _router._log('🤖 [${_role.label}] ${c.name}...');
      try {
        final out = await c.client.complete(system: system, user: user).timeout(_attemptTimeout);
        final problem = _check?.call(out);
        if (problem != null) throw FactoryException('مخرجات غير صالحة: $problem');
        _router.stats.recordSuccess(c.id, sw.elapsedMilliseconds);
        _router.lastUsed = c.name;
        _router._log('✔ ${c.name} (${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}ث)');
        return out;
      } on CancelledException {
        rethrow;
      } catch (e) {
        _router.stats.recordFailure(c.id, e);
        final msg = friendlyError(e);
        errors.add('${c.name}: $msg');
        final more = i < ordered.length - 1;
        _router._log('✖ ${c.name}: $msg${more ? ' ← الانتقال للأداة التالية' : ''}');
      }
    }
    throw FactoryException(
      'فشلت جميع أدوات الذكاء الاصطناعي:\n${errors.map((e) => '• $e').join('\n')}\n'
      'جرّب: الإعدادات ← فحص الاتصال والمفاتيح',
      details: errors.join('\n'),
    );
  }
}
