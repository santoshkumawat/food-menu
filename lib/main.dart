import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notifications.dart';
import 'screens.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore(await SharedPreferences.getInstance());
  final notifier = Notifier.instance;
  await notifier.init();
  await notifier.requestPermissions();
  await notifier.reschedule(store);
  // Keep reminders in sync with any edit.
  store.addListener(() => notifier.reschedule(store));
  runApp(App(store: store));
}

class App extends StatelessWidget {
  const App({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aaj Kya Banega?',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepOrange,
        useMaterial3: true,
      ),
      home: HomeShell(store: store),
    );
  }
}
