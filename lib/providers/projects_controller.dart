import 'package:flutter/foundation.dart';

import '../models/project_file.dart';
import '../models/project_meta.dart';
import '../services/project_store.dart';

/// مكتبة المشاريع المحفوظة على الجهاز.
class ProjectsController extends ChangeNotifier {
  ProjectsController({ProjectStore? store}) : _store = store ?? ProjectStore();

  final ProjectStore _store;

  List<ProjectMeta> _items = const [];
  bool _loaded = false;

  List<ProjectMeta> get items => _items;

  bool get loaded => _loaded;

  ProjectMeta? byId(String id) {
    for (final m in _items) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> load() async {
    _items = await _store.list();
    _loaded = true;
    notifyListeners();
  }

  Future<List<ProjectFile>> loadFiles(String id) => _store.loadFiles(id);

  Future<ProjectMeta> save(ProjectMeta meta, List<ProjectFile> files) async {
    final saved = await _store.save(meta, files);
    _items = await _store.list();
    notifyListeners();
    return saved;
  }

  Future<void> saveMeta(ProjectMeta meta) async {
    await _store.saveMeta(meta);
    _items = await _store.list();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    await _store.delete(id);
    _items = await _store.list();
    notifyListeners();
  }
}
