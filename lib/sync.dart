import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'notifications.dart';
import 'store.dart';

const _bgTaskName = 'menuSync';
const _timeout = Duration(seconds: 15);
const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// Entry point for the 15-minute background check.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await Sync.backgroundCheck();
    } catch (_) {
      // Try again at the next run.
    }
    return true;
  });
}

/// Shares the menu and the "done" ticks between phones through Firestore.
/// Everything still works on one phone if Firebase is not set up.
class Sync {
  static bool available = false;

  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      available = true;
    } catch (_) {
      available = false; // google-services.json missing: local-only mode.
    }
  }

  static Future<void> setupBackground() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await Workmanager().initialize(backgroundDispatcher);
  }

  static Future<void> startBackground() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await Workmanager().registerPeriodicTask(
      'menu-sync',
      _bgTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  static Future<void> stopBackground() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await Workmanager().cancelByUniqueName('menu-sync');
  }

  static DocumentReference<Map<String, dynamic>> _doc(String code) =>
      FirebaseFirestore.instance.collection('families').doc(code);

  static String _newCode() {
    final r = Random.secure();
    return List.generate(8, (_) => _codeAlphabet[r.nextInt(_codeAlphabet.length)])
        .join();
  }

  static Future<String> _deviceId(SharedPreferences p) async {
    var id = p.getString('device_id');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(36).toRadixString(36)).join();
      await p.setString('device_id', id);
    }
    return id;
  }

  // --- pairing ------------------------------------------------------------

  /// Creates a new shared family and returns its code.
  static Future<String> createFamily(AppStore s, String name) async {
    final id = await _deviceId(s.prefs);
    for (var i = 0; i < 5; i++) {
      final code = _newCode();
      final ref = _doc(code);
      if ((await ref.get().timeout(_timeout)).exists) continue;
      await ref.set({
        'menu': s.menuToJson(),
        'rev': 1,
        'editedById': id,
        'editedByName': name,
        'editedAt': DateTime.now().millisecondsSinceEpoch,
        'done': <String, dynamic>{},
      }).timeout(_timeout);
      s.setLastSeenRev(1);
      return code;
    }
    throw StateError('Could not create a family code');
  }

  /// Joins an existing family; its menu replaces the local one.
  static Future<bool> joinFamily(AppStore s, String code) async {
    final snap = await _doc(code).get().timeout(_timeout);
    if (!snap.exists) return false;
    final data = snap.data()!;
    s.applyRemoteMenu(data['menu'] as String, data['rev'] as int? ?? 1);
    await _mergeDone(s.prefs, data['done']);
    await s.reloadDone();
    return true;
  }

  // --- pushing changes ----------------------------------------------------

  static Future<void> pushMenu(AppStore s) async {
    final code = s.familyCode;
    if (!available || code == null) return;
    final id = await _deviceId(s.prefs);
    try {
      await _doc(code).set({
        'menu': s.menuToJson(),
        'rev': FieldValue.increment(1),
        'editedById': id,
        'editedByName': s.myName,
        'editedAt': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true)).timeout(_timeout);
    } catch (_) {
      // Offline: Firestore keeps the write queued and sends it later.
    }
  }

  /// Marks `20261007_cook` etc. as done for the whole family.
  static Future<void> pushDone(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final code = _familyCodeFrom(prefs);
      if (code == null) return;
      await init();
      if (!available) return;
      await _doc(code)
          .set({'done': {key: true}}, SetOptions(merge: true)).timeout(_timeout);
    } catch (_) {}
  }

  static String? _familyCodeFrom(SharedPreferences p) {
    final raw = p.getString('store_v1');
    if (raw == null) return null;
    return (jsonDecode(raw) as Map<String, dynamic>)['family'] as String?;
  }

  // --- receiving changes --------------------------------------------------

  static Future<void> _mergeDone(SharedPreferences p, dynamic done) async {
    if (done is! Map) return;
    for (final k in done.keys) {
      await DoneLog.add(p, k as String);
    }
  }

  /// Applies a remote snapshot. Returns a summary of what the other person
  /// changed, or null if nothing new came from someone else.
  static Future<({String who, String summary})?> _apply(
      AppStore s, Map<String, dynamic> data) async {
    await _mergeDone(s.prefs, data['done']);
    await s.reloadDone();

    final rev = data['rev'] as int? ?? 0;
    if (rev <= s.lastSeenRev) return null;
    final mine = data['editedById'] == await _deviceId(s.prefs);
    if (mine) {
      s.setLastSeenRev(rev);
      return null;
    }
    final before = {
      for (final e in s.menu.entries) e.key: Map<Slot, String>.of(e.value)
    };
    s.applyRemoteMenu(data['menu'] as String, rev);
    final who = (data['editedByName'] as String?)?.trim();
    return (
      who: (who == null || who.isEmpty) ? 'The other phone' : who,
      summary: _diff(before, s.menu),
    );
  }

  static String _diff(
      Map<int, Map<Slot, String>> a, Map<int, Map<Slot, String>> b) {
    final changes = <String>[];
    for (var day = 1; day <= 7; day++) {
      for (final slot in Slot.values) {
        final x = a[day]![slot] ?? '', y = b[day]![slot] ?? '';
        if (x != y) {
          changes.add('${dayNames[day - 1].substring(0, 3)} ${slot.label}: '
              '${y.isEmpty ? 'cleared' : y}');
        }
      }
    }
    if (changes.isEmpty) return 'Menu updated';
    final shown = changes.take(3).join('\n');
    return changes.length > 3 ? '$shown\n+${changes.length - 3} more' : shown;
  }

  /// Live updates while the app is open.
  static StreamSubscription<void>? listen(
      AppStore s, void Function(String who, String summary) onRemoteEdit) {
    final code = s.familyCode;
    if (!available || code == null) return null;
    return _doc(code).snapshots().listen((snap) async {
      final data = snap.data();
      if (data == null) return;
      final change = await _apply(s, data);
      if (change != null) onRemoteEdit(change.who, change.summary);
    }, onError: (_) {});
  }

  /// Runs in the background every ~15 minutes.
  static Future<void> backgroundCheck() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final store = AppStore(prefs);
    if (!store.isSetUp) return;
    await Notifier.instance.init();

    final code = store.familyCode;
    if (code != null) {
      await init();
      if (available) {
        final snap = await _doc(code).get().timeout(_timeout);
        final data = snap.data();
        if (data != null) {
          final change = await _apply(store, data);
          if (change != null) {
            await Notifier.instance.showNow(
              'Menu updated by ${change.who}',
              change.summary,
              id: 998,
            );
          }
        }
      }
    }
    // Keeps the 7-day window of reminders full and in line with the menu.
    await Notifier.instance.reschedule(store);
  }
}
