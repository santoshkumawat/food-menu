import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'notifications.dart';
import 'store.dart';
import 'tasks.dart';

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

class Member {
  const Member(this.uid, this.name, this.role, this.admin);
  final String uid;
  final String name;
  final Role role;
  final bool admin;
}

class JoinRequest {
  const JoinRequest(this.uid, this.name, this.role);
  final String uid;
  final String name;
  final Role role;
}

enum JoinResult { notFound, alreadyMember, pending }

enum Decision { approved, declined }

/// A set of live listeners that can be switched off together.
class SyncSession {
  final _subs = <StreamSubscription<void>>[];
  bool cancelled = false;

  void add(StreamSubscription<void> s) {
    if (cancelled) {
      s.cancel();
    } else {
      _subs.add(s);
    }
  }

  void cancel() {
    cancelled = true;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}

Role _role(Object? v) => Role.values.asNameMap()[v] ?? Role.me;

/// Shares the menu and the "done" ticks between phones through Firestore.
///
/// Data layout:
///   families/{code}                  adminUid, adminName, members{uid: {...}}
///   families/{code}/requests/{uid}   people waiting for the admin's approval
///   families/{code}/shared/state     menu, rev, done flags (members only)
/// Everything still works on one phone if Firebase is not set up.
class Sync {
  static bool available = false;

  /// Live copies for the UI.
  static final members = ValueNotifier<List<Member>>([]);
  static final requests = ValueNotifier<List<JoinRequest>>([]);

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

  // --- helpers ------------------------------------------------------------

  static DocumentReference<Map<String, dynamic>> _family(String code) =>
      FirebaseFirestore.instance.collection('families').doc(code);

  static DocumentReference<Map<String, dynamic>> _shared(String code) =>
      _family(code).collection('shared').doc('state');

  static CollectionReference<Map<String, dynamic>> _requests(String code) =>
      _family(code).collection('requests');

  /// Signs in anonymously the first time; the account id then stays on the
  /// phone and identifies it to the server.
  static Future<String> _uid() async {
    final auth = FirebaseAuth.instance;
    final user =
        auth.currentUser ?? (await auth.signInAnonymously().timeout(_timeout)).user;
    return user!.uid;
  }

  static String _newCode() {
    final r = Random.secure();
    return List.generate(8, (_) => _codeAlphabet[r.nextInt(_codeAlphabet.length)])
        .join();
  }

  static List<Member> _parseMembers(Map<String, dynamic> data) {
    final raw = (data['members'] as Map?) ?? {};
    final list = [
      for (final e in raw.entries)
        Member(
          e.key as String,
          ((e.value as Map)['name'] ?? '') as String,
          _role((e.value as Map)['role']),
          (e.value as Map)['admin'] == true,
        ),
    ];
    list.sort((a, b) => a.admin == b.admin
        ? a.name.compareTo(b.name)
        : (a.admin ? -1 : 1));
    return list;
  }

  // --- creating and joining -----------------------------------------------

  /// Creates a family with this phone as admin and returns its code.
  static Future<String> createFamily(AppStore s, String name, Role role) async {
    final uid = await _uid();
    for (var i = 0; i < 5; i++) {
      final code = _newCode();
      if ((await _family(code).get().timeout(_timeout)).exists) continue;
      await _family(code).set({
        'adminUid': uid,
        'adminName': name,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'members': {
          uid: {'name': name, 'role': role.name, 'admin': true},
        },
      }).timeout(_timeout);
      await _shared(code).set({
        'menu': s.menuToJson(),
        'rev': 1,
        'editedById': uid,
        'editedByName': name,
        'editedAt': DateTime.now().millisecondsSinceEpoch,
        'done': <String, dynamic>{},
      }).timeout(_timeout);
      s.setLastSeenRev(1);
      return code;
    }
    throw StateError('Could not create a family code');
  }

  /// Asks the admin to let this phone in. Safe to call again while waiting.
  static Future<({JoinResult result, String? adminName})> requestJoin(
      String code, String name, Role role) async {
    final uid = await _uid();
    final snap = await _family(code).get().timeout(_timeout);
    if (!snap.exists) return (result: JoinResult.notFound, adminName: null);
    final data = snap.data()!;
    final adminName = data['adminName'] as String?;
    if (_parseMembers(data).any((m) => m.uid == uid)) {
      return (result: JoinResult.alreadyMember, adminName: adminName);
    }
    await _requests(code)
        .doc(uid)
        .set({'name': name, 'role': role.name, 'at': DateTime.now().millisecondsSinceEpoch})
        .timeout(_timeout);
    return (result: JoinResult.pending, adminName: adminName);
  }

  /// Emits once the admin approves or declines this phone's request.
  static Stream<Decision> watchDecision(String code) {
    final controller = StreamController<Decision>();
    StreamSubscription<void>? a, b;
    controller.onListen = () async {
      try {
        final uid = await _uid();
        var requestSeen = false;
        a = _family(code).snapshots().listen((snap) {
          final data = snap.data();
          if (data != null && _parseMembers(data).any((m) => m.uid == uid)) {
            controller.add(Decision.approved);
          }
        }, onError: (_) {});
        b = _requests(code).doc(uid).snapshots().listen((snap) async {
          if (snap.exists) {
            requestSeen = true;
          } else if (requestSeen) {
            // Deleted: either approved (now a member) or declined.
            final fam = await _family(code).get();
            final isMember = fam.data() != null &&
                _parseMembers(fam.data()!).any((m) => m.uid == uid);
            controller.add(isMember ? Decision.approved : Decision.declined);
          }
        }, onError: (_) {});
      } catch (_) {
        controller.addError('offline');
      }
    };
    controller.onCancel = () {
      a?.cancel();
      b?.cancel();
    };
    return controller.stream;
  }

  static Future<void> cancelRequest(String code) async {
    try {
      await _requests(code).doc(await _uid()).delete().timeout(_timeout);
    } catch (_) {}
  }

  /// After approval: copy the shared menu onto this phone.
  static Future<void> loadShared(AppStore s, String code) async {
    final snap = await _shared(code).get().timeout(_timeout);
    final data = snap.data();
    if (data == null) return;
    s.applyRemoteMenu(data['menu'] as String, data['rev'] as int? ?? 1);
    await _mergeDone(s.prefs, data['done']);
    await s.reloadDone();
  }

  // --- admin actions ------------------------------------------------------

  static Future<void> approve(String code, JoinRequest r) async {
    final batch = FirebaseFirestore.instance.batch();
    batch.update(_family(code), {
      'members.${r.uid}': {'name': r.name, 'role': r.role.name, 'admin': false},
    });
    batch.delete(_requests(code).doc(r.uid));
    await batch.commit();
  }

  static Future<void> decline(String code, JoinRequest r) =>
      _requests(code).doc(r.uid).delete();

  static Future<void> removeMember(String code, String uid) =>
      _family(code).update({'members.$uid': FieldValue.delete()});

  // --- pushing changes ----------------------------------------------------

  static Future<void> pushMenu(AppStore s) async {
    final code = s.familyCode;
    if (!available || code == null) return;
    try {
      final uid = await _uid();
      await _shared(code).set({
        'menu': s.menuToJson(),
        'rev': FieldValue.increment(1),
        'editedById': uid,
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
      await _uid();
      await _shared(code)
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

  /// Applies the shared state. Returns a summary of what someone else
  /// changed, or null if nothing new came from another phone.
  static Future<({String who, String summary})?> _apply(
      AppStore s, Map<String, dynamic> data) async {
    await _mergeDone(s.prefs, data['done']);
    await s.reloadDone();

    final rev = data['rev'] as int? ?? 0;
    if (rev <= s.lastSeenRev) return null;
    final mine = data['editedById'] == FirebaseAuth.instance.currentUser?.uid;
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
      who: (who == null || who.isEmpty) ? 'Someone' : who,
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
  static SyncSession? listen(
    AppStore s, {
    required void Function(String who, String summary) onRemoteEdit,
    required void Function(String name) onJoinRequest,
    required VoidCallback onRemoved,
  }) {
    final code = s.familyCode;
    if (!available || code == null) return null;
    final session = SyncSession();
    () async {
      try {
        final uid = await _uid();
        if (session.cancelled) return;

        session.add(_family(code).snapshots().listen((snap) {
          final data = snap.data();
          if (data == null) return;
          final list = _parseMembers(data);
          members.value = list;
          if (!snap.metadata.isFromCache && !list.any((m) => m.uid == uid)) {
            onRemoved();
          }
        }, onError: (_) {}));

        session.add(_shared(code).snapshots().listen((snap) async {
          final data = snap.data();
          if (data == null) return;
          final change = await _apply(s, data);
          if (change != null) onRemoteEdit(change.who, change.summary);
        }, onError: (_) {}));

        if (s.isAdmin) {
          session.add(_requests(code).snapshots().listen((qs) {
            final list = [
              for (final d in qs.docs)
                JoinRequest(d.id, (d.data()['name'] ?? '') as String,
                    _role(d.data()['role'])),
            ];
            final known = requests.value.map((r) => r.uid).toSet();
            requests.value = list;
            for (final r in list.where((r) => !known.contains(r.uid))) {
              onJoinRequest(r.name);
            }
          }, onError: (_) {}));
        }
      } catch (_) {}
    }();
    return session;
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
        final uid = await _uid();
        final fam = (await _family(code).get().timeout(_timeout)).data();
        if (fam != null && !_parseMembers(fam).any((m) => m.uid == uid)) {
          // The admin removed this phone from the family.
          store.resetProfile();
          await stopBackground();
          await Notifier.instance.showNow('Removed from family',
              'The admin removed you. Open the app to join again.',
              id: 996);
          return;
        }

        final data = (await _shared(code).get().timeout(_timeout)).data();
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

        if (store.isAdmin) await _notifyNewRequests(prefs, code);
      }
    }
    // Keeps the 7-day window of reminders full and in line with the menu.
    await Notifier.instance.reschedule(store);
  }

  static Future<void> _notifyNewRequests(
      SharedPreferences prefs, String code) async {
    final seen = (prefs.getStringList('notified_requests') ?? []).toSet();
    final qs = await _requests(code).get().timeout(_timeout);
    final current = qs.docs.map((d) => d.id).toSet();
    var n = 0;
    for (final d in qs.docs) {
      if (seen.contains(d.id)) continue;
      await Notifier.instance.showNow(
        'Join request',
        '${d.data()['name'] ?? 'Someone'} wants to join your family.',
        id: 900 + n++,
      );
    }
    await prefs.setStringList('notified_requests', current.toList());
  }
}
