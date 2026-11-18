import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../services/ai_router.dart';
import '../services/settings_store.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({SettingsStore? store}) : _store = store ?? SettingsStore();

  final SettingsStore _store;

  /// إحصاءات أداء أدوات الذكاء الاصطناعي (للترتيب التلقائي).
  final ProviderStats stats = ProviderStats();

  AppSettings _settings = const AppSettings();
  bool _loaded = false;

  AppSettings get settings => _settings;

  bool get loaded => _loaded;

  Future<void> load() async {
    _settings = await _store.load();
    stats.loadJsonString(await _store.loadStats());
    stats.onChanged = () {
      _store.saveStats(stats.toJsonString());
      notifyListeners();
    };
    _loaded = true;
    notifyListeners();
  }

  Future<void> update(AppSettings next) async {
    _settings = next;
    notifyListeners();
    await _store.save(next);
  }
}
