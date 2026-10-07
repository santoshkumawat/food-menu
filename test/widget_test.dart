import 'package:aaj_kya_banega/account.dart';
import 'package:aaj_kya_banega/main.dart';
import 'package:aaj_kya_banega/store.dart';
import 'package:aaj_kya_banega/tasks.dart';
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

  test('menu survives a save and reload', () async {
    final store = await newStore();
    store.setDish(1, Slot.snack, 'Fruit chaat');
    final again = AppStore(store.prefs);
    expect(again.dish(1, Slot.snack), 'Fruit chaat');
  });
}
