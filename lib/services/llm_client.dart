import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/errors.dart';
import '../models/app_settings.dart';
import 'http_transport.dart';

/// واجهة موحدة لنماذج الذكاء الاصطناعي.
abstract class LlmClient {
  Future<String> complete({required String system, required String user});

  /// ينشئ العميل المناسب، أو null إذا لم يُضبط مفتاح.
  static LlmClient? fromSettings(AppSettings s, HttpTransport transport) {
    if (!s.legacyReady) return null;
    switch (s.provider) {
      case LlmProvider.anthropic:
        return AnthropicClient(apiKey: s.anthropicKey.trim(), model: s.anthropicModel, transport: transport);
      case LlmProvider.gemini:
        return GeminiClient(apiKey: s.geminiKey.trim(), model: s.geminiModel, transport: transport);
      case LlmProvider.omniroute:
        return OmniRouteClient(
          baseUrl: s.omnirouteUrl,
          apiKey: s.omnirouteKey.trim(),
          model: s.omnirouteModel.trim(),
          transport: transport,
        );
    }
  }
}

ApiException _llmError(http.Response res, String who) {
  var detail = '';
  try {
    final d = jsonDecode(utf8.decode(res.bodyBytes));
    if (d is Map) {
      final e = d['error'];
      if (e is Map && e['message'] is String) detail = e['message'] as String;
    }
  } catch (_) {}
  final code = res.statusCode;
  String hint;
  if (code == 401 || code == 403) {
    hint = 'مفتاح $who غير صالح أو لا يملك صلاحية';
  } else if (code == 429) {
    hint = 'تم تجاوز حد الطلبات أو الرصيد لدى $who';
  } else if (code == 400) {
    hint = 'طلب مرفوض من $who';
  } else {
    hint = 'خطأ من $who';
  }
  return ApiException('$hint [$code]${detail.isEmpty ? '' : ': $detail'}', statusCode: code);
}

class AnthropicClient implements LlmClient {
  AnthropicClient({
    required this.apiKey,
    required this.model,
    required this.transport,
    this.maxTokens = 16000,
  });

  final String apiKey;
  final String model;
  final HttpTransport transport;
  final int maxTokens;

  @override
  Future<String> complete({required String system, required String user}) async {
    final res = await transport.send(
      'POST',
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        'system': system,
        'messages': [
          {'role': 'user', 'content': user},
        ],
      }),
      timeout: const Duration(minutes: 10),
      retries: 1,
    );
    if (res.statusCode != 200) throw _llmError(res, 'Claude');
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! Map) throw const FactoryException('رد غير متوقع من Claude');
    final blocks = data['content'];
    final text = StringBuffer();
    if (blocks is List) {
      for (final b in blocks) {
        if (b is Map && b['type'] == 'text' && b['text'] is String) {
          text.write(b['text'] as String);
        }
      }
    }
    if (data['stop_reason'] == 'max_tokens') {
      throw const FactoryException('تم قطع رد النموذج لتجاوزه الحد الأقصى للطول. بسّط الفكرة.');
    }
    if (text.isEmpty) throw const FactoryException('رد Claude فارغ');
    return text.toString();
  }
}

class GeminiClient implements LlmClient {
  GeminiClient({
    required this.apiKey,
    required this.model,
    required this.transport,
    this.maxTokens = 65000,
  });

  final String apiKey;
  final String model;
  final HttpTransport transport;
  final int maxTokens;

  @override
  Future<String> complete({required String system, required String user}) async {
    final res = await transport.send(
      'POST',
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'x-goog-api-key': apiKey,
      },
      body: jsonEncode({
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': user},
            ],
          },
        ],
        'generationConfig': {'maxOutputTokens': maxTokens, 'temperature': 0.2},
      }),
      timeout: const Duration(minutes: 10),
      retries: 1,
    );
    if (res.statusCode != 200) throw _llmError(res, 'Gemini');
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! Map) throw const FactoryException('رد غير متوقع من Gemini');
    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const FactoryException('لم يُرجع Gemini أي نتيجة (قد يكون الطلب محظوراً).');
    }
    final first = candidates.first;
    if (first is! Map) throw const FactoryException('رد Gemini غير متوقع');
    if (first['finishReason'] == 'MAX_TOKENS') {
      throw const FactoryException('تم قطع رد النموذج لتجاوزه الحد الأقصى للطول. بسّط الفكرة.');
    }
    final content = first['content'];
    final text = StringBuffer();
    if (content is Map && content['parts'] is List) {
      for (final p in content['parts'] as List) {
        if (p is Map && p['text'] is String) text.write(p['text'] as String);
      }
    }
    if (text.isEmpty) throw const FactoryException('رد Gemini فارغ');
    return text.toString();
  }
}

/// OmniRoute: بوابة متوافقة مع واجهة OpenAI (توجيه ذكي لعدة مزودين).
/// الرابط الافتراضي المحلي: http://localhost:20128
class OmniRouteClient implements LlmClient {
  OmniRouteClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.transport,
    this.maxTokens = 16000,
    this.autoV1 = true,
  });

  final String baseUrl;

  /// true: يضيف /v1 تلقائياً (OmniRoute). false: الرابط يحوي مسار API كاملاً.
  final bool autoV1;
  final String apiKey;
  final String model;
  final HttpTransport transport;
  final int maxTokens;

  /// يبني رابط واجهة OpenAI من العنوان الأساسي (يقبل مع /v1 أو بدونها).
  static Uri endpoint(String baseUrl, String path, {bool autoV1 = true}) {
    var b = baseUrl.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (!b.contains('://')) b = 'http://$b';
    if (!autoV1) return Uri.parse('$b/$path');
    return Uri.parse(b.endsWith('/v1') ? '$b/$path' : '$b/v1/$path');
  }

  Map<String, String> get _headers => {
        'content-type': 'application/json; charset=utf-8',
        if (apiKey.isNotEmpty) 'authorization': 'Bearer $apiKey',
      };

  @override
  Future<String> complete({required String system, required String user}) async {
    final res = await transport.send(
      'POST',
      endpoint(baseUrl, 'chat/completions', autoV1: autoV1),
      headers: _headers,
      body: jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        'temperature': 0.2,
        'stream': false,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': user},
        ],
      }),
      timeout: const Duration(minutes: 10),
      retries: 1,
    );
    if (res.statusCode != 200) throw _llmError(res, 'OmniRoute');
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! Map) throw const FactoryException('رد غير متوقع من OmniRoute');
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const FactoryException('لم يُرجع OmniRoute أي نتيجة.');
    }
    final first = choices.first as Map;
    if (first['finish_reason'] == 'length') {
      throw const FactoryException('تم قطع رد النموذج لتجاوزه الحد الأقصى للطول. بسّط الفكرة أو اختر نموذجاً أكبر.');
    }
    final message = first['message'];
    final content = message is Map ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw const FactoryException('رد OmniRoute فارغ.');
    }
    return content;
  }

  /// قائمة النماذج المتاحة (GET /v1/models) لاختبار الاتصال واختيار نموذج.
  Future<List<String>> listModels() async {
    final res = await transport.send(
      'GET',
      endpoint(baseUrl, 'models', autoV1: autoV1),
      headers: _headers,
      timeout: const Duration(seconds: 20),
      retries: 0,
    );
    if (res.statusCode != 200) throw _llmError(res, 'OmniRoute');
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final list = data is Map ? data['data'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => '${m['id']}')
        .where((id) => id.isNotEmpty && id != 'null')
        .toList();
  }
}
