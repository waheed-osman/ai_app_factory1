import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/errors.dart';
import '../models/ai_profile.dart';
import '../services/ai_router.dart';
import '../services/file_exporter.dart';
import '../services/http_transport.dart';
import '../services/model_lister.dart';
import 'diagnostics_dialogs.dart';

/// نتيجة محرر الأداة: حفظ أو حذف.
class AiEditorResult {
  const AiEditorResult.saved(this.profile) : deleted = false;
  const AiEditorResult.deleted()
      : profile = null,
        deleted = true;

  final AiProfile? profile;
  final bool deleted;
}

/// تعديل أداة ذكاء اصطناعي: خطوات الحصول على المفتاح، اللصق من الحافظة،
/// جلب الموديلات المتاحة، واختبار الاتصال.
class AiProfileEditorScreen extends StatefulWidget {
  const AiProfileEditorScreen({
    super.key,
    required this.profile,
    this.presetNote,
    this.canDelete = false,
    this.autoFetch = false,
  });

  final AiProfile profile;
  final String? presetNote;
  final bool canDelete;

  /// جلب الموديلات تلقائياً عند الفتح (بعد لصق مفتاح).
  final bool autoFetch;

  @override
  State<AiProfileEditorScreen> createState() => _AiProfileEditorScreenState();
}

class _AiProfileEditorScreenState extends State<AiProfileEditorScreen> {
  late AiProfile _p;
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _key;
  late final TextEditingController _model;
  late final TextEditingController _tokens;
  bool _fetching = false;
  bool _hideKey = true;

  @override
  void initState() {
    super.initState();
    _p = widget.profile;
    _name = TextEditingController(text: _p.name);
    _url = TextEditingController(text: _p.baseUrl);
    _key = TextEditingController(text: _p.apiKey);
    _model = TextEditingController(text: _p.model);
    _tokens = TextEditingController(text: '${_p.maxTokens}');
    if (widget.autoFetch) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchModels(autoPick: true));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _key.dispose();
    _model.dispose();
    _tokens.dispose();
    super.dispose();
  }

  AiPreset? get _preset => AiPreset.matchFor(_collect());

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  AiProfile _collect() {
    final tokens = int.tryParse(_tokens.text.trim()) ?? _p.maxTokens;
    return _p.copyWith(
      name: _name.text.trim().isEmpty ? 'أداة' : _name.text.trim(),
      baseUrl: _url.text.trim(),
      apiKey: _key.text.trim(),
      model: _model.text.trim(),
      maxTokens: tokens.clamp(1000, 128000).toInt(),
    );
  }

  Future<void> _openKeyPage() async {
    final url = _preset?.keyUrl ?? '';
    if (url.isEmpty) {
      _toast('لا توجد صفحة مفتاح معروفة لهذه الأداة. افتح موقع المزود وأنشئ المفتاح من لوحته.');
      return;
    }
    try {
      await FileExporter.openUrl(url);
    } catch (e) {
      _toast(friendlyError(e));
    }
  }

  Future<void> _pasteKey() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _toast('الحافظة فارغة. انسخ المفتاح من صفحة المزود أولاً.');
      return;
    }
    final detected = AiPreset.detectFromKey(text);
    final mine = _preset;
    setState(() => _key.text = text);
    if (detected != null && mine != null && detected.name != mine.name && detected.kind != mine.kind) {
      _toast('تنبيه: هذا المفتاح يبدو لـ ${detected.name} وليس لهذه الأداة.');
    } else {
      _toast('تم لصق المفتاح. اضغط «الموديلات المتاحة» للتحقق منه.');
    }
  }

  Future<String> _testTool() async {
    final transport = HttpTransport();
    try {
      final client = AiRouter.clientFor(_collect(), transport);
      final out = await client
          .complete(system: 'Reply with a single short word.', user: 'Say OK.')
          .timeout(const Duration(seconds: 60));
      return out.trim().length > 80 ? out.trim().substring(0, 80) : out.trim();
    } finally {
      transport.close();
    }
  }

  Future<void> _fetchModels({bool autoPick = false}) async {
    final transport = HttpTransport();
    setState(() => _fetching = true);
    try {
      final models = await ModelLister.list(_collect(), transport);
      if (!mounted) return;
      if (models.isEmpty) {
        _toast('الاتصال ناجح لكن لا توجد قائمة نماذج. اكتب الاسم يدوياً.');
        return;
      }
      if (autoPick && models.contains(_model.text.trim())) {
        _toast('المفتاح صالح والنموذج ${_model.text.trim()} متاح ✔');
        return;
      }
      final picked = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('المفتاح صالح ✔ — ${models.length} نموذج، اختر واحداً'),
          children: [
            SizedBox(
              width: double.maxFinite,
              height: 380,
              child: ListView(
                children: [
                  for (final m in models)
                    ListTile(
                      dense: true,
                      title: Text(m, textDirection: TextDirection.ltr),
                      onTap: () => Navigator.of(ctx).pop(m),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
      if (picked != null && mounted) setState(() => _model.text = picked);
    } catch (e) {
      if (mounted) _toast('فشل: ${friendlyError(e)}');
    } finally {
      transport.close();
      if (mounted) setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOpenAi = _p.kind == AiKind.openai;
    final preset = _preset;
    final defaultModel = preset?.model ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('أداة ذكاء اصطناعي'),
        actions: [
          if (widget.canDelete)
            IconButton(
              tooltip: 'حذف',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => Navigator.of(context).pop(const AiEditorResult.deleted()),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.presetNote != null)
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(padding: const EdgeInsets.all(12), child: Text(widget.presetNote!)),
              ),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم')),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<AiKind>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: AiKind.openai,
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text('OpenAI-متوافق')),
                  ),
                  ButtonSegment(value: AiKind.anthropic, label: Text('Claude')),
                  ButtonSegment(value: AiKind.gemini, label: Text('Gemini')),
                ],
                selected: {_p.kind},
                onSelectionChanged: (v) => setState(() => _p = _p.copyWith(kind: v.first)),
              ),
            ),
            if (isOpenAi) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _url,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'رابط API',
                  helperText: 'الرابط الكامل حتى /v1 مثل https://api.groq.com/openai/v1',
                ),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الحصول على المفتاح',
                      style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '1) افتح صفحة المفتاح وسجّل الدخول بحسابك (جوجل أو GitHub).\n'
                      '2) أنشئ مفتاح API وانسخه.\n'
                      '3) ارجع هنا واضغط «لصق من الحافظة».\n'
                      'الخطط المجانية تكفي للاستخدام الشخصي.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _openKeyPage,
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('فتح صفحة المفتاح'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _pasteKey,
                          icon: const Icon(Icons.content_paste, size: 18),
                          label: const Text('لصق من الحافظة'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              obscureText: _hideKey,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: isOpenAi ? 'مفتاح API (اختياري للخوادم المحلية)' : 'مفتاح API',
                helperText: 'يُحفظ على هذا الجهاز فقط',
                suffixIcon: IconButton(
                  tooltip: _hideKey ? 'إظهار' : 'إخفاء',
                  icon: Icon(_hideKey ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _hideKey = !_hideKey),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _model,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'النموذج',
                helperText: defaultModel.isEmpty ? null : 'الافتراضي: $defaultModel',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _fetching ? null : _fetchModels,
                  icon: _fetching
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.list_alt),
                  label: const Text('الموديلات المتاحة'),
                ),
                OutlinedButton.icon(
                  onPressed: () => showToolTest(context, _testTool),
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('اختبار الاتصال'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('التخصص (المهام التي يتولاها)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final r in AiRole.values)
                  FilterChip(
                    label: Text(r.label),
                    selected: _p.roles.contains(r),
                    onSelected: (on) {
                      final next = Set<AiRole>.of(_p.roles);
                      if (on) {
                        next.add(r);
                      } else {
                        next.remove(r);
                      }
                      if (next.isEmpty) return;
                      setState(() => _p = _p.copyWith(roles: next));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('الأولوية: ${_p.priority} (1 = تُجرَّب أولاً)', style: theme.textTheme.titleSmall),
            Slider(
              min: 1,
              max: 9,
              divisions: 8,
              value: _p.priority.toDouble(),
              label: '${_p.priority}',
              onChanged: (v) => setState(() => _p = _p.copyWith(priority: v.round())),
            ),
            TextField(
              controller: _tokens,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'أقصى طول للرد (tokens)',
                helperText: 'قلّله إن رفض المزود القيمة الكبيرة',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('مفعّلة'),
              value: _p.enabled,
              onChanged: (v) => setState(() => _p = _p.copyWith(enabled: v)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(AiEditorResult.saved(_collect())),
              icon: const Icon(Icons.save_outlined),
              label: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
