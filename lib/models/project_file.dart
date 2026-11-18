import 'dart:convert';
import 'dart:typed_data';

/// ملف واحد من ملفات المشروع (مسار نسبي + محتوى ثنائي).
class ProjectFile {
  ProjectFile(this.path, this.bytes);

  factory ProjectFile.text(String path, String content) =>
      ProjectFile(path, Uint8List.fromList(utf8.encode(content)));

  final String path;
  final Uint8List bytes;

  int get size => bytes.length;

  String get text => utf8.decode(bytes, allowMalformed: true);

  bool get isDart => path.endsWith('.dart');

  static const Set<String> _textExt = {
    'dart', 'yaml', 'yml', 'json', 'md', 'txt', 'xml', 'html', 'css', 'js',
    'gradle', 'properties', 'kt', 'java', 'arb', 'csv', 'gitignore', 'lock',
  };

  /// هل يمكن تعديل الملف كنص داخل التطبيق؟
  bool get isEditableText {
    if (size > 400 * 1024) return false;
    final name = path.split('/').last.toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return true;
    return _textExt.contains(name.substring(dot + 1));
  }
}
