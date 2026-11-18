import '../models/project_file.dart';
import 'project_packager.dart';

/// قوالب جاهزة لإنشاء مشروع فارغ يدوياً.
class ProjectTemplates {
  ProjectTemplates._();

  static List<ProjectFile> blank(String displayName) {
    final pkg = ProjectPackager.sanitizePackageName(displayName);
    return [
      ProjectFile.text('pubspec.yaml', '''
name: $pkg
description: Flutter project created in AI App Factory
publish_to: "none"
version: 1.0.0+1

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
'''),
      ProjectFile.text('analysis_options.yaml', 'include: package:flutter_lints/flutter.yaml\n'),
      ProjectFile.text('lib/main.dart', _main),
    ];
  }

  static const String _main = r'''
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تطبيقي',
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تطبيقي')),
      body: Center(child: Text('العدّاد: $_count', style: Theme.of(context).textTheme.headlineMedium)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _count++),
        child: const Icon(Icons.add),
      ),
    );
  }
}
''';
}
