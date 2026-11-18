import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../core/errors.dart';
import '../models/build_models.dart';
import '../providers/settings_controller.dart';
import '../services/background_service.dart';
import '../services/http_transport.dart';
import '../services/llm_client.dart';
import 'ai_tools_screen.dart';
import 'diagnostics_dialogs.dart';
import 'diagnostics_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _s;
  late final TextEditingController _anthropic;
  late final TextEditingController _gemini;
  late final TextEditingController _github;
  late final TextEditingController _anthropicModel;
  late final TextEditingController _geminiModel;
  late final TextEditingController _omniUrl;
  late final TextEditingController _omniKey;
  late final TextEditingController _omniModel;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _s = context.read<SettingsController>().settings;
    _anthropic = TextEditingController(text: _s.anthropicKey);
    _gemini = TextEditingController(text: _s.geminiKey);
    _github = TextEditingController(text: _s.githubToken);
    _anthropicModel = TextEditingController(text: _s.anthropicModel);
    _geminiModel = TextEditingController(text: _s.geminiModel);
    _omniUrl = TextEditingController(text: _s.omnirouteUrl);
    _omniKey = TextEditingController(text: _s.omnirouteKey);
    _omniModel = TextEditingController(text: _s.omnirouteModel);
  }

  @override
  void dispose() {
    _anthropic.dispose();
    _gemini.dispose();
    _github.dispose();
    _anthropicModel.dispose();
    _geminiModel.dispose();
    _omniUrl.dispose();
    _omniKey.dispose();
    _omniModel.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // قائمة الأدوات والتنقل التلقائي تُعدَّل من شاشة أخرى؛ نأخذ آخر نسخة.
    final latest = context.read<SettingsController>().settings;
    final next = _s.copyWith(
      profiles: latest.profiles,
      smartRouting: latest.smartRouting,
      anthropicKey: _anthropic.text.trim(),
      geminiKey: _gemini.text.trim(),
      omnirouteUrl: _omniUrl.text.trim(),
      omnirouteKey: _omniKey.text.trim(),
      omnirouteModel: _omniModel.text.trim(),
      githubToken: _github.text.trim(),
      anthropicModel: _anthropicModel.text.trim().isEmpty
          ? const AppSettings().anthropicModel
          : _anthropicModel.text.trim(),
      geminiModel: _geminiModel.text.trim().isEmpty
          ? const AppSettings().geminiModel
          : _geminiModel.text.trim(),
    );
    await context.read<SettingsController>().update(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ الإعدادات')),
    );
    Navigator.of(context).pop();
  }

  /// يرسل طلباً قصيراً بالإعدادات الحالية في الشاشة (دون حفظها).
  Future<String> _testLegacy() async {
    final temp = _s.copyWith(
      anthropicKey: _anthropic.text.trim(),
      geminiKey: _gemini.text.trim(),
      anthropicModel: _anthropicModel.text.trim(),
      geminiModel: _geminiModel.text.trim(),
      omnirouteUrl: _omniUrl.text.trim(),
      omnirouteKey: _omniKey.text.trim(),
      omnirouteModel: _omniModel.text.trim(),
    );
    final transport = HttpTransport();
    try {
      final client = LlmClient.fromSettings(temp, transport);
      if (client == null) {
        throw const FactoryException('أكمل المفتاح واسم النموذج أولاً.');
      }
      final out = await client
          .complete(system: 'Reply with a single short word.', user: 'Say OK.')
          .timeout(const Duration(seconds: 60));
      return out.trim().length > 80 ? out.trim().substring(0, 80) : out.trim();
    } finally {
      transport.close();
    }
  }

  Future<void> _testOmni() async {
    final transport = HttpTransport();
    setState(() => _testing = true);
    try {
      final client = OmniRouteClient(
        baseUrl: _omniUrl.text,
        apiKey: _omniKey.text.trim(),
        model: _omniModel.text.trim(),
        transport: transport,
      );
      final models = await client.listModels();
      if (!mounted) return;
      if (models.isEmpty) {
        _toast('الاتصال ناجح لكن لا توجد نماذج مُعرَّفة. اكتب اسم النموذج أو الـ Combo يدوياً.');
        return;
      }
      final picked = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('الاتصال ناجح (${models.length} نموذج) — اختر نموذجاً'),
          children: [
            SizedBox(
              width: double.maxFinite,
              height: 360,
              child: ListView(
                children: [
                  for (final m in models)
                    ListTile(
                      dense: true,
                      title: Text(m),
                      onTap: () => Navigator.of(ctx).pop(m),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
      if (picked != null && mounted) setState(() => _omniModel.text = picked);
    } catch (e) {
      if (mounted) _toast('فشل الاتصال: ${friendlyError(e)}');
    } finally {
      transport.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.watch<SettingsController>().settings;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.alt_route),
                title: const Text('أدوات الذكاء الاصطناعي (تنقل تلقائي)'),
                subtitle: Text(
                  s.smartRouting
                      ? '${s.profiles.where((p) => p.isUsable).length} أداة جاهزة — توزيع المهام والتبديل التلقائي'
                      : 'معطّل',
                ),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AiToolsScreen()),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.network_check),
                title: const Text('فحص الاتصال والمفاتيح'),
                subtitle: const Text('يحدد سبب فشل أدوات الذكاء الاصطناعي: الشبكة أم المفتاح أم النموذج'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen()),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('الأداة الافتراضية (خيار أخير)', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<LlmProvider>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: LlmProvider.anthropic, label: Text('Claude')),
                  ButtonSegment(value: LlmProvider.gemini, label: Text('Gemini')),
                  ButtonSegment(
                    value: LlmProvider.omniroute,
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text('OmniRoute')),
                  ),
                ],
                selected: {_s.provider},
                onSelectionChanged: (v) => setState(() => _s = _s.copyWith(provider: v.first)),
              ),
            ),
            const SizedBox(height: 12),
            if (_s.provider == LlmProvider.anthropic) ...[
              TextField(
                controller: _anthropic,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'مفتاح Anthropic API'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _anthropicModel,
                decoration: const InputDecoration(labelText: 'النموذج'),
              ),
            ] else if (_s.provider == LlmProvider.gemini) ...[
              TextField(
                controller: _gemini,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'مفتاح Gemini API'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _geminiModel,
                decoration: const InputDecoration(labelText: 'النموذج'),
              ),
            ] else ...[
              TextField(
                controller: _omniUrl,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'رابط OmniRoute',
                  helperText: 'مثال: http://localhost:20128 أو رابط خادمك (Railway / VPS)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _omniKey,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'مفتاح API (اختياري)',
                  helperText: 'اتركه فارغاً إذا كان التوثيق معطلاً في OmniRoute',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _omniModel,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'النموذج أو الـ Combo',
                  helperText: 'استخدم «اختبار الاتصال» لعرض النماذج المتاحة',
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _testOmni,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('اختبار الاتصال وجلب النماذج'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => showToolTest(context, _testLegacy),
                icon: const Icon(Icons.science_outlined),
                label: const Text('اختبار الأداة الافتراضية'),
              ),
            ),
            const Divider(height: 32),
            Text('GitHub', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _github,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Personal Access Token',
                helperText: 'يلزم: repo + workflow (Classic) — راجع الدليل',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('مستودعات خاصة'),
              subtitle: const Text('GitHub Pages قد لا يعمل مع الخاصة في الحسابات المجانية.'),
              value: _s.privateRepos,
              onChanged: (v) => setState(() => _s = _s.copyWith(privateRepos: v)),
            ),
            const Divider(height: 32),
            Text('البناء', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('الإصلاح الذاتي'),
              subtitle: const Text('عند فشل البناء يُرسل السجل للنموذج ويُعاد البناء تلقائياً.'),
              value: _s.autoFix,
              onChanged: (v) => setState(() => _s = _s.copyWith(autoFix: v)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('أقصى محاولات الإصلاح: ${_s.maxFixAttempts}'),
              subtitle: Slider(
                min: 1,
                max: 5,
                divisions: 4,
                value: _s.maxFixAttempts.toDouble(),
                onChanged: (v) => setState(() => _s = _s.copyWith(maxFixAttempts: v.round())),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('العمل في الخلفية'),
              subtitle: const Text(
                'يُبقي التصنيع والبناء مستمراً عند قفل الشاشة أو الخروج من التطبيق (يظهر إشعار دائم أثناء العمل).',
              ),
              value: _s.backgroundMode,
              onChanged: (v) async {
                setState(() => _s = _s.copyWith(backgroundMode: v));
                if (v) await BackgroundService.requestPermissions();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('نشر نسخة الويب على GitHub Pages'),
              subtitle: const Text('يعطيك رابط موقع جاهز للمشاركة بعد نجاح بناء الويب.'),
              value: _s.publishWebToPages,
              onChanged: (v) => setState(() => _s = _s.copyWith(publishWebToPages: v)),
            ),
            const SizedBox(height: 8),
            Text('النوع الافتراضي للبناء', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<BuildTarget>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: BuildTarget.apk, label: Text('APK')),
                  ButtonSegment(value: BuildTarget.web, label: Text('ويب')),
                  ButtonSegment(value: BuildTarget.both, label: Text('الاثنان')),
                ],
                selected: {_s.defaultTarget},
                onSelectionChanged: (v) => setState(() => _s = _s.copyWith(defaultTarget: v.first)),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
