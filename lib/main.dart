import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notifications.dart';
import 'screens.dart';
import 'store.dart';
import 'sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore(await SharedPreferences.getInstance());

  await Sync.init();
  await Sync.setupBackground();

  final notifier = Notifier.instance;
  await notifier.init();
  await notifier.requestPermissions();

  // Reminders follow every change: menu edits, times, role, done ticks.
  store.addListener(() => notifier.reschedule(store));
  store.onMenuEdited = () => Sync.pushMenu(store);
  notifier.onDoneChanged = store.reloadDone;

  if (store.isSetUp) {
    await notifier.reschedule(store);
    if (store.familyCode != null) await Sync.startBackground();
  }
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
