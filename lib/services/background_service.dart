import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// معالج فارغ: الخدمة الأمامية هنا وظيفتها إبقاء العملية حيّة (مع قفل CPU و WiFi)
/// بينما يعمل خط الإنتاج في الـ isolate الرئيسي.
@pragma('vm:entry-point')
void backgroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(_IdleTaskHandler());
}

class _IdleTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

/// تشغيل التطبيق في الخلفية عبر Foreground Service (أندرويد فقط).
/// كل الدوال آمنة: أي فشل لا يوقف عمل التطبيق.
class BackgroundService {
  BackgroundService._();

  static bool _initialized = false;
  static String _lastText = '';

  static bool get supported => Platform.isAndroid;

  static void init() {
    if (!supported || _initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'app_factory_background',
        channelName: 'مصنع التطبيقات - العمل في الخلفية',
        channelDescription: 'يُبقي التصنيع والبناء مستمراً عند قفل الشاشة',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  /// يطلب إذن الإشعارات (أندرويد 13+) واستثناء توفير البطارية.
  static Future<void> requestPermissions() async {
    if (!supported) return;
    try {
      await FlutterForegroundTask.requestNotificationPermission();
      final ignoring = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (!ignoring) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (_) {
      // غير حرج.
    }
  }

  static Future<void> start(String text) async {
    if (!supported) return;
    try {
      init();
      _lastText = text;
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'مصنع التطبيقات',
          notificationText: text,
        );
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 4711,
          notificationTitle: 'مصنع التطبيقات',
          notificationText: text,
          callback: backgroundStartCallback,
        );
      }
    } catch (_) {
      // نكمل العمل بدون خدمة خلفية.
    }
  }

  static Future<void> update(String text) async {
    if (!supported || text == _lastText) return;
    _lastText = text;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'مصنع التطبيقات',
          notificationText: text,
        );
      }
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!supported) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }
}
