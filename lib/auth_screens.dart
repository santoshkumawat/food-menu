import 'package:flutter/material.dart';

import 'account.dart';
import 'sync.dart';
import 'tasks.dart';

/// Busy flag and error text shared by the screens below.
mixin BusyState<T extends StatefulWidget> on State<T> {
  bool busy = false;
  String? error;

  Future<void> run(Future<void> Function() job) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget status(BuildContext context) => Column(
        children: [
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      );
}

Widget _page(BuildContext context, String title, List<Widget> children,
    {List<Widget>? actions}) {
  return Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(padding: const EdgeInsets.all(20), children: children),
      ),
    ),
  );
}

Widget _signOutButton(Session session) => TextButton(
      onPressed: session.signOut,
      child: const Text('Sign out'),
    );

// --- sign in / sign up ------------------------------------------------------

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.session});
  final Session session;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with BusyState {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _hide = true;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() => run(() async {
        _info = null;
        if (_signUp) {
          await widget.session.signUp(_email.text, _password.text);
        } else {
          await widget.session.signIn(_email.text, _password.text);
        }
      });

  Future<void> _forgot() => run(() async {
        if (_email.text.trim().isEmpty) {
          throw StateError('Enter your email above first');
        }
        await widget.session.resetPassword(_email.text);
        setState(() => _info = 'Password reset email sent to ${_email.text.trim()}');
      });

  @override
  Widget build(BuildContext context) {
    return _page(context, 'Aaj Kya Banega?', [
      const SizedBox(height: 8),
      Text(_signUp ? 'Create your account' : 'Sign in',
          style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(
            labelText: 'Email', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        obscureText: _hide,
        autofillHints: [
          _signUp ? AutofillHints.newPassword : AutofillHints.password
        ],
        decoration: InputDecoration(
          labelText: 'Password',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _hide = !_hide),
          ),
        ),
        onSubmitted: (_) => busy ? null : _submit(),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: busy ? null : _submit,
        child: Text(_signUp ? 'Create account' : 'Sign in'),
      ),
      if (!_signUp)
        TextButton(
            onPressed: busy ? null : _forgot,
            child: const Text('Forgot password?')),
      TextButton(
        onPressed: busy
            ? null
            : () => setState(() {
                  _signUp = !_signUp;
                  error = null;
                }),
        child: Text(_signUp
            ? 'I already have an account'
            : 'New here? Create an account'),
      ),
      if (_info != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_info!),
        ),
      status(context),
    ]);
  }
}

// --- email verification -----------------------------------------------------

class VerifyPage extends StatefulWidget {
  const VerifyPage({super.key, required this.session});
  final Session session;

  @override
  State<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<VerifyPage> with BusyState {
  String? _info;

  @override
  Widget build(BuildContext context) {
    return _page(
      context,
      'Verify your email',
      [
        const Icon(Icons.mark_email_unread_outlined, size: 56),
        const SizedBox(height: 16),
        Text('We sent a link to ${widget.session.email}.',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
            'Open it, then come back and tap the button. Verifying keeps '
            'invitations to your email address safe. Check the spam folder too.'),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy ? null : () => run(widget.session.refresh),
          child: const Text("I've verified my email"),
        ),
        TextButton(
          onPressed: busy
              ? null
              : () => run(() async {
                    await widget.session.resendVerification();
                    setState(() => _info = 'Verification email sent again');
                  }),
          child: const Text('Send the email again'),
        ),
        if (_info != null) Text(_info!),
        status(context),
      ],
      actions: [_signOutButton(widget.session)],
    );
  }
}

// --- username and name ------------------------------------------------------

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.session});
  final Session session;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with BusyState {
  final _name = TextEditingController();
  final _username = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _page(
      context,
      'Set up your profile',
      [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              labelText: 'Your name', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _username,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Username',
            helperText: 'Letters, numbers, underscore. Others can invite you with it.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy
              ? null
              : () => run(() =>
                  widget.session.createProfile(_username.text, _name.text)),
          child: const Text('Continue'),
        ),
        status(context),
      ],
      actions: [_signOutButton(widget.session)],
    );
  }
}

// --- create a family or accept an invitation --------------------------------

class FamilyStartPage extends StatefulWidget {
  const FamilyStartPage({super.key, required this.session});
  final Session session;

  @override
  State<FamilyStartPage> createState() => _FamilyStartPageState();
}

class _FamilyStartPageState extends State<FamilyStartPage> with BusyState {
  final _familyName = TextEditingController();
  Role _role = Role.me;
  late final Stream<List<Invite>> _invites =
      Sync.watchInvites(widget.session.inviteKeys);

  @override
  void dispose() {
    _familyName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return _page(
      context,
      'Hello ${s.name}',
      [
        Text('Invitations', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        StreamBuilder<List<Invite>>(
          stream: _invites,
          builder: (context, snap) {
            final list = snap.data ?? const <Invite>[];
            if (list.isEmpty) {
              return const Card(
                child: ListTile(
                  leading: Icon(Icons.mail_outline),
                  title: Text('No invitations yet'),
                  subtitle: Text(
                      'Ask the family admin to invite your email or username.'),
                ),
              );
            }
            return Column(
              children: [
                for (final inv in list)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.group_add_outlined),
                      title: Text(inv.familyName),
                      subtitle: Text(
                          'Invited by ${inv.invitedBy.isEmpty ? 'the admin' : inv.invitedBy} as ${inv.role.shortName}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Decline',
                            icon: const Icon(Icons.close),
                            onPressed: busy
                                ? null
                                : () => run(() => Sync.declineInvite(inv)),
                          ),
                          IconButton(
                            tooltip: 'Accept',
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: busy
                                ? null
                                : () => run(() => s.acceptInvite(inv)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const Divider(height: 40),
        Text('Or start your own family',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _familyName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              labelText: 'Family name (e.g. Kumawat family)',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        const Text('Your role in the family:'),
        RadioGroup<Role>(
          groupValue: _role,
          onChanged: (v) => setState(() => _role = v ?? _role),
          child: Column(
            children: [
              for (final r in Role.values)
                RadioListTile<Role>(value: r, title: Text(r.label)),
            ],
          ),
        ),
        FilledButton(
          onPressed: busy
              ? null
              : () => run(() => s.createFamily(_familyName.text, _role)),
          child: const Text('Create family (you become admin)'),
        ),
        status(context),
      ],
      actions: [_signOutButton(s)],
    );
  }
}

// --- no connection ----------------------------------------------------------

class OfflinePage extends StatelessWidget {
  const OfflinePage({super.key, required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    return _page(
      context,
      'Aaj Kya Banega?',
      [
        const Icon(Icons.cloud_off_outlined, size: 56),
        const SizedBox(height: 16),
        Text('Could not reach the server',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Check your internet connection and try again.'),
        const SizedBox(height: 16),
        FilledButton(onPressed: session.retry, child: const Text('Try again')),
      ],
      actions: [_signOutButton(session)],
    );
  }
}
