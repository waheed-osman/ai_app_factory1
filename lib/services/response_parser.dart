import 'dart:convert';

import '../core/errors.dart';
import '../models/project_file.dart';

/// يحوّل رد النموذج (### FILE: path + كتلة كود) إلى ملفات مشروع.
class ResponseParser {
  ResponseParser._();

  static final RegExp _header = RegExp(r'^\s*###\s*FILE:\s*(.+?)\s*$');

  static List<ProjectFile> parse(String response) {
    final lines = const LineSplitter().convert(response);
    final contents = <String, String>{};
    var truncated = false;
    var i = 0;
    while (i < lines.length) {
      final m = _header.firstMatch(lines[i]);
      if (m == null) {
        i++;
        continue;
      }
      final path = cleanPath(m.group(1)!);
      i++;
      while (i < lines.length && lines[i].trim().isEmpty) {
        i++;
      }
      if (i >= lines.length || !lines[i].trimLeft().startsWith('```')) {
        continue;
      }
      i++;
      final buf = <String>[];
      var closed = false;
      while (i < lines.length) {
        if (lines[i].trim() == '```') {
          closed = true;
          i++;
          break;
        }
        buf.add(lines[i]);
        i++;
      }
      if (!closed) truncated = true;
      if (path != null) contents[path] = '${buf.join('\n')}\n';
    }
    if (contents.isEmpty) {
      throw const FactoryException(
        'لم يُرجع النموذج أي ملفات بالصيغة المطلوبة. أعد المحاولة أو غيّر الوصف.',
      );
    }
    if (truncated) {
      throw const FactoryException(
        'الرد مقطوع قبل اكتمال الملفات (تجاوز حد الطول). بسّط الفكرة وأعد المحاولة.',
      );
    }
    return contents.entries
        .map((e) => ProjectFile.text(e.key, e.value))
        .toList();
  }

  /// تنظيف المسار: يرفض المسارات المطلقة والخروج من الجذر.
  static String? cleanPath(String raw) {
    var p = raw.trim();
    p = p.replaceAll('`', '').replaceAll('"', '').replaceAll("'", '');
    p = p.replaceAll('\\', '/');
    while (p.startsWith('./')) {
      p = p.substring(2);
    }
    if (p.isEmpty || p.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(p)) {
      return null;
    }
    final parts = p.split('/');
    if (parts.any((s) => s == '..' || s.isEmpty)) return null;
    return p;
  }
}
