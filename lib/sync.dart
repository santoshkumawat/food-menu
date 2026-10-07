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
  const Member(this.uid, this.name, this.username, this.role, this.admin);
  final String uid;
  final String name;
  final String username;
  final Role role;
  final bool admin;
}

/// An invitation waiting for the person it is addressed to.
class Invite {
  const Invite(this.key, this.code, this.familyName, this.role, this.invitedBy);
  final String key; // lower-case email or username it was sent to
  final String code; // family code
  final String familyName;
  final Role role;
  final String invitedBy;
}

/// An invitation as the admin sees it.
class PendingInvite {
  const PendingInvite(this.key, this.role);
  final String key;
  final Role role;
}

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

Role _role(Object? v) => Role.values.asNameMap()[v] ?? Role.familyMember;

bool isEmail(String s) => s.contains('@');

/// Lower-case form used as the document id for invites.
String inviteKey(String input) => input.trim().toLowerCase();

/// Shares the menu and the "done" ticks between family members.
///
/// Data layout (see FIREBASE_SETUP.md for the security rules):
///   users/{uid}                       username, name, email, familyCode
///   usernames/{username}              uid  (keeps usernames unique)
///   families/{code}                   name, adminUid, members{uid: {...}}
///   families/{code}/invites/{key}     invites the admin has sent
///   families/{code}/shared/state      menu, rev, done flags (members only)
///   inboxes/{key}/invites/{code}      the invite as the invited person sees it
/// Everything still works on one phone if Firebase is not set up.
class Sync {
  static bool available = false;

  /// Live copies for the UI.
  static final members = ValueNotifier<List<Member>>([]);
  static final pendingInvites = ValueNotifier<List<PendingInvite>>([]);

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

  // --- references ---------------------------------------------------------

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);

  static DocumentReference<Map<String, dynamic>> _family(String code) =>
      _db.collection('families').doc(code);

  static DocumentReference<Map<String, dynamic>> _shared(String code) =>
      _family(code).collection('shared').doc('state');

  static DocumentReference<Map<String, dynamic>> _sentInvite(
          String code, String key) =>
      _family(code).collection('invites').doc(key);

  static CollectionReference<Map<String, dynamic>> _inbox(String key) =>
      _db.collection('inboxes').doc(key).collection('invites');

  static String get _myUid => FirebaseAuth.instance.currentUser!.uid;

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
          ((e.value as Map)['username'] ?? '') as String,
          _role((e.value as Map)['role']),
          (e.value as Map)['admin'] == true,
        ),
    ];
    list.sort((a, b) => a.admin == b.admin
        ? a.name.compareTo(b.name)
        : (a.admin ? -1 : 1));
    return list;
  }

  // --- family lifecycle ---------------------------------------------------

  /// Creates a family with this account as admin and returns its code.
  static Future<String> createFamily(
    AppStore s, {
    required String familyName,
    required String name,
    required String username,
    required Role role,
  }) async {
    final uid = _myUid;
    for (var i = 0; i < 5; i++) {
      final code = _newCode();
      try {
        if ((await _family(code).get().timeout(_timeout)).exists) continue;
      } on FirebaseException catch (e) {
        // Someone else's family: the rules deny the read. Try another code.
        if (e.code == 'permission-denied') continue;
        rethrow;
      }
      await _family(code).set({
        'name': familyName,
        'adminUid': uid,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'members': {
          uid: {
            'name': name,
            'username': username,
            'role': role.name,
            'admin': true,
          },
        },
      }).timeout(_timeout);
      await _shared(code).set({
        ...s.sharedFields(),
        'rev': 1,
        'editedById': uid,
        'editedByName': name,
        'editedAt': DateTime.now().millisecondsSinceEpoch,
        'done': <String, dynamic>{},
      }).timeout(_timeout);
      await _user(uid)
          .set({'familyCode': code}, SetOptions(merge: true)).timeout(_timeout);
      s.setLastSeenRev(1);
      return code;
    }
    throw StateError('Could not create a family code');
  }

  /// Accepts an invitation and joins the family.
  static Future<void> acceptInvite(
      Invite inv, String name, String username) async {
    final uid = _myUid;
    await _family(inv.code).update({
      'members.$uid': {
        'name': name,
        'username': username,
        'role': inv.role.name,
        'admin': false,
      },
    }).timeout(_timeout);
    await _user(uid)
        .set({'familyCode': inv.code}, SetOptions(merge: true)).timeout(_timeout);
    try {
      await _inbox(inv.key).doc(inv.code).delete();
    } catch (_) {}
  }

  /// Copies the family's shared data onto this phone (used right after
  /// joining, so the new member sees everything immediately).
  static Future<void> loadShared(AppStore s, String code) async {
    final data = (await _shared(code).get().timeout(_timeout)).data();
    if (data == null) return;
    s.applyRemoteMenu(
      data['menu'] as String,
      data['rev'] as int? ?? 1,
      guidelines: _strings(data['guidelines']),
    );
    await _mergeDone(s.prefs, data['done']);
    await s.reloadDone();
  }

  /// Saves this person's private medicine list on their own account.
  static Future<void> pushMedicines(List<String> list) async {
    if (!available || FirebaseAuth.instance.currentUser == null) return;
    try {
      await _user(_myUid)
          .set({'medicines': list}, SetOptions(merge: true)).timeout(_timeout);
    } catch (_) {
      // Offline: Firestore keeps the write queued and sends it later.
    }
  }

  static List<String>? _strings(Object? v) =>
      v is List ? [for (final e in v) '$e'] : null;

  static Future<void> declineInvite(Invite inv) =>
      _inbox(inv.key).doc(inv.code).delete();

  /// Leaves the family (members only; the admin cannot leave).
  static Future<void> leaveFamily(String code) async {
    final uid = _myUid;
    await _family(code)
        .update({'members.$uid': FieldValue.delete()}).timeout(_timeout);
    await _user(uid)
        .set({'familyCode': FieldValue.delete()}, SetOptions(merge: true));
  }

  /// Clears the family link on the account (e.g. after being removed).
  static Future<void> clearFamilyLink() async {
    try {
      await _user(_myUid)
          .set({'familyCode': FieldValue.delete()}, SetOptions(merge: true));
    } catch (_) {}
  }

  // --- invitations --------------------------------------------------------

  /// Invitations addressed to any of [keys] (the account's email/username).
  static Stream<List<Invite>> watchInvites(List<String> keys) {
    final controller = StreamController<List<Invite>>();
    final latest = <String, List<Invite>>{};
    final subs = <StreamSubscription<void>>[];
    controller.onListen = () {
      for (final key in keys) {
        subs.add(_inbox(key).snapshots().listen((qs) {
          latest[key] = [
            for (final d in qs.docs)
              Invite(
                key,
                d.id,
                (d.data()['familyName'] ?? 'A family') as String,
                _role(d.data()['role']),
                (d.data()['invitedBy'] ?? '') as String,
              ),
          ];
          controller.add([for (final l in latest.values) ...l]);
        }, onError: (_) {}));
      }
    };
    controller.onCancel = () {
      for (final s in subs) {
        s.cancel();
      }
    };
    return controller.stream;
  }

  /// Admin: invites an email address or a username with a role.
  /// Throws [StateError] with a user-readable message on bad input.
  static Future<String> invite({
    required String code,
    required String familyName,
    required String input,
    required Role role,
    required String invitedBy,
  }) async {
    final key = inviteKey(input);
    if (key.isEmpty) throw StateError('Enter an email or username');
    if (isEmail(key)) {
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(key)) {
        throw StateError('That email address looks wrong');
      }
    } else if ((await _db.collection('usernames').doc(key).get()).exists ==
        false) {
      throw StateError('No user with the username "$key"');
    }
    if (members.value.any((m) => m.username == key)) {
      throw StateError('That person is already in the family');
    }
    final batch = _db.batch();
    final at = DateTime.now().millisecondsSinceEpoch;
    batch.set(_inbox(key).doc(code), {
      'familyName': familyName,
      'role': role.name,
      'invitedBy': invitedBy,
      'at': at,
    });
    batch.set(_sentInvite(code, key), {'role': role.name, 'at': at});
    await batch.commit();
    return key;
  }

  static Future<void> cancelInvite(String code, String key) async {
    final batch = _db.batch();
    batch.delete(_inbox(key).doc(code));
    batch.delete(_sentInvite(code, key));
    await batch.commit();
  }

  static Future<void> changeRole(String code, String uid, Role role) =>
      _family(code).update({'members.$uid.role': role.name});

  static Future<void> removeMember(String code, String uid) =>
      _family(code).update({'members.$uid': FieldValue.delete()});

  // --- pushing changes ----------------------------------------------------

  static Future<void> pushMenu(AppStore s) async {
    final code = s.familyCode;
    if (!available || code == null) return;
    try {
      await _shared(code).set({
        ...s.sharedFields(),
        'medicines': FieldValue.delete(), // medicines are personal now
        'rev': FieldValue.increment(1),
        'editedById': _myUid,
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
      if (!available || FirebaseAuth.instance.currentUser == null) return;
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
    final oldGuidelines = [...s.guidelines];
    s.applyRemoteMenu(
      data['menu'] as String,
      rev,
      guidelines: _strings(data['guidelines']),
    );
    final who = (data['editedByName'] as String?)?.trim();
    return (
      who: (who == null || who.isEmpty) ? 'Someone' : who,
      summary: _summary(before, s.menu,
          guidelinesChanged: !listEquals(oldGuidelines, s.guidelines)),
    );
  }

  static String _summary(
    Map<int, Map<Slot, String>> a,
    Map<int, Map<Slot, String>> b, {
    required bool guidelinesChanged,
  }) {
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
    final shown = changes.take(3).toList();
    if (changes.length > 3) shown.add('+${changes.length - 3} more');
    if (guidelinesChanged) shown.add('Guidelines updated');
    return shown.isEmpty ? 'Family data updated' : shown.join('\n');
  }

  /// Copies this account's member entry (role, name, admin) onto the phone.
  static void _syncMembership(
      AppStore s, Map<String, dynamic> family, List<Member> list) {
    final me = list.where((m) => m.uid == FirebaseAuth.instance.currentUser?.uid);
    if (me.isEmpty) return;
    s.syncMembership(
      me.first.role,
      me.first.name,
      me.first.admin,
      (family['name'] ?? '') as String,
    );
  }

  /// Live updates while the app is open.
  static SyncSession? listen(
    AppStore s, {
    required void Function(String who, String summary) onRemoteEdit,
    required VoidCallback onRemoved,
  }) {
    final code = s.familyCode;
    if (!available || code == null || FirebaseAuth.instance.currentUser == null) {
      return null;
    }
    final session = SyncSession();
    final uid = _myUid;

    session.add(_family(code).snapshots().listen((snap) {
      final data = snap.data();
      if (data == null) return;
      final list = _parseMembers(data);
      members.value = list;
      if (!snap.metadata.isFromCache && !list.any((m) => m.uid == uid)) {
        onRemoved();
      } else {
        _syncMembership(s, data, list);
      }
    }, onError: (_) {}));

    session.add(_shared(code).snapshots().listen((snap) async {
      final data = snap.data();
      if (data == null) return;
      final change = await _apply(s, data);
      if (change != null) onRemoteEdit(change.who, change.summary);
    }, onError: (_) {}));

    if (s.isAdmin) {
      session.add(_family(code).collection('invites').snapshots().listen(
        (qs) async {
          // An invite is still pending only while the invited person's copy
          // exists. When they accept or decline, that copy is deleted, so the
          // admin's copy is stale: remove it and leave it out of the list.
          final pending = <PendingInvite>[];
          for (final d in qs.docs) {
            var open = true; // offline: keep showing it
            try {
              open = (await _inbox(d.id).doc(code).get()).exists;
            } catch (_) {}
            if (open) {
              pending.add(PendingInvite(d.id, _role(d.data()['role'])));
            } else {
              try {
                await d.reference.delete();
              } catch (_) {}
            }
          }
          pendingInvites.value = pending;
        },
        onError: (_) {},
      ));
    }
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
      if (available && FirebaseAuth.instance.currentUser != null) {
        final uid = _myUid;
        final fam = (await _family(code).get().timeout(_timeout)).data();
        if (fam != null) {
          final list = _parseMembers(fam);
          if (!list.any((m) => m.uid == uid)) {
            // The admin removed this account from the family.
            store.resetProfile();
            await clearFamilyLink();
            await stopBackground();
            await Notifier.instance.showNow('Removed from family',
                'The admin removed you. Open the app to continue.',
                id: 996);
            return;
          }
          _syncMembership(store, fam, list);
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
      }
    }
    // Keeps the 7-day window of reminders full and in line with the menu.
    await Notifier.instance.reschedule(store);
  }
}
