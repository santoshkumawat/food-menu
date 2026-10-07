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
}
