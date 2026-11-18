import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'providers/factory_controller.dart';
import 'providers/projects_controller.dart';
import 'providers/settings_controller.dart';
import 'screens/home_screen.dart';
import 'services/background_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BackgroundService.init();
  final settings = SettingsController();
  await settings.load();
  final projects = ProjectsController();
  await projects.load();
  runApp(FactoryApp(settings: settings, projects: projects));
}

class FactoryApp extends StatelessWidget {
  const FactoryApp({super.key, required this.settings, required this.projects});

  final SettingsController settings;
  final ProjectsController projects;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<ProjectsController>.value(value: projects),
        ChangeNotifierProvider<FactoryController>(
          create: (_) => FactoryController(settings, projects),
        ),
      ],
      child: MaterialApp(
        title: 'مصنع التطبيقات',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
