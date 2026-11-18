import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_profile.dart';
import '../models/app_settings.dart';
import '../models/build_models.dart';

class SettingsStore {
  static const _provider = 'provider';
  static const _anthropicKey = 'anthropicKey';
  static const _geminiKey = 'geminiKey';
  static const _anthropicModel = 'anthropicModel';
  static const _geminiModel = 'geminiModel';
  static const _githubToken = 'githubToken';
  static const _privateRepos = 'privateRepos';
  static const _autoFix = 'autoFix';
  static const _maxFix = 'maxFixAttempts';
  static const _pages = 'publishWebToPages';
  static const _target = 'defaultTarget';
  static const _background = 'backgroundMode';
  static const _smart = 'smartRouting';
  static const _profiles = 'aiProfiles';
  static const _stats = 'aiStats';
  static const _omniUrl = 'omnirouteUrl';
  static const _omniKey = 'omnirouteKey';
  static const _omniModel = 'omnirouteModel';

  Future<AppSettings> load() async {
    const d = AppSettings();
    try {
      final p = await SharedPreferences.getInstance();
      return AppSettings(
        provider: LlmProvider.values.firstWhere(
          (e) => e.name == p.getString(_provider),
          orElse: () => LlmProvider.anthropic,
        ),
        anthropicKey: p.getString(_anthropicKey) ?? '',
        geminiKey: p.getString(_geminiKey) ?? '',
        anthropicModel: p.getString(_anthropicModel) ?? d.anthropicModel,
        geminiModel: p.getString(_geminiModel) ?? d.geminiModel,
        omnirouteUrl: p.getString(_omniUrl) ?? d.omnirouteUrl,
        omnirouteKey: p.getString(_omniKey) ?? '',
        omnirouteModel: p.getString(_omniModel) ?? '',
        githubToken: p.getString(_githubToken) ?? '',
        privateRepos: p.getBool(_privateRepos) ?? d.privateRepos,
        autoFix: p.getBool(_autoFix) ?? d.autoFix,
        maxFixAttempts: p.getInt(_maxFix) ?? d.maxFixAttempts,
        publishWebToPages: p.getBool(_pages) ?? d.publishWebToPages,
        defaultTarget: BuildTargetX.fromName(p.getString(_target)),
        backgroundMode: p.getBool(_background) ?? d.backgroundMode,
        smartRouting: p.getBool(_smart) ?? d.smartRouting,
        profiles: _decodeProfiles(p.getString(_profiles)),
      );
    } catch (_) {
      return d;
    }
  }

  Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_provider, s.provider.name);
    await p.setString(_anthropicKey, s.anthropicKey);
    await p.setString(_geminiKey, s.geminiKey);
    await p.setString(_anthropicModel, s.anthropicModel);
    await p.setString(_geminiModel, s.geminiModel);
    await p.setString(_omniUrl, s.omnirouteUrl);
    await p.setString(_omniKey, s.omnirouteKey);
    await p.setString(_omniModel, s.omnirouteModel);
    await p.setString(_githubToken, s.githubToken);
    await p.setBool(_privateRepos, s.privateRepos);
    await p.setBool(_autoFix, s.autoFix);
    await p.setInt(_maxFix, s.maxFixAttempts);
    await p.setBool(_pages, s.publishWebToPages);
    await p.setString(_target, s.defaultTarget.name);
    await p.setBool(_background, s.backgroundMode);
    await p.setBool(_smart, s.smartRouting);
    await p.setString(_profiles, jsonEncode(s.profiles.map((e) => e.toJson()).toList()));
  }

  static List<AiProfile> _decodeProfiles(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final d = jsonDecode(raw);
      if (d is! List) return const [];
      return d.whereType<Map>().map((m) => AiProfile.fromJson(Map<String, dynamic>.from(m))).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<String?> loadStats() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(_stats);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveStats(String json) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_stats, json);
    } catch (_) {}
  }
}
