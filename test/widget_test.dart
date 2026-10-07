import 'dart:convert';

import 'package:aaj_kya_banega/account.dart';
import 'package:aaj_kya_banega/links.dart';
import 'package:aaj_kya_banega/main.dart';
import 'package:aaj_kya_banega/screens.dart';
import 'package:aaj_kya_banega/updates.dart';
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
    store.setProfile(Role.familyMember, 'Test', null);
    await tester.pumpWidget(App(store: store, session: Session(store)));

    // Today: the cook's checklist is not shown for the Family member role.
    expect(find.text('Your checklist'), findsNothing);
    expect(find.text('Kitchen status'), findsNothing);
    await tester.tap(find.text('Morning'));
    await tester.pump();
    expect(find.text('Morning routine'), findsWidgets);

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
    store.setTaskTime(false, Task.memberBreakfast, 10 * 60);
    final again = AppStore(store.prefs);
    expect(again.taskTime(Task.memberBreakfast, DateTime.tuesday), 10 * 60);
    expect(again.taskTime(Task.memberBreakfast, DateTime.sunday), isNull);
    again.clearTaskTime(false, Task.memberBreakfast);
    expect(again.hasAnyTaskTime, isFalse);
  });

  test('family menu and guidelines are replaced on join; medicines stay personal',
      () async {
    final admin = await newStore();
    admin.setDish(2, Slot.dinner, 'Sev Paratha');
    admin.setGuidelines(['Drink water']);
    admin.setMedicines(['8 AM - admin only']);
    final shared = admin.sharedFields();
    expect(shared.containsKey('medicines'), isFalse);

    // A new member's phone starts empty and receives the family's copy.
    final member = await newStore();
    member.setDish(1, Slot.lunch, 'local leftover');
    member.setMedicines(['9 PM - my own']);
    member.applyRemoteMenu(shared['menu'] as String, 4,
        guidelines: List<String>.from(shared['guidelines'] as List));

    final reopened = AppStore(member.prefs);
    expect(reopened.dish(2, Slot.dinner), 'Sev Paratha');
    expect(reopened.dish(1, Slot.lunch), isEmpty);
    expect(reopened.guidelines, ['Drink water']);
    // The family's guidelines arrive, but medicines stay personal.
    expect(reopened.medicines, ['9 PM - my own']);
    expect(reopened.lastSeenRev, 4);
  });

  test('roles are called Cook and Family member', () {
    expect(Role.cook.shortName, 'Cook');
    expect(Role.familyMember.shortName, 'Family member');
    expect(Role.familyMember.label, startsWith('Family member'));
    // These names are what gets saved on the phone and in Firestore.
    expect(Role.familyMember.name, 'familyMember');
    expect(Role.cook.name, 'cook');
  });

  test('data saved by an older build (role "me") still loads', () async {
    SharedPreferences.setMockInitialValues({
      'store_v1': jsonEncode({
        'menu': <String, dynamic>{},
        'role': 'me',
        'times': {'0_meBreakfast': 600},
      }),
    });
    final store = AppStore(await SharedPreferences.getInstance());
    expect(store.role, Role.familyMember);
    expect(store.taskTime(Task.memberBreakfast, DateTime.monday), 600);
  });

  test('the invite message carries the release link and how to sign in', () {
    final byEmail = inviteMessage('Kumawat family', 'anjali@example.com');
    expect(byEmail, contains(appDownloadUrl));
    expect(byEmail, contains('this email: anjali@example.com'));
    expect(byEmail, contains('Kumawat family'));

    final byName = inviteMessage('Kumawat family', 'anjali_k');
    expect(byName, contains('the username: anjali_k'));
    expect(appDownloadUrl, endsWith('/releases/latest'));
  });

  test('version comparison is numeric, not alphabetical', () {
    expect(isNewerVersion('v1.0.2', '1.0.1'), isTrue);
    expect(isNewerVersion('v1.0.10', '1.0.9'), isTrue);
    expect(isNewerVersion('v1.1', '1.0.5'), isTrue);
    expect(isNewerVersion('v2.0.0', '1.9.9'), isTrue);
    expect(isNewerVersion('v1.0.1', '1.0.1'), isFalse);
    expect(isNewerVersion('v1.0.0', '1.0.1'), isFalse);
    expect(isNewerVersion('1.0.1+2', '1.0.1'), isFalse);
  });

  test('GitHub release answers are read safely', () {
    final info = parseRelease({
      'tag_name': 'v1.0.2',
      'html_url': 'https://github.com/x/y/releases/tag/v1.0.2',
      'body': 'Fixes reminders',
    });
    expect(info!.version, '1.0.2');
    expect(info.url, endsWith('/v1.0.2'));
    expect(info.notes, 'Fixes reminders');
    expect(parseRelease({'tag_name': 'v1.0.3', 'draft': true}), isNull);
    expect(parseRelease({'tag_name': 'v1.0.3', 'prerelease': true}), isNull);
    expect(parseRelease({'name': 'no tag'}), isNull);
  });

  testWidgets('update banner shows for a newer release until dismissed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final updates = UpdateChecker(prefs)
      ..installed = '1.0.1'
      ..latest = const UpdateInfo('1.0.2', 'https://example.com/r', 'Notes here');
    expect(updates.showBanner, isTrue);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UpdateBanner(updates: updates)),
    ));
    expect(find.textContaining('1.0.2'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Notes here'), findsOneWidget);

    updates.dismiss();
    expect(updates.showBanner, isFalse); // same version stays hidden

    // A newer release brings the banner back.
    updates.latest = const UpdateInfo('1.0.3', 'https://example.com/r', '');
    expect(updates.showBanner, isTrue);

    // Already on the latest: nothing to show.
    updates.installed = '1.0.3';
    expect(updates.showBanner, isFalse);
  });

  test('the greeting follows the hour, including late at night', () {
    for (final h in [0, 1, 3, 5]) {
      expect(greetingFor(h), startsWith('Night owl'), reason: 'hour $h');
    }
    for (final h in [6, 9, 11]) {
      expect(greetingFor(h), 'Good morning', reason: 'hour $h');
    }
    for (final h in [12, 15, 17]) {
      expect(greetingFor(h), 'Good afternoon', reason: 'hour $h');
    }
    for (final h in [18, 21, 23]) {
      expect(greetingFor(h), 'Good evening', reason: 'hour $h');
    }
  });

  test('every slot has a placeholder and the last one is After dinner', () {
    expect(Slot.morning.hint, 'Warm water, soaked dry fruits');
    expect(Slot.breakfast.hint, 'Healthy breakfast item');
    expect(Slot.lunch.hint, 'Healthy lunch item');
    expect(Slot.snack.hint, 'Healthy snack');
    expect(Slot.dinner.hint, 'Healthy dinner item');
    expect(Slot.night.hint, 'Milk');
    expect(Slot.night.label, 'After dinner');
    for (final s in Slot.values) {
      expect(s.hint, isNotEmpty);
    }
  });

  testWidgets('the edit box shows the placeholder for the slot', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = await newStore();
    store.setProfile(Role.familyMember, 'Test', null);
    await tester.pumpWidget(App(store: store, session: Session(store)));

    // The Breakfast card on Today opens the edit box with its placeholder.
    await tester.tap(find.text('Tap to add').first);
    await tester.pumpAndSettle();
    expect(find.text('Healthy breakfast item'), findsOneWidget);
  });
}
