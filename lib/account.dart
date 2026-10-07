import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'store.dart';
import 'sync.dart';
import 'tasks.dart';

enum AuthState {
  loading,
  offline,
  signedOut,
  unverified,
  needsProfile,
  noFamily,
  ready,
}

/// Where the signed-in account stands: verified? profile? in a family?
class Session extends ChangeNotifier {
  Session(this.store);
  final AppStore store;

  AuthState state = AuthState.loading;
  String email = '';
  String username = '';
  String name = '';

  StreamSubscription<User?>? _sub;
  int _run = 0;

  static final _usernameRule = RegExp(r'^[a-z0-9_]{3,20}$');

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  void start() {
    if (!Sync.available) return;
    _sub = _auth.userChanges().listen(_evaluate);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _set(AuthState s) {
    state = s;
    notifyListeners();
  }

  /// Works out which screen the account should see.
  Future<void> _evaluate(User? user) async {
    final run = ++_run;
    if (user == null) {
      if (store.isSetUp) store.resetProfile();
      email = username = name = '';
      return _set(AuthState.signedOut);
    }
    email = user.email ?? '';
    if (!user.emailVerified) return _set(AuthState.unverified);

    try {
      final snap = await _db.collection('users').doc(user.uid).get();
      if (run != _run) return;
      final data = snap.data();
      if (data == null) return _set(AuthState.needsProfile);
      username = (data['username'] ?? '') as String;
      name = (data['name'] ?? '') as String;

      final code = data['familyCode'] as String?;
      if (code != null) {
        final fam = (await _db.collection('families').doc(code).get()).data();
        if (run != _run) return;
        final me = (fam?['members'] as Map?)?[user.uid] as Map?;
        if (me != null) {
          store.setProfile(
            Role.values.asNameMap()[me['role']] ?? Role.me,
            (me['name'] ?? name) as String,
            code,
            admin: me['admin'] == true,
            family: (fam?['name'] ?? '') as String,
          );
          await Sync.startBackground();
          return _set(AuthState.ready);
        }
        await Sync.clearFamilyLink(); // removed from the family meanwhile
      }
      if (store.isSetUp) store.resetProfile();
      _set(AuthState.noFamily);
    } catch (_) {
      if (run != _run) return;
      // No internet: keep working from what is saved on the phone.
      _set(store.isSetUp && store.familyCode != null
          ? AuthState.ready
          : AuthState.offline);
    }
  }

  Future<void> retry() => _evaluate(_auth.currentUser);

  // --- account actions ----------------------------------------------------

  Future<void> signIn(String email, String password) => _auth
      .signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> signUp(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    await cred.user?.sendEmailVerification();
  }

  Future<void> resendVerification() async =>
      _auth.currentUser?.sendEmailVerification();

  /// After the person taps the link in the email.
  Future<void> refresh() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.reload();
    await _auth.currentUser?.getIdToken(true); // so the server sees the verification
    await _evaluate(_auth.currentUser);
  }

  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() async {
    await Sync.stopBackground();
    store.resetProfile();
    await _auth.signOut();
  }

  /// Picks a unique username and display name. Throws [StateError] with a
  /// readable message when the username is invalid or taken.
  Future<void> createProfile(String username, String displayName) async {
    final u = username.trim().toLowerCase();
    if (!_usernameRule.hasMatch(u)) {
      throw StateError(
          'Username must be 3-20 letters, numbers or underscores');
    }
    if (displayName.trim().isEmpty) {
      throw StateError('Enter your name');
    }
    final user = _auth.currentUser!;
    final batch = _db.batch();
    batch.set(_db.collection('usernames').doc(u), {'uid': user.uid});
    batch.set(_db.collection('users').doc(user.uid), {
      'username': u,
      'name': displayName.trim(),
      'email': (user.email ?? '').toLowerCase(),
    });
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw StateError('That username is already taken');
      }
      rethrow;
    }
    await _evaluate(user);
  }

  Future<void> createFamily(String familyName, Role role) async {
    if (familyName.trim().isEmpty) throw StateError('Enter a family name');
    final code = await Sync.createFamily(
      store,
      familyName: familyName.trim(),
      name: name,
      username: username,
      role: role,
    );
    store.setProfile(role, name, code, admin: true, family: familyName.trim());
    await Sync.startBackground();
    _set(AuthState.ready);
  }

  Future<void> acceptInvite(Invite inv) async {
    await Sync.acceptInvite(inv, name, username);
    await _evaluate(_auth.currentUser);
  }

  /// Leave the family (non-admins).
  Future<void> leaveFamily() async {
    final code = store.familyCode;
    if (code == null) return;
    await Sync.leaveFamily(code);
    await Sync.stopBackground();
    store.resetProfile();
    _set(AuthState.noFamily);
  }

  /// Keys that invitations for this account can be addressed to.
  List<String> get inviteKeys => [
        if (email.isNotEmpty) email.toLowerCase(),
        if (username.isNotEmpty) username,
      ];
}

/// Turns Firebase and app errors into short messages for the screen.
String errorMessage(Object e) {
  if (e is StateError) return e.message;
  final raw = e.toString();
  if (raw.contains('CONFIGURATION_NOT_FOUND') ||
      (e is FirebaseAuthException && e.code == 'operation-not-allowed')) {
    return 'Sign-in is not turned on in Firebase yet. In the Firebase console '
        'open Build > Authentication > Get started, then Sign-in method > '
        'Email/Password > Enable.';
  }
  if (e is FirebaseAuthException) {
    return switch (e.code) {
      'invalid-email' => 'That email address looks wrong.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' =>
        'Email or password is incorrect.',
      'email-already-in-use' => 'An account with this email already exists.',
      'weak-password' => 'Choose a longer password (at least 6 characters).',
      'too-many-requests' => 'Too many attempts. Try again in a few minutes.',
      'network-request-failed' => 'No internet connection.',
      _ => 'Sign-in failed (${e.code}): ${_short(e.message)}',
    };
  }
  if (e is FirebaseException && e.code == 'permission-denied') {
    return 'Not allowed. Check the Firestore rules in FIREBASE_SETUP.md.';
  }
  if (e is FirebaseException) {
    return 'Server error (${e.code}): ${_short(e.message)}';
  }
  return 'Something went wrong: ${_short(raw)}';
}

String _short(String? s) {
  final t = (s ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length > 140 ? '${t.substring(0, 140)}...' : t;
}
