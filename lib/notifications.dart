import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'store.dart';

class Notifier {
  Notifier._();
  static final instance = Notifier._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    if (!supported) return;
    tzdata.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  Future<void> requestPermissions() async {
    if (!_ready) return;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    if (!(await android?.canScheduleExactNotifications() ?? true)) {
      await android?.requestExactAlarmsPermission();
    }
  }

  /// Cancels everything and schedules the weekly reminders again.
  Future<void> reschedule(AppStore store) async {
    if (!_ready) return;
    await _plugin.cancelAll();
    if (!store.notificationsOn) return;

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final exact = await android?.canScheduleExactNotifications() ?? false;
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    for (var day = 1; day <= 7; day++) {
      for (final slot in Slot.values) {
        final dish = store.dish(day, slot);
        if (dish.isEmpty) continue;
        await _plugin.zonedSchedule(
          id: day * 10 + slot.index,
          title: _title(slot),
          body: dish,
          scheduledDate: _nextOccurrence(day, store.notifyTime(day, slot)),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'daily_menu',
              'Daily menu',
              channelDescription: 'Breakfast, lunch and dinner reminders',
              importance: Importance.high,
              priority: Priority.high,
              styleInformation: BigTextStyleInformation(''),
            ),
          ),
          androidScheduleMode: mode,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
    }
  }

  String _title(Slot slot) => switch (slot) {
        Slot.morning => 'Good morning! Morning routine',
        Slot.breakfast => "Today's breakfast",
        Slot.lunch => "Today's lunch",
        Slot.dinner => "Tonight's dinner",
        Slot.night => 'Bedtime',
      };

  tz.TZDateTime _nextOccurrence(int weekday, int minutes) {
    final now = tz.TZDateTime.now(tz.local);
    var d = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
    while (d.weekday != weekday || d.isBefore(now)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  Future<void> showTest() async {
    if (!_ready) return;
    await _plugin.show(
      id: 999,
      title: 'Aaj Kya Banega?',
      body: 'Notifications are working.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('daily_menu', 'Daily menu',
            importance: Importance.high, priority: Priority.high),
      ),
    );
  }
}
