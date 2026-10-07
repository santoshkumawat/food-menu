import 'store.dart';

/// Who is using this phone.
enum Role {
  cook('Cook (makes the food)'),
  me('Me (eats and plans the menu)');

  const Role(this.label);
  final String label;
}

/// A reminder that can be scheduled. Each task belongs to one role.
enum Task {
  // Cook
  cookWake(Role.cook, 'Wake-up: today\'s breakfast & lunch', 7 * 60, 10 * 60),
  cookFollow(Role.cook, 'Follow-up if not prepared', 8 * 60, 11 * 60),
  cookDinner(Role.cook, 'Tonight\'s dinner', 18 * 60, 18 * 60),
  cookSoak(Role.cook, 'Soak dry fruits for tomorrow', 21 * 60, 21 * 60),
  cookSoakFollow(Role.cook, 'Soaking follow-up', 21 * 60 + 30, 21 * 60 + 30),
  // Me
  meWater(Role.me, 'Warm water + soaked dry fruits', 8 * 60, 10 * 60 + 15),
  meBreakfast(Role.me, 'Breakfast', 10 * 60, 11 * 60 + 30),
  meLunch(Role.me, 'Lunch', 13 * 60, 14 * 60),
  meSnack(Role.me, 'Snacks', 17 * 60, 17 * 60),
  meDinner(Role.me, 'Dinner', 20 * 60, 21 * 60),
  meMilk(Role.me, 'Turmeric milk', 21 * 60, 22 * 60 + 30);

  const Task(this.role, this.label, this.weekdayTime, this.weekendTime);

  final Role role;
  final String label;
  final int weekdayTime;
  final int weekendTime;

  /// Done flag this task relates to ('cook' or 'soak'); null if none.
  String? get doneKind => switch (this) {
        cookWake || cookFollow => 'cook',
        cookSoak || cookSoakFollow => 'soak',
        _ => null,
      };

  bool get isFollowUp => this == cookFollow || this == cookSoakFollow;

  /// The Slot this task reads its text from (null = built from other slots).
  Slot? get slot => switch (this) {
        meWater => Slot.morning,
        meBreakfast => Slot.breakfast,
        meLunch => Slot.lunch,
        meSnack => Slot.snack,
        meDinner => Slot.dinner,
        meMilk => Slot.night,
        cookDinner => Slot.dinner,
        _ => null,
      };

  static List<Task> forRole(Role r) =>
      Task.values.where((t) => t.role == r).toList();
}

String dateKey(DateTime d) =>
    '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

/// Key stored in the done log, e.g. `20261007_cook`.
String doneKey(DateTime d, String kind) => '${dateKey(d)}_$kind';
