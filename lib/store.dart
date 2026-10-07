import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tasks.dart';

enum Slot { morning, breakfast, lunch, snack, dinner, night }

extension SlotInfo on Slot {
  String get label => switch (this) {
        Slot.morning => 'Morning Routine',
        Slot.breakfast => 'Breakfast',
        Slot.lunch => 'Lunch',
        Slot.snack => 'Evening Snacks',
        Slot.dinner => 'Dinner',
        Slot.night => 'Bedtime',
      };

  IconData get icon => switch (this) {
        Slot.morning => Icons.wb_sunny_outlined,
        Slot.breakfast => Icons.free_breakfast_outlined,
        Slot.lunch => Icons.lunch_dining_outlined,
        Slot.snack => Icons.cookie_outlined,
        Slot.dinner => Icons.dinner_dining_outlined,
        Slot.night => Icons.nightlight_outlined,
      };

  /// Placeholder shown in the edit box while it is empty.
  String get hint => switch (this) {
        Slot.morning => 'e.g. Warm water with honey, soaked almonds and walnuts',
        Slot.breakfast => 'e.g. Moong dal cheela, poha with peanuts, vegetable oats upma',
        Slot.lunch => 'e.g. Roti, dal, seasonal sabzi, cucumber salad',
        Slot.snack => 'e.g. Roasted chana, fruit, makhana, sprouts chaat',
        Slot.dinner => 'e.g. Moong dal khichdi, vegetable soup, 2 roti with lauki sabzi',
        Slot.night => 'e.g. Warm turmeric milk, or a glass of plain milk',
      };

  /// Same as [label]: every screen uses one name per slot.
  String get shortLabel => label;

  /// Icon colour for this slot, from the Expensely palette
  /// (warm, expense, good, cool, income, accent) for each theme.
  Color tone(Brightness b) {
    final dark = b == Brightness.dark;
    return switch (this) {
      Slot.morning => const Color(0xFFE58B3A),
      Slot.breakfast => dark ? const Color(0xFFD19B6B) : const Color(0xFF7F5229),
      Slot.lunch => const Color(0xFF4FA58A),
      Slot.snack => dark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
      Slot.dinner => dark ? const Color(0xFF68A19D) : const Color(0xFF3A6F61),
      Slot.night => dark ? const Color(0xFFD1D5DB) : const Color(0xFF1F2937),
    };
  }

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

/// Nothing is pre-filled: every family fills in its own menu, guidelines and
/// reminder times.
Map<int, Map<Slot, String>> defaultMenu() => {
      for (var day = 1; day <= 7; day++)
        day: {for (final s in Slot.values) s: ''},
    };

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
  static const _themeKey = 'theme_mode';
  final SharedPreferences prefs;

  Map<int, Map<Slot, String>> menu = defaultMenu();
  final Map<String, int> _taskTimes = {};
  bool notificationsOn = true;
  List<String> medicines = [];
  List<String> guidelines = [];

  ThemeMode themeMode = ThemeMode.system;

  Role? role;
  String myName = '';
  String? familyCode;
  bool isAdmin = false;
  String familyName = '';
  int lastSeenRev = 0;
  Set<String> done = {};

  /// Called after the user edits shared data: menu or guidelines
  /// (not for edits received from sync).
  VoidCallback? onMenuEdited;

  /// Called after the user edits their personal medicine list.
  VoidCallback? onMedicinesEdited;

  bool get isSetUp => role != null;

  String dish(int weekday, Slot slot) => menu[weekday]![slot] ?? '';

  /// Minutes after midnight, or null when this member has not set one.
  int? taskTime(Task t, int weekday) =>
      _taskTimes['${isWeekend(weekday) ? 1 : 0}_${t.name}'];

  bool get hasAnyTaskTime => _taskTimes.isNotEmpty;

  void clearTaskTime(bool weekend, Task t) {
    _taskTimes.remove('${weekend ? 1 : 0}_${t.name}');
    _save();
  }

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

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    prefs.setString(_themeKey, mode.name);
    notifyListeners();
  }

  void setNotificationsOn(bool v) {
    notificationsOn = v;
    _save();
  }

  /// Medicine timings are personal: never shared with the family, but saved
  /// to this person's own account so they follow them to a new phone.
  void setMedicines(List<String> v) {
    medicines = v;
    _save();
    onMedicinesEdited?.call();
  }

  /// The signed-in person's list as saved on their account.
  void loadMedicines(List<String> v) {
    if (listEquals(medicines, v)) return;
    medicines = v;
    _save();
  }

  /// Forgets everything personal (on sign out).
  void clearPersonal() {
    medicines = [];
    _save();
  }

  void setGuidelines(List<String> v) {
    guidelines = v;
    _save();
    onMenuEdited?.call();
  }

  void setProfile(Role r, String name, String? code,
      {bool admin = false, String family = ''}) {
    role = r;
    myName = name.trim();
    familyCode = code;
    isAdmin = admin;
    familyName = family;
    _save();
  }

  /// Follows the member entry kept on the server (the admin can change the
  /// role at any time). Saves only when something changed.
  void syncMembership(Role r, String name, bool admin, String family) {
    if (role == r && myName == name && isAdmin == admin && familyName == family) {
      return;
    }
    role = r;
    myName = name;
    isAdmin = admin;
    familyName = family;
    _save();
  }

  void resetProfile() {
    role = null;
    myName = '';
    familyCode = null;
    isAdmin = false;
    familyName = '';
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

  /// Everything the family shares: menu and guidelines.
  Map<String, dynamic> sharedFields() => {
        'menu': menuToJson(),
        'guidelines': guidelines,
      };

  /// Replaces the shared data with the family's copy.
  void applyRemoteMenu(String json, int rev, {List<String>? guidelines}) {
    _menuFromJson(jsonDecode(json) as Map<String, dynamic>);
    if (guidelines != null) this.guidelines = guidelines;
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
    themeMode = switch (prefs.getString(_themeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final raw = prefs.getString(_key);
    final doneRaw = prefs.getStringList(DoneLog._key);
    done = (doneRaw ?? []).toSet();
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _menuFromJson(j['menu'] as Map<String, dynamic>);
      // Older builds saved the second role as `me` / `meBreakfast`, etc.
      (j['times'] as Map<String, dynamic>? ?? {}).forEach((k, v) =>
          _taskTimes[k.replaceFirst(RegExp(r'_me(?=[A-Z])'), '_member')] =
              v as int);
      notificationsOn = j['on'] as bool? ?? true;
      medicines = List<String>.from(j['medicines'] ?? []);
      guidelines = List<String>.from(j['guidelines'] ?? []);
      final r = j['role'] as String?;
      role = r == null
          ? null
          : Role.values.asNameMap()[r == 'me' ? 'familyMember' : r];
      myName = j['name'] as String? ?? '';
      familyCode = j['family'] as String?;
      isAdmin = j['admin'] as bool? ?? false;
      familyName = j['familyName'] as String? ?? '';
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
        'admin': isAdmin,
        'familyName': familyName,
        'rev': lastSeenRev,
      }),
    );
    notifyListeners();
  }
}
