import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/errors.dart';
import '../models/project_file.dart';
import 'project_packager.dart';

/// حفظ ومشاركة الملفات وفتح الروابط.
class FileExporter {
  FileExporter._();

  static Future<File> _writeTemp(String filename, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> shareFile(String filename, Uint8List bytes, {String? text}) async {
    final file = await _writeTemp(filename, bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: text, subject: filename),
    );
  }

  static Future<void> shareProjectZip(List<ProjectFile> files, String name) {
    return shareFile('$name.zip', ProjectPackager.zip(files));
  }

  static Future<void> shareText(String text, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }

  /// يستخرج app-release.apk من ZIP الـ Artifact.
  static Uint8List extractApk(Uint8List artifactZip) {
    final archive = ZipDecoder().decodeBytes(artifactZip);
    for (final f in archive.files) {
      if (f.isFile && f.name.toLowerCase().endsWith('.apk')) {
        final c = f.content;
        if (c is List<int>) return Uint8List.fromList(c);
      }
    }
    throw const FactoryException('لم يُعثر على ملف APK داخل الملف الناتج.');
  }

  static Future<void> openUrl(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) throw const FactoryException('تعذر فتح الرابط.');
  }
}
