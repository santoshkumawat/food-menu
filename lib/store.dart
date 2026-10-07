import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tasks.dart';

enum Slot { morning, breakfast, lunch, snack, dinner, night }

extension SlotInfo on Slot {
  String get label => switch (this) {
        Slot.morning => 'Morning routine',
        Slot.breakfast => 'Breakfast',
        Slot.lunch => 'Lunch',
        Slot.snack => 'Snacks',
        Slot.dinner => 'Dinner',
        Slot.night => 'Turmeric milk',
      };

  IconData get icon => switch (this) {
        Slot.morning => Icons.wb_sunny_outlined,
        Slot.breakfast => Icons.free_breakfast_outlined,
        Slot.lunch => Icons.lunch_dining_outlined,
        Slot.snack => Icons.cookie_outlined,
        Slot.dinner => Icons.dinner_dining_outlined,
        Slot.night => Icons.nightlight_outlined,
      };

  /// Meals that are always shown on the Today page, even when empty.
  bool get isMeal =>
      this == Slot.breakfast || this == Slot.lunch || this == Slot.dinner;
}

const dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

bool isWeekend(int weekday) => weekday >= DateTime.saturday;

String formatMinutes(int m) {
  final h = m ~/ 60, min = m % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${min.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

int _t(int h, int m) => h * 60 + m;

/// When the meal is eaten (from the sheet). Shown on the cards.
int eatTime(int weekday, Slot slot) {
  final we = isWeekend(weekday);
  return switch (slot) {
    Slot.morning => we ? _t(10, 15) : _t(8, 0),
    Slot.breakfast => we ? _t(11, 30) : _t(10, 0),
    Slot.lunch => we ? _t(14, 0) : _t(13, 0),
    Slot.snack => _t(17, 0),
    Slot.dinner => we ? _t(21, 0) : _t(20, 0),
    Slot.night => we ? _t(22, 30) : _t(21, 0),
  };
}

const _almonds = 'Warm water + 1 tsp honey, soaked almonds, kishmish, walnuts';
const _shilajit = 'Lukewarm water + Shilajit';
const _milk = 'Turmeric milk';

Map<int, Map<Slot, String>> defaultMenu() {
  Map<Slot, String> d(String morning, String b, String l, String di) => {
        Slot.morning: morning,
        Slot.breakfast: b,
        Slot.lunch: l,
        Slot.snack: '',
        Slot.dinner: di,
        Slot.night: _milk,
      };
  const mixDal = 'Roti, Sabji (mix dal: toor, chana, masoor, urad), salad';
  return {
    1: d(_almonds, 'Sooji Cheela', mixDal, mixDal),
    2: d(_shilajit, 'Lobhia Chaat',
        'Roti, Sabji (Aloo, Bhindi, Gobhi), salad, curd', 'Sev Paratha'),
    3: d(_almonds, 'Green Moong Cheela', 'Rice, toor dal, salad',
        'Roti + sabzi'),
    4: d(_shilajit, 'Chole / Kale Chana Mungfali Chhat',
        'Roti, yellow moong dal (kale chana), salad, curd', 'Aloo Paratha'),
    5: d(_almonds, 'Besan Cheela', 'Roti, Sabji (hare chana), salad, curd',
        'Rice, toor dal'),
    6: d(_shilajit, 'Sevaiyya', 'Rajma Chawal / Dosa', 'Rajma Chawal / Dosa'),
    7: d(_almonds, 'Poha with peanuts', 'Chole Chawal / Idli Sambhar',
        'Chole Chawal / Idli Sambhar'),
  };
}

const defaultGuidelines = [
  'Drink 3-4 liters of water',
  'Avoid fried food, excess salt, chips, cookies and sweets',
  'Use ghee in moderation',
  'Include turmeric milk every night',
  'Avoid curd at night (can have during lunch only)',
  'Alternate Shilajit and honey each morning',
  'Do not consume raw tomato or spinach (due to kidney stone history)',
];

/// Done flags (`20261007_cook`, `20261007_soak`) are kept in their own prefs
/// key so the notification action handler can write them without the store.
class DoneLog {
  static const _key = 'done_v1';

  static Future<Set<String>> load(SharedPreferences p) async {
    await p.reload();
    return (p.getStringList(_key) ?? []).toSet();
  }

  static Future<void> add(SharedPreferences p, String key) async {
    final s = await load(p);
    s.add(key);
    // Keep the last ~14 days only.
    final cutoff =
        dateKey(DateTime.now().subtract(const Duration(days: 14)));
    s.removeWhere((k) => k.split('_').first.compareTo(cutoff) < 0);
    await p.setStringList(_key, s.toList());
  }
}

class AppStore extends ChangeNotifier {
  AppStore(this.prefs) {
    _load();
  }

  static const _key = 'store_v1';
  final SharedPreferences prefs;

  Map<int, Map<Slot, String>> menu = defaultMenu();
  final Map<String, int> _taskTimes = {};
  bool notificationsOn = true;
  List<String> medicines = [];
  List<String> guidelines = [...defaultGuidelines];

  Role? role;
  String myName = '';
  String? familyCode;
  int lastSeenRev = 0;
  Set<String> done = {};

  /// Called after the user edits the menu (not for edits received from sync).
  VoidCallback? onMenuEdited;

  bool get isSetUp => role != null;

  String dish(int weekday, Slot slot) => menu[weekday]![slot] ?? '';

  int taskTime(Task t, int weekday) =>
      _taskTimes['${isWeekend(weekday) ? 1 : 0}_${t.name}'] ??
      (isWeekend(weekday) ? t.weekendTime : t.weekdayTime);

  bool isDone(DateTime d, String kind) => done.contains(doneKey(d, kind));

  void setDish(int weekday, Slot slot, String text) {
    menu[weekday]![slot] = text.trim();
    _save();
    onMenuEdited?.call();
  }

  void setTaskTime(bool weekend, Task t, int minutes) {
    _taskTimes['${weekend ? 1 : 0}_${t.name}'] = minutes;
    _save();
  }

  void setNotificationsOn(bool v) {
    notificationsOn = v;
    _save();
  }

  void setMedicines(List<String> v) {
    medicines = v;
    _save();
  }

  void setGuidelines(List<String> v) {
    guidelines = v;
    _save();
  }

  void setProfile(Role r, String name, String? code) {
    role = r;
    myName = name.trim();
    familyCode = code;
    _save();
  }

  void resetProfile() {
    role = null;
    myName = '';
    familyCode = null;
    lastSeenRev = 0;
    _save();
  }

  void leaveFamily() {
    familyCode = null;
    lastSeenRev = 0;
    _save();
  }

  Future<void> markDone(DateTime d, String kind) async {
    await DoneLog.add(prefs, doneKey(d, kind));
    done = await DoneLog.load(prefs);
    notifyListeners();
  }

  /// Re-reads everything saved, e.g. after the background check changed it.
  Future<void> reload() async {
    await prefs.reload();
    _load();
    notifyListeners();
  }

  Future<void> reloadDone() async {
    done = await DoneLog.load(prefs);
    notifyListeners();
  }

  // --- sync helpers -------------------------------------------------------

  String menuToJson() => jsonEncode({
        for (final e in menu.entries)
          '${e.key}': {for (final s in e.value.entries) s.key.name: s.value},
      });

  /// Replaces the menu with one received from the shared copy.
  void applyRemoteMenu(String json, int rev) {
    _menuFromJson(jsonDecode(json) as Map<String, dynamic>);
    lastSeenRev = rev;
    _save();
  }

  void setLastSeenRev(int rev) {
    lastSeenRev = rev;
    _save();
  }

  // --- persistence --------------------------------------------------------

  void _menuFromJson(Map<String, dynamic> m) {
    for (final e in m.entries) {
      final day = int.parse(e.key);
      for (final s in Slot.values) {
        final v = (e.value as Map<String, dynamic>)[s.name];
        if (v is String) menu[day]![s] = v;
      }
    }
  }

  void _load() {
    final raw = prefs.getString(_key);
    final doneRaw = prefs.getStringList(DoneLog._key);
    done = (doneRaw ?? []).toSet();
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _menuFromJson(j['menu'] as Map<String, dynamic>);
      (j['times'] as Map<String, dynamic>? ?? {})
          .forEach((k, v) => _taskTimes[k] = v as int);
      notificationsOn = j['on'] as bool? ?? true;
      medicines = List<String>.from(j['medicines'] ?? []);
      guidelines = List<String>.from(j['guidelines'] ?? defaultGuidelines);
      final r = j['role'] as String?;
      role = r == null ? null : Role.values.asNameMap()[r];
      myName = j['name'] as String? ?? '';
      familyCode = j['family'] as String?;
      lastSeenRev = j['rev'] as int? ?? 0;
    } catch (_) {
      // Corrupt data: keep defaults.
    }
  }

  void _save() {
    prefs.setString(
      _key,
      jsonEncode({
        'menu': jsonDecode(menuToJson()),
        'times': _taskTimes,
        'on': notificationsOn,
        'medicines': medicines,
        'guidelines': guidelines,
        'role': role?.name,
        'name': myName,
        'family': familyCode,
        'rev': lastSeenRev,
      }),
    );
    notifyListeners();
  }
}
