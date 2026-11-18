import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// استثناء عام برسالة مفهومة للمستخدم.
class FactoryException implements Exception {
  const FactoryException(this.message, {this.details});

  final String message;
  final String? details;

  @override
  String toString() => message;
}

/// فشل في الاتصال بالإنترنت أو انتهاء المهلة.
class NetworkException extends FactoryException {
  const NetworkException(super.message, {super.details});
}

/// رد خطأ من واجهة برمجية (GitHub / Claude / Gemini).
class ApiException extends FactoryException {
  const ApiException(super.message, {this.statusCode, super.details});

  final int? statusCode;
}

/// ألغى المستخدم العملية.
class CancelledException extends FactoryException {
  const CancelledException() : super('تم إلغاء العملية');
}

/// أداة بسيطة لإلغاء العمليات الطويلة.
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void check() {
    if (_cancelled) throw const CancelledException();
  }
}

/// تحويل أي استثناء إلى رسالة عربية واضحة.
String friendlyError(Object error) {
  if (error is FactoryException) return error.message;
  if (error is TimeoutException) {
    return 'انتهت مهلة الاتصال. تحقق من الإنترنت وحاول مرة أخرى.';
  }
  if (error is SocketException) {
    return 'لا يوجد اتصال بالإنترنت أو تعذر الوصول إلى الخادم.';
  }
  if (error is HandshakeException) {
    return 'تعذر إنشاء اتصال آمن (SSL). تحقق من الشبكة أو التاريخ على الجهاز.';
  }
  if (error is http.ClientException) {
    return 'انقطع الاتصال أثناء الطلب: ${error.message}';
  }
  if (error is FormatException) {
    return 'استجابة غير متوقعة من الخادم: ${error.message}';
  }
  return 'حدث خطأ غير متوقع: $error';
}
