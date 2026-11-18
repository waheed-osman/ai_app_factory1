import 'package:flutter/material.dart';

import '../core/errors.dart';

/// يشغّل اختباراً (طلب قصير للأداة) ويعرض الرد أو الخطأ المفصّل.
Future<void> showToolTest(BuildContext context, Future<String> Function() test) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => FutureBuilder<String>(
      future: test(),
      builder: (ctx, snap) {
        final waiting = snap.connectionState != ConnectionState.done;
        final failed = snap.hasError;
        final text = waiting
            ? 'جارٍ إرسال طلب اختبار...'
            : failed
                ? _describe(snap.error!)
                : 'نجح الاتصال ✔\nرد الأداة: ${snap.data}';
        return AlertDialog(
          title: const Text('اختبار الأداة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (waiting) const LinearProgressIndicator(),
                if (waiting) const SizedBox(height: 12),
                SelectableText(text),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إغلاق'))],
        );
      },
    ),
  );
}

String _describe(Object e) {
  final b = StringBuffer('فشل الاختبار ✖\n${friendlyError(e)}');
  if (e is FactoryException && e.details != null && e.details!.isNotEmpty && e is! ApiException) {
    b.write('\n\nالتفاصيل التقنية:\n${e.details}');
  }
  if (e is ApiException && e.statusCode == 404) {
    b.write('\n\nاسم النموذج غير صحيح أو غير متاح (النماذج القديمة مثل gemini-1.5-flash أُوقفت). اختر نموذجاً حديثاً مثل gemini-2.5-flash.');
  }
  if (e is ApiException && (e.statusCode == 400 || e.statusCode == 403)) {
    b.write('\n\nتحقق من صحة المفتاح وأنه مفعّل لهذه الخدمة.');
  }
  return b.toString();
}
