import 'package:flutter/material.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  static const List<(String, String)> _sections = [
    (
      '1) توكن GitHub',
      'من github.com ← Settings ← Developer settings ← Personal access tokens ← Tokens (classic) ← Generate new token. '
          'فعّل الصلاحيتين repo و workflow (وإن أردت حذف المستودعات لاحقاً: delete_repo). الصق التوكن في الإعدادات.',
    ),
    (
      '2) مفتاح الذكاء الاصطناعي',
      'مطلوب فقط لتوليد التطبيق من فكرة وللإصلاح الذاتي. رفع مشروع جاهز لا يحتاجه إلا إذا أردت الإصلاح الذاتي.',
    ),
    (
      '3) تبويب «من فكرة»',
      'اكتب وصف التطبيق، اختر نوع البناء (APK / ويب / الاثنان) ثم «ابدأ التصنيع».',
    ),
    (
      '4) تبويب «رفع مشروع جاهز»',
      'اختر ملف ZIP يحوي pubspec.yaml ومجلد lib. يُستبعد تلقائياً: build و .git و .dart_tool و .github وملفات APK، '
          'وتُولَّد مجلدات android/web من جديد بأحدث قالب. يُحدَّث قيد sdk القديم في pubspec.yaml، ويُحذف pubspec.lock لتفادي تعارض الإصدارات.',
    ),
    (
      '5) نسخة الويب',
      'يُبنى المشروع بالأمر flutter build web --release ويُرفع مجلد build/web كـ Artifact باسم web. '
          'عند تفعيل «النشر على GitHub Pages» يظهر رابط الموقع للفتح والمشاركة.',
    ),
    (
      '6) حالات البناء',
      'في الانتظار ← في الطابور ← قيد التنفيذ ← نجح / فشل. عند الفشل يقرأ التطبيق سجل GitHub ويحاول الإصلاح ذاتياً (حسب الإعدادات).',
    ),
    (
      '7) تثبيت APK',
      'كل بناء يُوقَّع بمفتاح debug جديد؛ إن ظهر تعارض مع نسخة أقدم فاحذف القديمة أولاً ثم ثبّت الجديدة.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الدليل')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _sections.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final s = _sections[i];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.$1, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(s.$2),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
