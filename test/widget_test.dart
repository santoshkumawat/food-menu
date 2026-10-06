import 'package:aaj_kya_banega/main.dart';
import 'package:aaj_kya_banega/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows app title and today tab', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(await SharedPreferences.getInstance());
    await tester.pumpWidget(App(store: store));
    expect(find.text('Aaj Kya Banega?'), findsOneWidget);
    expect(find.textContaining('Breakfast'), findsWidgets);
  });
}
