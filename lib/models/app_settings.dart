import 'ai_profile.dart';
import 'build_models.dart';

enum LlmProvider { anthropic, gemini, omniroute }

class AppSettings {
  const AppSettings({
    this.provider = LlmProvider.anthropic,
    this.anthropicKey = '',
    this.geminiKey = '',
    this.anthropicModel = 'claude-sonnet-5-5',
    this.geminiModel = 'gemini-flash-lite-latest',
    this.omnirouteUrl = 'http://localhost:20128',
    this.omnirouteKey = '',
    this.omnirouteModel = '',
    this.githubToken = '',
    this.privateRepos = true,
    this.autoFix = true,
    this.maxFixAttempts = 3,
    this.publishWebToPages = true,
    this.defaultTarget = BuildTarget.apk,
    this.backgroundMode = true,
    this.smartRouting = true,
    this.profiles = const [],
  });

  final LlmProvider provider;
  final String anthropicKey;
  final String geminiKey;
  final String anthropicModel;
  final String geminiModel;
  final String omnirouteUrl;
  final String omnirouteKey;
  final String omnirouteModel;
  final String githubToken;
  final bool privateRepos;
  final bool autoFix;
  final int maxFixAttempts;
  final bool publishWebToPages;
  final BuildTarget defaultTarget;
  final bool backgroundMode;

  /// التنقل التلقائي بين الأدوات المضافة في قائمة «أدوات الذكاء الاصطناعي».
  final bool smartRouting;
  final List<AiProfile> profiles;

  String get llmKey {
    switch (provider) {
      case LlmProvider.anthropic:
        return anthropicKey;
      case LlmProvider.gemini:
        return geminiKey;
      case LlmProvider.omniroute:
        return omnirouteKey;
    }
  }

  String get llmModel {
    switch (provider) {
      case LlmProvider.anthropic:
        return anthropicModel;
      case LlmProvider.gemini:
        return geminiModel;
      case LlmProvider.omniroute:
        return omnirouteModel;
    }
  }

  /// OmniRoute قد يعمل بدون مفتاح (إن كان التوثيق معطلاً)، لكنه يحتاج رابطاً ونموذجاً.
  bool get llmReady => legacyReady || (smartRouting && profiles.any((p) => p.isUsable));

  /// جاهزية المزوّد الأساسي المختار في الإعدادات.
  bool get legacyReady {
    if (provider == LlmProvider.omniroute) {
      return omnirouteUrl.trim().isNotEmpty && omnirouteModel.trim().isNotEmpty;
    }
    return llmKey.trim().isNotEmpty;
  }

  bool get githubReady => githubToken.trim().isNotEmpty;

  AppSettings copyWith({
    LlmProvider? provider,
    String? anthropicKey,
    String? geminiKey,
    String? anthropicModel,
    String? geminiModel,
    String? omnirouteUrl,
    String? omnirouteKey,
    String? omnirouteModel,
    String? githubToken,
    bool? privateRepos,
    bool? autoFix,
    int? maxFixAttempts,
    bool? publishWebToPages,
    BuildTarget? defaultTarget,
    bool? backgroundMode,
    bool? smartRouting,
    List<AiProfile>? profiles,
  }) {
    return AppSettings(
      provider: provider ?? this.provider,
      anthropicKey: anthropicKey ?? this.anthropicKey,
      geminiKey: geminiKey ?? this.geminiKey,
      anthropicModel: anthropicModel ?? this.anthropicModel,
      geminiModel: geminiModel ?? this.geminiModel,
      omnirouteUrl: omnirouteUrl ?? this.omnirouteUrl,
      omnirouteKey: omnirouteKey ?? this.omnirouteKey,
      omnirouteModel: omnirouteModel ?? this.omnirouteModel,
      githubToken: githubToken ?? this.githubToken,
      privateRepos: privateRepos ?? this.privateRepos,
      autoFix: autoFix ?? this.autoFix,
      maxFixAttempts: maxFixAttempts ?? this.maxFixAttempts,
      publishWebToPages: publishWebToPages ?? this.publishWebToPages,
      defaultTarget: defaultTarget ?? this.defaultTarget,
      backgroundMode: backgroundMode ?? this.backgroundMode,
      smartRouting: smartRouting ?? this.smartRouting,
      profiles: profiles ?? this.profiles,
    );
  }
}
