import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'store.dart';
import 'sync.dart';
import 'tasks.dart';

const _doneAction = 'done';
const _daysAhead = 7;

/// Tapping "Done" on a notification while the app is closed.
@pragma('vm:entry-point')
Future<void> onNotificationBackground(NotificationResponse r) async {
  await Notifier.instance.init();
  await Notifier.instance.handleResponse(r);
}

class Notifier {
  Notifier._();
  static final instance = Notifier._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Called in the foreground after a "Done" tap, so the UI can refresh.
  VoidCallback? onDoneChanged;

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    if (!supported || _ready) return;
    tzdata.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: handleResponse,
      onDidReceiveBackgroundNotificationResponse: onNotificationBackground,
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

  // --- "Done" handling ----------------------------------------------------

  Future<void> handleResponse(NotificationResponse r) async {
    if (r.actionId != _doneAction) return;
    final parts = (r.payload ?? '').split('|'); // 20261007|cook
    if (parts.length != 2) return;
    await markDone(DateTime.parse(parts[0]), parts[1]);
  }

  /// Records "cook" or "soak" as done for [date], tells the family, and
  /// drops that day's pending follow-up reminder.
  Future<void> markDone(DateTime date, String kind) async {
    final prefs = await SharedPreferences.getInstance();
    await DoneLog.add(prefs, doneKey(date, kind));
    for (final t in Task.values.where((t) => t.doneKind == kind)) {
      await _plugin.cancel(id: _id(date, t));
    }
    onDoneChanged?.call();
    await Sync.pushDone(doneKey(date, kind));
  }

  // --- scheduling ---------------------------------------------------------

  int _id(DateTime d, Task t) =>
      DateTime.utc(d.year, d.month, d.day)
              .difference(DateTime.utc(2020))
              .inDays *
          20 +
      t.index;

  Future<void> _queue = Future.value();

  /// Cancels pending reminders and schedules the next week for this role.
  /// Runs one at a time so overlapping calls can't cancel each other's work.
  Future<void> reschedule(AppStore store) {
    _queue = _queue.then((_) => _reschedule(store)).catchError((_) {});
    return _queue;
  }

  Future<void> _reschedule(AppStore store) async {
    if (!_ready) return;
    await _plugin.cancelAllPendingNotifications();
    final role = store.role;
    if (role == null || !store.notificationsOn) return;

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final exact = await android?.canScheduleExactNotifications() ?? false;
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    final now = tz.TZDateTime.now(tz.local);
    for (var i = 0; i < _daysAhead; i++) {
      final day = DateTime(now.year, now.month, now.day).add(Duration(days: i));
      for (final task in Task.forRole(role)) {
        final kind = task.doneKind;
        if (kind != null && store.isDone(day, kind)) continue;
        final content = _content(store, task, day);
        if (content == null) continue;
        final minutes = store.taskTime(task, day.weekday);
        final when = tz.TZDateTime(tz.local, day.year, day.month, day.day,
            minutes ~/ 60, minutes % 60);
        if (!when.isAfter(now)) continue;
        await _plugin.zonedSchedule(
          id: _id(day, task),
          title: content.title,
          body: content.body,
          scheduledDate: when,
          payload: kind == null ? null : '${dateKey(day)}|$kind',
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'daily_menu',
              'Daily menu',
              channelDescription: 'Meal and routine reminders',
              importance: Importance.high,
              priority: Priority.high,
              styleInformation: BigTextStyleInformation(content.body),
              actions: kind == null
                  ? null
                  : [AndroidNotificationAction(_doneAction, content.doneLabel)],
            ),
          ),
          androidScheduleMode: mode,
        );
      }
    }
  }

  ({String title, String body, String doneLabel})? _content(
      AppStore s, Task task, DateTime day) {
    final wd = day.weekday;
    String d(Slot slot) => s.dish(wd, slot);
    final tomorrowWd = day.add(const Duration(days: 1)).weekday;

    switch (task) {
      case Task.cookWake:
        return (
          title: 'Good morning! Plan today\'s cooking',
          body: 'Breakfast: ${_or(d(Slot.breakfast))}\n'
              'Lunch: ${_or(d(Slot.lunch))}',
          doneLabel: 'Prepared',
        );
      case Task.cookFollow:
        return (
          title: 'Breakfast & lunch should be prepared',
          body: 'Breakfast: ${_or(d(Slot.breakfast))}\n'
              'Lunch: ${_or(d(Slot.lunch))}',
          doneLabel: 'Prepared',
        );
      case Task.cookDinner:
        return (
          title: 'What to cook for dinner',
          body: _or(d(Slot.dinner)),
          doneLabel: '',
        );
      case Task.cookSoak:
      case Task.cookSoakFollow:
        // Only on nights before a morning that includes almonds.
        if (!s.dish(tomorrowWd, Slot.morning).toLowerCase().contains('almond')) {
          return null;
        }
        return (
          title: task == Task.cookSoak
              ? 'Soak dry fruits for tomorrow morning'
              : 'Did you soak the dry fruits?',
          body: 'Almonds, kishmish and walnuts.',
          doneLabel: 'Soaked',
        );
      case Task.meWater:
        return (
          title: 'Morning routine',
          body: _or(d(Slot.morning), 'Warm water + soaked dry fruits'),
          doneLabel: '',
        );
      case Task.meBreakfast:
      case Task.meLunch:
      case Task.meSnack:
      case Task.meDinner:
        final text = d(task.slot!);
        if (text.isEmpty) return null;
        return (
          title: '${task.slot!.label} time',
          body: text,
          doneLabel: '',
        );
      case Task.meMilk:
        return (
          title: 'Turmeric milk',
          body: _or(d(Slot.night), 'Time for your turmeric milk'),
          doneLabel: '',
        );
    }
  }

  String _or(String v, [String fallback = 'Not set']) =>
      v.isEmpty ? fallback : v;

  // --- one-off notifications ---------------------------------------------

  Future<void> showNow(String title, String body, {int id = 999}) async {
    if (!_ready) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('daily_menu', 'Daily menu',
            importance: Importance.high, priority: Priority.high),
      ),
    );
  }
}
