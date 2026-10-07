import 'package:aaj_kya_banega/account.dart';
import 'package:aaj_kya_banega/main.dart';
import 'package:aaj_kya_banega/store.dart';
import 'package:aaj_kya_banega/tasks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<AppStore> newStore() async {
    SharedPreferences.setMockInitialValues({});
    return AppStore(await SharedPreferences.getInstance());
  }

  testWidgets('first run shows role setup', (tester) async {
    final store = await newStore();
    await tester.pumpWidget(App(store: store, session: Session(store)));
    expect(find.text('Who is using this phone?'), findsOneWidget);
  });

  testWidgets('cook sees today checklist and meals', (tester) async {
    final store = await newStore();
    store.setProfile(Role.cook, 'Test', null);
    await tester.pumpWidget(App(store: store, session: Session(store)));
    expect(find.text('Your checklist'), findsOneWidget);
    expect(find.textContaining('Breakfast'), findsWidgets);
  });

  testWidgets('filter pills narrow the Today list and Week fits a phone',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = await newStore();
    store.setProfile(Role.me, 'Test', null);
    await tester.pumpWidget(App(store: store, session: Session(store)));

    // Today: All shows the checklist; the Morning pill hides it.
    expect(find.text('Kitchen status'), findsOneWidget);
    await tester.tap(find.text('Morning'));
    await tester.pump();
    expect(find.text('Kitchen status'), findsNothing);

    // Week tab and the sort menu open without layout errors.
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(find.text('Monday'), findsOneWidget);
    await tester.tap(find.byTooltip('Sort days'));
    await tester.pumpAndSettle();
    expect(find.text('Starting today'), findsOneWidget);

    // Family and Health tabs and the top menu.
    await tester.tapAt(const Offset(10, 10)); // close the sort menu
    await tester.pumpAndSettle();
    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Health'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Reminders & times'), findsOneWidget);
  });

  test('menu survives a save and reload', () async {
    final store = await newStore();
    store.setDish(1, Slot.snack, 'Fruit chaat');
    final again = AppStore(store.prefs);
    expect(again.dish(1, Slot.snack), 'Fruit chaat');
  });

  test('theme choice is remembered', () async {
    final store = await newStore();
    expect(store.themeMode, ThemeMode.system);
    store.setThemeMode(ThemeMode.dark);
    expect(AppStore(store.prefs).themeMode, ThemeMode.dark);
  });

  test('a fresh install has no seeded menu, guidelines or reminder times',
      () async {
    final store = await newStore();
    for (var day = 1; day <= 7; day++) {
      for (final slot in Slot.values) {
        expect(store.dish(day, slot), isEmpty);
      }
    }
    expect(store.guidelines, isEmpty);
    expect(store.medicines, isEmpty);
    expect(store.hasAnyTaskTime, isFalse);
    for (final task in Task.values) {
      expect(store.taskTime(task, DateTime.monday), isNull);
      expect(store.taskTime(task, DateTime.saturday), isNull);
    }
  });

  test('reminder times are saved only when the member sets them', () async {
    final store = await newStore();
    store.setTaskTime(false, Task.meBreakfast, 10 * 60);
    final again = AppStore(store.prefs);
    expect(again.taskTime(Task.meBreakfast, DateTime.tuesday), 10 * 60);
    expect(again.taskTime(Task.meBreakfast, DateTime.sunday), isNull);
    again.clearTaskTime(false, Task.meBreakfast);
    expect(again.hasAnyTaskTime, isFalse);
  });

  test('family data (menu, guidelines, medicines) is replaced on join',
      () async {
    final admin = await newStore();
    admin.setDish(2, Slot.dinner, 'Sev Paratha');
    admin.setGuidelines(['Drink water']);
    admin.setMedicines(['8 AM - vitamin']);
    final shared = admin.sharedFields();

    // A new member's phone starts empty and receives the family's copy.
    final member = await newStore();
    member.setDish(1, Slot.lunch, 'local leftover');
    member.applyRemoteMenu(shared['menu'] as String, 4,
        guidelines: List<String>.from(shared['guidelines'] as List),
        medicines: List<String>.from(shared['medicines'] as List));

    final reopened = AppStore(member.prefs);
    expect(reopened.dish(2, Slot.dinner), 'Sev Paratha');
    expect(reopened.dish(1, Slot.lunch), isEmpty);
    expect(reopened.guidelines, ['Drink water']);
    expect(reopened.medicines, ['8 AM - vitamin']);
    expect(reopened.lastSeenRev, 4);
  });
}
