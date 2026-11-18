import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/errors.dart';
import '../models/project_file.dart';
import '../models/project_meta.dart';
import 'project_packager.dart';

/// تخزين المشاريع على الجهاز: index.json + ملف ZIP لكل مشروع.
class ProjectStore {
  ProjectStore({Directory? root}) : _rootOverride = root;

  final Directory? _rootOverride;
  Future<void> _lock = Future<void>.value();

  Future<T> _sync<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _lock = _lock.catchError((Object _) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  Future<Directory> _dir() async {
    final base = _rootOverride ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'projects'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _indexFile() async => File(p.join((await _dir()).path, 'index.json'));

  Future<File> _zipFile(String id) async => File(p.join((await _dir()).path, '$id.zip'));

  Future<List<ProjectMeta>> _readIndex() async {
    try {
      final f = await _indexFile();
      if (!await f.exists()) return [];
      final data = jsonDecode(await f.readAsString());
      if (data is! List) return [];
      final list = data
          .whereType<Map>()
          .map((m) => ProjectMeta.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(List<ProjectMeta> items) async {
    final f = await _indexFile();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()), flush: true);
    await tmp.rename(f.path);
  }

  Future<List<ProjectMeta>> list() => _sync(_readIndex);

  Future<List<ProjectFile>> loadFiles(String id) => _sync(() async {
        final f = await _zipFile(id);
        if (!await f.exists()) {
          throw const FactoryException('ملفات المشروع غير موجودة على الجهاز.');
        }
        return ProjectPackager.unzip(Uint8List.fromList(await f.readAsBytes()));
      });

  /// يحفظ الملفات + البيانات الوصفية (ينشئ أو يحدّث).
  Future<ProjectMeta> save(ProjectMeta meta, List<ProjectFile> files) => _sync(() async {
        final zip = ProjectPackager.zip(files);
        final f = await _zipFile(meta.id);
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsBytes(zip, flush: true);
        await tmp.rename(f.path);
        final saved = meta.copyWith(
          updatedAt: DateTime.now(),
          fileCount: files.length,
          totalBytes: files.fold<int>(0, (s, e) => s + e.size),
        );
        final items = await _readIndex();
        items.removeWhere((e) => e.id == saved.id);
        items.add(saved);
        await _writeIndex(items);
        return saved;
      });

  /// تحديث البيانات الوصفية فقط (إعادة تسمية، رابط المستودع...).
  Future<void> saveMeta(ProjectMeta meta) => _sync(() async {
        final items = await _readIndex();
        final i = items.indexWhere((e) => e.id == meta.id);
        if (i < 0) return;
        items[i] = meta;
        await _writeIndex(items);
      });

  Future<void> delete(String id) => _sync(() async {
        final f = await _zipFile(id);
        if (await f.exists()) await f.delete();
        final items = await _readIndex();
        items.removeWhere((e) => e.id == id);
        await _writeIndex(items);
      });
}
