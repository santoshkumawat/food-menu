import 'store.dart';

/// Who is using this phone.
enum Role {
  // The enum names are stored in saved data and on the server, so they stay
  // `cook` and `me`; only the display names below are user-facing.
  cook('Cook', 'Cook (makes the food)'),
  me('Family member', 'Family member (eats and plans the menu)');

  const Role(this.shortName, this.label);

  /// Compact name for lists and subtitles.
  final String shortName;

  /// Full description for choosing a role.
  final String label;
}

/// A reminder that can be scheduled. Each task belongs to one role.
enum Task {
  // Cook
  cookWake(Role.cook, 'Wake-up: today\'s breakfast & lunch'),
  cookFollow(Role.cook, 'Follow-up if not prepared'),
  cookDinner(Role.cook, 'Tonight\'s dinner'),
  cookSoak(Role.cook, 'Soak dry fruits for tomorrow'),
  cookSoakFollow(Role.cook, 'Soaking follow-up'),
  // Me
  meWater(Role.me, 'Morning routine'),
  meBreakfast(Role.me, 'Breakfast'),
  meLunch(Role.me, 'Lunch'),
  meSnack(Role.me, 'Snacks'),
  meDinner(Role.me, 'Dinner'),
  meMilk(Role.me, 'Turmeric milk');

  const Task(this.role, this.label);

  final Role role;
  final String label;

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
