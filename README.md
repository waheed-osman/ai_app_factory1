# مصنع التطبيقات (AI App Factory) v2

تطبيق Flutter يصنع تطبيقات Flutter ويبنيها على GitHub Actions.

## المزايا
- **من فكرة**: توليد مشروع كامل بـ Claude أو Gemini.
- **رفع مشروع جاهز (جديد)**: اختيار ZIP لمشروع Flutter ← قراءة وتنظيف ← إنشاء مستودع ← رفع ← بناء.
- **نوع البناء (جديد)**: APK أو Web أو الاثنان. الويب: `flutter build web --release` ثم رفع `build/web` كـ Artifact `web`،
  مع نشر اختياري على GitHub Pages لإعطاء رابط للمشاركة.
- **الإصلاح الذاتي**: عند فشل البناء يُقرأ السجل ويُصلح الكود ثم يُعاد الرفع (حتى N محاولات).
- حالات واضحة: في الانتظار / في الطابور / قيد التنفيذ / نجح / فشل.

## البنية
`lib/services/`: github_builder (Git Data API + Actions)، factory_pipeline، project_importer (جديد)،
workflow_templates (جديد: build_apk.yml / build_web.yml)، project_validator، llm_client، ...

## الرفع على GitHub وبناء APK الخاص بالمصنع
ارفع محتويات هذا المجلد كاملاً (بما فيه `.github/workflows/build_apk.yml`) إلى مستودع، ثم شغّل Actions ← Build Flutter APK.
