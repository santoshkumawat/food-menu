import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Slot { morning, breakfast, lunch, dinner, night }

extension SlotInfo on Slot {
  String get label => switch (this) {
        Slot.morning => 'Morning routine',
        Slot.breakfast => 'Breakfast',
        Slot.lunch => 'Lunch',
        Slot.dinner => 'Dinner',
        Slot.night => 'Bedtime',
      };

  IconData get icon => switch (this) {
        Slot.morning => Icons.wb_sunny_outlined,
        Slot.breakfast => Icons.free_breakfast_outlined,
        Slot.lunch => Icons.lunch_dining_outlined,
        Slot.dinner => Icons.dinner_dining_outlined,
        Slot.night => Icons.nightlight_outlined,
      };

  /// Meals that get cooked (the others are routine reminders).
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
    Slot.morning => we ? _t(10, 15) : _t(7, 45),
    Slot.breakfast => we ? _t(11, 30) : _t(10, 0),
    Slot.lunch => we ? _t(14, 0) : _t(13, 0),
    Slot.dinner => we ? _t(21, 0) : _t(20, 0),
    Slot.night => we ? _t(22, 30) : _t(21, 30),
  };
}

/// Default notification times: one hour before each meal.
int _defaultNotify(bool weekend, Slot slot) {
  final t = eatTime(weekend ? DateTime.saturday : DateTime.monday, slot);
  return slot.isMeal ? t - 60 : t;
}

const _almonds = 'Warm water + 1 tsp honey, soaked almonds, kishmish, walnuts';
const _shilajit = 'Lukewarm water + Shilajit';
const _milk = 'Turmeric milk';

Map<int, Map<Slot, String>> _defaultMenu() {
  Map<Slot, String> d(String morning, String b, String l, String di,
          [String night = '']) =>
      {
        Slot.morning: morning,
        Slot.breakfast: b,
        Slot.lunch: l,
        Slot.dinner: di,
        Slot.night: night,
      };
  const mixDal = 'Roti, Sabji (mix dal: toor, chana, masoor, urad), salad';
  return {
    1: d(_almonds, 'Sooji Cheela', mixDal, mixDal),
    2: d(_shilajit, 'Lobhia Chaat',
        'Roti, Sabji (Aloo, Bhindi, Gobhi), salad, curd', 'Sev Paratha', _milk),
    3: d(_almonds, 'Green Moong Cheela', 'Rice, toor dal, salad',
        'Roti + sabzi'),
    4: d(_shilajit, 'Chole / Kale Chana Mungfali Chhat',
        'Roti, yellow moong dal (kale chana), salad, curd', 'Aloo Paratha',
        _milk),
    5: d(_almonds, 'Besan Cheela', 'Roti, Sabji (hare chana), salad, curd',
        'Rice, toor dal'),
    6: d(_shilajit, 'Sevaiyya', 'Rajma Chawal / Dosa', 'Rajma Chawal / Dosa',
        _milk),
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

class AppStore extends ChangeNotifier {
  AppStore(this._prefs) {
    _load();
  }

  static const _key = 'store_v1';
  final SharedPreferences _prefs;

  Map<int, Map<Slot, String>> menu = _defaultMenu();
  final Map<String, int> _notifyTimes = {};
  bool notificationsOn = true;
  List<String> medicines = [];
  List<String> guidelines = [...defaultGuidelines];

  String dish(int weekday, Slot slot) => menu[weekday]![slot] ?? '';

  int notifyTime(int weekday, Slot slot) {
    final we = isWeekend(weekday);
    return _notifyTimes['${we ? 1 : 0}_${slot.name}'] ??
        _defaultNotify(we, slot);
  }

  void setDish(int weekday, Slot slot, String text) {
    menu[weekday]![slot] = text.trim();
    _save();
  }

  void setNotifyTime(bool weekend, Slot slot, int minutes) {
    _notifyTimes['${weekend ? 1 : 0}_${slot.name}'] = minutes;
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

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final m = j['menu'] as Map<String, dynamic>;
      for (final e in m.entries) {
        final day = int.parse(e.key);
        for (final s in Slot.values) {
          final v = (e.value as Map<String, dynamic>)[s.name];
          if (v is String) menu[day]![s] = v;
        }
      }
      (j['times'] as Map<String, dynamic>)
          .forEach((k, v) => _notifyTimes[k] = v as int);
      notificationsOn = j['on'] as bool? ?? true;
      medicines = List<String>.from(j['medicines'] ?? []);
      guidelines = List<String>.from(j['guidelines'] ?? defaultGuidelines);
    } catch (_) {
      // Corrupt data: keep defaults.
    }
  }

  void _save() {
    _prefs.setString(
      _key,
      jsonEncode({
        'menu': {
          for (final e in menu.entries)
            '${e.key}': {for (final s in e.value.entries) s.key.name: s.value},
        },
        'times': _notifyTimes,
        'on': notificationsOn,
        'medicines': medicines,
        'guidelines': guidelines,
      }),
    );
    notifyListeners();
  }
}
