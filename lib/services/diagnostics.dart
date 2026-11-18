import 'dart:convert';

import '../core/errors.dart';
import '../models/ai_profile.dart';
import 'http_transport.dart';
import 'llm_client.dart';

class DiagnosticResult {
  const DiagnosticResult(this.title, this.ok, this.detail);

  final String title;
  final bool ok;
  final String detail;
}

/// فحص الاتصال والمفاتيح والنماذج لتحديد سبب فشل أدوات الذكاء الاصطناعي بدقة.
class Diagnostics {
  Diagnostics(this._t);

  final HttpTransport _t;

  /// هل يصل الجهاز لهذا العنوان؟ (أي رد HTTP يعني أن الشبكة سليمة).
  Future<DiagnosticResult> reach(String title, String url) async {
    final sw = Stopwatch()..start();
    try {
      final res = await _t.send(
        'GET',
        Uri.parse(url),
        timeout: const Duration(seconds: 15),
        retries: 0,
      );
      return DiagnosticResult(title, true, 'يصل (HTTP ${res.statusCode}) في ${sw.elapsedMilliseconds}ms');
    } on FactoryException catch (e) {
      return DiagnosticResult(title, false, e.message);
    }
  }

  String _apiMessage(List<int> body) {
    try {
      final d = jsonDecode(utf8.decode(body));
      if (d is Map && d['error'] is Map && (d['error'] as Map)['message'] is String) {
        return (d['error'] as Map)['message'] as String;
      }
    } catch (_) {}
    return '';
  }

  /// يختبر المفتاح ثم وجود النموذج لأداة واحدة.
  Future<DiagnosticResult> testTool({
    required String title,
    required AiKind kind,
    required String apiKey,
    required String model,
    String baseUrl = '',
    bool autoV1 = false,
  }) async {
    try {
      switch (kind) {
        case AiKind.gemini:
          return await _testGemini(title, apiKey, model);
        case AiKind.anthropic:
          return await _testAnthropic(title, apiKey);
        case AiKind.openai:
          return await _testOpenAi(title, baseUrl, apiKey, model, autoV1);
      }
    } on FactoryException catch (e) {
      return DiagnosticResult(title, false, e.message);
    }
  }

  Future<DiagnosticResult> _testGemini(String title, String key, String model) async {
    if (key.trim().isEmpty) return DiagnosticResult(title, false, 'لا يوجد مفتاح API');
    final headers = {'x-goog-api-key': key.trim()};
    final res = await _t.send(
      'GET',
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?pageSize=1'),
      headers: headers,
      timeout: const Duration(seconds: 20),
      retries: 0,
    );
    if (res.statusCode != 200) {
      final msg = _apiMessage(res.bodyBytes);
      return DiagnosticResult(title, false, 'المفتاح مرفوض [${res.statusCode}] $msg');
    }
    final m = model.trim().replaceFirst('models/', '');
    final mres = await _t.send(
      'GET',
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$m'),
      headers: headers,
      timeout: const Duration(seconds: 20),
      retries: 0,
    );
    if (mres.statusCode == 200) return DiagnosticResult(title, true, 'المفتاح صالح والنموذج $m متاح');
    return DiagnosticResult(
      title,
      false,
      'المفتاح صالح لكن النموذج «$m» غير متاح [${mres.statusCode}]. جرّب gemini-flash-lite-latest',
    );
  }

  Future<DiagnosticResult> _testAnthropic(String title, String key) async {
    if (key.trim().isEmpty) return DiagnosticResult(title, false, 'لا يوجد مفتاح API');
    final res = await _t.send(
      'GET',
      Uri.parse('https://api.anthropic.com/v1/models?limit=1'),
      headers: {'x-api-key': key.trim(), 'anthropic-version': '2023-06-01'},
      timeout: const Duration(seconds: 20),
      retries: 0,
    );
    if (res.statusCode == 200) return DiagnosticResult(title, true, 'المفتاح صالح');
    return DiagnosticResult(title, false, 'المفتاح مرفوض [${res.statusCode}] ${_apiMessage(res.bodyBytes)}');
  }

  Future<DiagnosticResult> _testOpenAi(
    String title,
    String baseUrl,
    String key,
    String model,
    bool autoV1,
  ) async {
    if (baseUrl.trim().isEmpty) return DiagnosticResult(title, false, 'لا يوجد رابط API');
    final client = OmniRouteClient(
      baseUrl: baseUrl,
      apiKey: key.trim(),
      model: model.trim(),
      transport: _t,
      autoV1: autoV1,
    );
    final models = await client.listModels();
    if (models.isEmpty) {
      return DiagnosticResult(title, true, 'الاتصال سليم (الخادم لا يعرض قائمة نماذج). تأكد من اسم النموذج يدوياً');
    }
    if (model.trim().isNotEmpty && !models.contains(model.trim())) {
      return DiagnosticResult(title, false, 'الاتصال سليم لكن النموذج «${model.trim()}» ليس ضمن ${models.length} نموذجاً متاحاً');
    }
    return DiagnosticResult(title, true, 'الاتصال والمفتاح سليمان (${models.length} نموذج)');
  }

  /// خلاصة مفهومة لنتائج فحص الشبكة.
  static String networkVerdict(List<DiagnosticResult> r) {
    if (r.isEmpty) return '';
    final ok = r.where((e) => e.ok).length;
    if (ok == r.length) {
      return 'الشبكة سليمة. إن استمر الفشل فالسبب في المفتاح أو اسم النموذج (انظر القسم 2).';
    }
    if (ok == 0) {
      return 'لا يصل التطبيق لأي خادم رغم اتصال الهاتف. السبب الأرجح: صلاحية INTERNET غير موجودة في ملف APK '
          '(أعد البناء بالـ workflow المحدّث الذي يشغّل tool/setup_android.py ثم ثبّت النسخة الجديدة)، '
          'أو VPN/حماية تمنع التطبيق.';
    }
    final bad = r.where((e) => !e.ok).map((e) => e.title).join('، ');
    return 'الإنترنت يعمل لكن لا يصل التطبيق إلى: $bad. غالباً حجب من مزود الإنترنت أو DNS: '
        'جرّب VPN أو غيّر DNS الخاص إلى dns.google أو بدّل الشبكة.';
  }
}
