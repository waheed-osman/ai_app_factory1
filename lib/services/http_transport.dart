import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/errors.dart';

/// طبقة اتصال موحدة: مهلة + إعادة محاولة عند أخطاء الشبكة و 5xx
/// + تحويل الأخطاء إلى [NetworkException].
class HttpTransport {
  HttpTransport({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  Future<http.Response> send(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 60),
    int retries = 2,
    bool followRedirects = true,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final req = http.Request(method, url)..followRedirects = followRedirects;
        if (headers != null) req.headers.addAll(headers);
        if (body is String) {
          req.body = body;
        } else if (body is List<int>) {
          req.bodyBytes = body;
        }
        final streamed = await _client.send(req).timeout(timeout);
        final res = await http.Response.fromStream(streamed).timeout(timeout);
        if (res.statusCode >= 500 && attempt < retries) {
          lastError = 'HTTP ${res.statusCode}';
          await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
          continue;
        }
        return res;
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on HandshakeException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
      if (attempt < retries) {
        await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    throw NetworkException(
      'تعذر الوصول إلى ${url.host}: ${explain(lastError)}',
      details: '$lastError',
    );
  }

  /// يشرح سبب فشل الاتصال بالعربية مع النص التقني المختصر.
  static String explain(Object? e) {
    final raw = '$e';
    final low = raw.toLowerCase();
    String cause;
    if (low.contains('failed host lookup') || low.contains('nodename nor servname')) {
      cause = 'تعذر تحليل اسم الخادم (DNS): الإنترنت لا يصل لهذا الموقع، أو DNS الخاص/VPN/الشبكة تحجبه';
    } else if (low.contains('operation not permitted') || low.contains('permission denied')) {
      cause = 'التطبيق بلا إذن إنترنت (INTERNET) أو أن الشبكة محجوبة عنه من إعدادات الجهاز';
    } else if (e is HandshakeException || low.contains('certificate') || low.contains('handshake')) {
      cause = 'فشل التحقق من شهادة SSL: تحقق من تاريخ ووقت الجهاز، وأوقف VPN أو برنامج الحماية';
    } else if (low.contains('connection refused')) {
      cause = 'الخادم رفض الاتصال';
    } else if (low.contains('network is unreachable') || low.contains('no route')) {
      cause = 'الشبكة غير متاحة';
    } else if (e is TimeoutException || low.contains('timed out')) {
      cause = 'انتهت المهلة قبل وصول الرد';
    } else if (low.contains('connection reset') || low.contains('connection closed') || low.contains('broken pipe')) {
      cause = 'انقطع الاتصال أثناء الطلب';
    } else {
      cause = 'سبب غير معروف';
    }
    final short = raw.length > 140 ? raw.substring(0, 140) : raw;
    return '$cause\n($short)';
  }

  /// تنزيل ملف يتطلب توثيقاً ثم يُحوَّل لرابط موقّع (مثل Artifacts و Logs):
  /// الطلب الأول يحمل التوثيق، والتحويلات اللاحقة تُرسل بدونه.
  Future<Uint8List> download(
    Uri url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    var res = await send(
      'GET',
      url,
      headers: headers,
      timeout: timeout,
      followRedirects: false,
    );
    var hops = 0;
    while (const [301, 302, 303, 307, 308].contains(res.statusCode) &&
        hops < 5) {
      final location = res.headers['location'];
      if (location == null || location.isEmpty) break;
      res = await send(
        'GET',
        url.resolve(location),
        timeout: timeout,
      );
      hops++;
    }
    if (res.statusCode != 200) {
      throw ApiException(
        'فشل التنزيل (HTTP ${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
    return res.bodyBytes;
  }
}
