import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
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
  final session = Session(store)..start();
  runApp(App(store: store, session: session));
}

class App extends StatelessWidget {
  const App({super.key, required this.store, required this.session});
  final AppStore store;
  final Session session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aaj Kya Banega?',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: HomeShell(store: store, session: session),
    );
  }
}

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFE64A19),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
  );
}
