import 'dart:convert';

import '../core/errors.dart';
import '../models/ai_profile.dart';
import 'http_transport.dart';
import 'llm_client.dart';

/// جلب النماذج المتاحة لحساب/مفتاح معيّن (يتحقق من المفتاح في الوقت نفسه).
class ModelLister {
  ModelLister._();

  static String _msg(List<int> body) {
    try {
      final d = jsonDecode(utf8.decode(body));
      if (d is Map && d['error'] is Map && (d['error'] as Map)['message'] is String) {
        return (d['error'] as Map)['message'] as String;
      }
    } catch (_) {}
    return '';
  }

  static Future<List<String>> list(AiProfile p, HttpTransport t) async {
    final key = p.apiKey.trim();
    switch (p.kind) {
      case AiKind.openai:
        return OmniRouteClient(
          baseUrl: p.baseUrl,
          apiKey: key,
          model: p.model,
          transport: t,
          autoV1: false,
        ).listModels();
      case AiKind.gemini:
        if (key.isEmpty) throw const FactoryException('أدخل مفتاح API أولاً.');
        final res = await t.send(
          'GET',
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200'),
          headers: {'x-goog-api-key': key},
          timeout: const Duration(seconds: 20),
          retries: 0,
        );
        if (res.statusCode != 200) {
          throw ApiException('المفتاح مرفوض [${res.statusCode}] ${_msg(res.bodyBytes)}', statusCode: res.statusCode);
        }
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        final models = d is Map && d['models'] is List ? d['models'] as List : const [];
        return models
            .whereType<Map>()
            .where((m) => m['supportedGenerationMethods'] is List && (m['supportedGenerationMethods'] as List).contains('generateContent'))
            .map((m) => '${m['name']}'.replaceFirst('models/', ''))
            .toList();
      case AiKind.anthropic:
        if (key.isEmpty) throw const FactoryException('أدخل مفتاح API أولاً.');
        final res = await t.send(
          'GET',
          Uri.parse('https://api.anthropic.com/v1/models?limit=100'),
          headers: {'x-api-key': key, 'anthropic-version': '2023-06-01'},
          timeout: const Duration(seconds: 20),
          retries: 0,
        );
        if (res.statusCode != 200) {
          throw ApiException('المفتاح مرفوض [${res.statusCode}] ${_msg(res.bodyBytes)}', statusCode: res.statusCode);
        }
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        final data = d is Map && d['data'] is List ? d['data'] as List : const [];
        return data.whereType<Map>().map((m) => '${m['id']}').toList();
    }
  }
}
