import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/ai_profile.dart';
import '../providers/settings_controller.dart';
import 'ai_profile_editor_screen.dart';
import 'diagnostics_screen.dart';

/// قائمة أدوات الذكاء الاصطناعي المتعددة مع التنقل التلقائي بينها.
class AiToolsScreen extends StatelessWidget {
  const AiToolsScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    AiProfile profile, {
    String? note,
    bool isNew = false,
    bool autoFetch = false,
  }) async {
    final controller = context.read<SettingsController>();
    final result = await Navigator.of(context).push<AiEditorResult>(
      MaterialPageRoute(
        builder: (_) => AiProfileEditorScreen(
          profile: profile,
          presetNote: note,
          canDelete: !isNew,
          autoFetch: autoFetch,
        ),
      ),
    );
    if (result == null) return;
    final s = controller.settings;
    final list = List<AiProfile>.of(s.profiles);
    final i = list.indexWhere((p) => p.id == profile.id);
    if (result.deleted) {
      if (i >= 0) list.removeAt(i);
      controller.stats.reset(profile.id);
    } else if (result.profile != null) {
      if (i >= 0) {
        list[i] = result.profile!;
      } else {
        list.add(result.profile!);
      }
    }
    await controller.update(s.copyWith(profiles: list));
  }

  /// يقرأ مفتاحاً منسوخاً، يتعرف على مزوّده، وينشئ الأداة جاهزة للتحقق.
  Future<void> _pasteKey(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final key = data?.text?.trim() ?? '';
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (key.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('الحافظة فارغة. انسخ المفتاح من صفحة المزود أولاً.')));
      return;
    }
    final preset = AiPreset.detectFromKey(key);
    if (preset == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('لم أتعرف على نوع المفتاح. اختر الأداة من «إضافة أداة» ثم الصق المفتاح فيها.')),
      );
      return;
    }
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await _edit(
      context,
      preset.toProfile(id).copyWith(apiKey: key),
      note: 'تم التعرف على المفتاح: ${preset.name}. سيُتحقق منه وتُجلب النماذج المتاحة تلقائياً.',
      isNew: true,
      autoFetch: true,
    );
  }

  Future<void> _add(BuildContext context) async {
    final preset = await showModalBottomSheet<AiPreset?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('اختر أداة جاهزة أو أضف أداة مخصصة', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              for (final p in AiPreset.all)
                ListTile(
                  leading: const Icon(Icons.bolt_outlined),
                  title: Text(p.name),
                  subtitle: Text(p.note),
                  onTap: () => Navigator.of(ctx).pop(p),
                ),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('أداة مخصصة'),
                subtitle: const Text('أي خدمة متوافقة مع واجهة OpenAI'),
                onTap: () => Navigator.of(ctx).pop(
                  const AiPreset(
                    name: 'أداة مخصصة',
                    baseUrl: '',
                    model: '',
                    roles: kAllRoles,
                    priority: 5,
                    note: 'أدخل رابط API الكامل ومفتاحك واسم النموذج.',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (preset == null || !context.mounted) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await _edit(context, preset.toProfile(id), note: preset.note, isNew: true);
  }

  String _statLine(SettingsController c, AiProfile p) {
    final s = c.stats.stat(p.id);
    final parts = <String>['نجاح ${s.ok}', 'فشل ${s.fail}'];
    if (s.ok > 0) parts.add('متوسط ${(s.avgMs / 1000).toStringAsFixed(1)}ث');
    final cd = c.stats.cooldownLeftSeconds(p.id);
    if (cd > 0) parts.add('موقوفة مؤقتاً ${cd ~/ 60 > 0 ? '${cd ~/ 60}د' : '${cd}ث'}');
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SettingsController>();
    final s = c.settings;
    final theme = Theme.of(context);
    final profiles = List<AiProfile>.of(s.profiles)..sort((a, b) => a.priority.compareTo(b.priority));
    return Scaffold(
      appBar: AppBar(
        title: const Text('أدوات الذكاء الاصطناعي'),
        actions: [
          IconButton(
            tooltip: 'لصق مفتاح من الحافظة',
            icon: const Icon(Icons.content_paste_go),
            onPressed: () => _pasteKey(context),
          ),
          IconButton(
            tooltip: 'فحص الاتصال والمفاتيح',
            icon: const Icon(Icons.network_check),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('إضافة أداة'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('التنقل التلقائي بين الأدوات'),
              subtitle: const Text(
                'لكل مهمة (توليد / إصلاح / تعديل / تحسين) تُجرَّب الأدوات المتخصصة بالترتيب، '
                'وعند الفشل أو انتهاء الحصة المجانية أو رد غير صالح ينتقل التطبيق للتالية. '
                'يتعلّم الترتيب من سرعة كل أداة ونسبة نجاحها.',
              ),
              value: s.smartRouting,
              onChanged: (v) => c.update(s.copyWith(smartRouting: v)),
            ),
            const SizedBox(height: 8),
            if (profiles.isEmpty)
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'لا توجد أدوات بعد. أضف عدة أدوات مجانية (Gemini و Groq و OpenRouter ...) '
                    'ووزّع التخصصات بينها. الأداة الافتراضية من «الإعدادات» تعمل دائماً كخيار أخير.',
                  ),
                ),
              ),
            for (final p in profiles) ...[
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${p.priority}')),
                  title: Text(p.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.model.isEmpty ? '— اختر نموذجاً —' : p.model, textDirection: TextDirection.ltr),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        children: [
                          for (final r in AiRole.values)
                            if (p.roles.contains(r))
                              Chip(
                                label: Text(r.label, style: const TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                        ],
                      ),
                      Text(_statLine(c, p), style: theme.textTheme.bodySmall),
                      if (c.stats.stat(p.id).lastError != null)
                        Text(
                          c.stats.stat(p.id).lastError!,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (p.model.contains('gemini-1.5'))
                        Text(
                          'نماذج gemini-1.5 متقاعدة؛ استخدم gemini-2.5-flash',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                        ),
                      if (!p.isUsable && p.enabled)
                        Text('غير مكتملة الإعداد', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: Switch(
                    value: p.enabled,
                    onChanged: (v) {
                      final list = [for (final x in s.profiles) x.id == p.id ? x.copyWith(enabled: v) : x];
                      c.update(s.copyWith(profiles: list));
                    },
                  ),
                  onTap: () => _edit(context, p),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
