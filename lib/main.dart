import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
import 'notifications.dart';
import 'screens.dart';
import 'store.dart';
import 'sync.dart';
import 'updates.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore(await SharedPreferences.getInstance());

  await _safely(Sync.init);
  await _safely(Sync.setupBackground);

  final notifier = Notifier.instance;
  await _safely(notifier.init);
  await _safely(notifier.requestPermissions);

  // Reminders follow every change: menu edits, times, role, done ticks.
  store.addListener(() => notifier.reschedule(store));
  store.onMenuEdited = () => Sync.pushMenu(store);
  store.onMedicinesEdited = () => Sync.pushMedicines(store.medicines);
  notifier.onDoneChanged = store.reloadDone;

  if (store.isSetUp) {
    await _safely(() => notifier.reschedule(store));
    if (store.familyCode != null) await _safely(Sync.startBackground);
  }
  final session = Session(store)..start();
  runApp(App(
    store: store,
    session: session,
    updates: UpdateChecker(store.prefs),
  ));
}

/// Start-up steps (notifications, sync, background work) must never stop the
/// screen from appearing, so a failure is logged and skipped.
Future<void> _safely(Future<void> Function() step) async {
  try {
    await step();
  } catch (e) {
    debugPrint('Start-up step failed: $e');
  }
}

class App extends StatelessWidget {
  const App(
      {super.key, required this.store, required this.session, this.updates});
  final AppStore store;
  final Session session;

  /// Null in tests.
  final UpdateChecker? updates;

  @override
  Widget build(BuildContext context) {
    // Rebuilt when the theme is toggled from the menu.
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        title: 'Aaj Kya Banega?',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: store.themeMode,
        home: HomeShell(store: store, session: session, updates: updates),
      ),
    );
  }
}

/// Colours from the Expensely palette (default light / dark themes).
ColorScheme _scheme(Brightness b) {
  if (b == Brightness.light) {
    return ColorScheme.fromSeed(
      seedColor: const Color(0xFF374151),
      brightness: b,
    ).copyWith(
      primary: const Color(0xFF374151), // accent
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE5E7EB), // accentSoft
      onPrimaryContainer: const Color(0xFF1F2937), // accentDeep
      secondary: const Color(0xFFE58B3A), // warm
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFFBE9D7),
      onSecondaryContainer: const Color(0xFF7F5229), // expense
      tertiary: const Color(0xFF4FA58A), // good
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFDDF0E9),
      onTertiaryContainer: const Color(0xFF3A6F61), // income
      surface: const Color(0xFFF5F6F7), // tint
      onSurface: const Color(0xFF1F2937),
      onSurfaceVariant: const Color(0xFF6B7280),
      surfaceContainerLow: Colors.white, // cards (hero)
      surfaceContainerHighest: const Color(0xFFE5E7EB),
      outlineVariant: const Color(0xFFE5E7EB),
    );
  }
  return ColorScheme.fromSeed(
    seedColor: const Color(0xFFF3F4F6),
    brightness: b,
  ).copyWith(
    primary: const Color(0xFFF3F4F6), // accent
    onPrimary: const Color(0xFF17181C),
    primaryContainer: const Color(0xFF374151), // accentSoft
    onPrimaryContainer: Colors.white, // accentDeep
    secondary: const Color(0xFFE58B3A), // warm
    onSecondary: const Color(0xFF17181C),
    secondaryContainer: const Color(0xFF4A3420),
    onSecondaryContainer: const Color(0xFFD19B6B), // expense
    tertiary: const Color(0xFF68A19D), // income
    onTertiary: const Color(0xFF17181C),
    tertiaryContainer: const Color(0xFF0F766E), // good
    onTertiaryContainer: Colors.white,
    surface: const Color(0xFF17181C), // tint
    onSurface: const Color(0xFFF3F4F6),
    onSurfaceVariant: const Color(0xFF9CA3AF),
    surfaceContainerLow: const Color(0xFF1F2026),
    surfaceContainerHighest: const Color(0xFF2B2D34),
    outlineVariant: const Color(0xFF2B2D34),
  );
}

ThemeData _theme(Brightness brightness) {
  final scheme = _scheme(brightness);
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
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
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
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
  );
}
