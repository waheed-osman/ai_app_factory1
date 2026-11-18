import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ai_profile.dart';
import '../models/app_settings.dart';
import '../providers/settings_controller.dart';
import '../services/diagnostics.dart';
import '../services/http_transport.dart';

/// فحص الاتصال والمفاتيح: يحدد هل المشكلة في الشبكة أم المفتاح أم النموذج.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final List<DiagnosticResult> _network = [];
  final List<DiagnosticResult> _tools = [];
  bool _running = false;

  Future<void> _run() async {
    final s = context.read<SettingsController>().settings;
    setState(() {
      _running = true;
      _network.clear();
      _tools.clear();
    });
    final transport = HttpTransport();
    final d = Diagnostics(transport);
    try {
      const hosts = <(String, String)>[
        ('الإنترنت العام (Google)', 'https://www.google.com/generate_204'),
        ('GitHub', 'https://api.github.com'),
        ('Gemini API', 'https://generativelanguage.googleapis.com/'),
        ('Claude API', 'https://api.anthropic.com'),
        ('Groq', 'https://api.groq.com'),
        ('OpenRouter', 'https://openrouter.ai'),
      ];
      for (final h in hosts) {
        final r = await d.reach(h.$1, h.$2);
        if (!mounted) return;
        setState(() => _network.add(r));
      }

      if (s.legacyReady) {
        DiagnosticResult r;
        switch (s.provider) {
          case LlmProvider.anthropic:
            r = await d.testTool(title: 'الأداة الافتراضية (Claude)', kind: AiKind.anthropic, apiKey: s.anthropicKey, model: s.anthropicModel);
            break;
          case LlmProvider.gemini:
            r = await d.testTool(title: 'الأداة الافتراضية (Gemini)', kind: AiKind.gemini, apiKey: s.geminiKey, model: s.geminiModel);
            break;
          case LlmProvider.omniroute:
            r = await d.testTool(
              title: 'الأداة الافتراضية (OmniRoute)',
              kind: AiKind.openai,
              apiKey: s.omnirouteKey,
              model: s.omnirouteModel,
              baseUrl: s.omnirouteUrl,
              autoV1: true,
            );
            break;
        }
        if (!mounted) return;
        setState(() => _tools.add(r));
      }
      for (final p in s.profiles.where((p) => p.enabled)) {
        final r = await d.testTool(
          title: p.name,
          kind: p.kind,
          apiKey: p.apiKey,
          model: p.model,
          baseUrl: p.baseUrl,
        );
        if (!mounted) return;
        setState(() => _tools.add(r));
      }
    } finally {
      transport.close();
      if (mounted) setState(() => _running = false);
    }
  }

  Widget _row(DiagnosticResult r) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(r.ok ? Icons.check_circle : Icons.cancel, color: r.ok ? cs.primary : cs.error),
      title: Text(r.title),
      subtitle: Text(r.detail),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('فحص الاتصال والمفاتيح')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'يفحص هل يصل الجهاز لخوادم الذكاء الاصطناعي، ثم يتحقق من كل مفتاح ونموذج. '
              'إن فشل فحص «الشبكة» فالمشكلة في الاتصال/الإذن/الـ DNS وليست في المفتاح.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.network_check),
              label: Text(_running ? 'جارٍ الفحص...' : 'ابدأ الفحص'),
            ),
            if (_network.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('1) الشبكة', style: theme.textTheme.titleMedium),
              for (final r in _network) _row(r),
              if (!_running)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(Diagnostics.networkVerdict(_network)),
                ),
            ],
            if (_tools.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('2) المفاتيح والنماذج', style: theme.textTheme.titleMedium),
              for (final r in _tools) _row(r),
            ],
          ],
        ),
      ),
    );
  }
}
