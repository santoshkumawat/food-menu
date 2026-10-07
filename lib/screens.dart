import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'account.dart';
import 'auth_screens.dart';
import 'notifications.dart';
import 'store.dart';
import 'sync.dart';
import 'tasks.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store, required this.session});
  final AppStore store;
  final Session session;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  SyncSession? _session;
  String? _subscribedCode;

  AppStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store.addListener(_syncSubscription);
    _syncSubscription();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.removeListener(_syncSubscription);
    _session?.cancel();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Follows the shared family data while the app is open.
  void _syncSubscription() {
    final code = _store.familyCode;
    if (code == _subscribedCode) return;
    _session?.cancel();
    _subscribedCode = code;
    _session = Sync.listen(
      _store,
      onRemoteEdit: (who, summary) => _snack('Menu updated by $who\n$summary'),
      onRemoved: () async {
        await Sync.stopBackground();
        await Sync.clearFamilyLink();
        _store.resetProfile();
        _snack('You were removed from the family');
        widget.session.retry();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The background check may have changed the saved data meanwhile.
    if (state == AppLifecycleState.resumed) _store.reload();
  }

  /// The sign-in / onboarding screen to show, or null for the main app.
  Widget? _gate() {
    final session = widget.session;
    if (!Sync.available) {
      return _store.isSetUp ? null : SetupPage(store: _store);
    }
    return switch (session.state) {
      AuthState.loading =>
        const Scaffold(body: Center(child: CircularProgressIndicator())),
      AuthState.offline => OfflinePage(session: session),
      AuthState.signedOut => AuthPage(session: session),
      AuthState.unverified => VerifyPage(session: session),
      AuthState.needsProfile => ProfilePage(session: session),
      AuthState.noFamily => FamilyStartPage(session: session),
      AuthState.ready => _store.isSetUp
          ? null
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_store, widget.session]),
      builder: (context, _) {
        final gate = _gate();
        if (gate != null) return gate;
        final pages = [
          TodayPage(store: _store),
          WeekPage(store: _store),
          HealthPage(store: _store),
          SettingsPage(store: _store, session: widget.session),
        ];
        return Scaffold(
          appBar: AppBar(title: const Text('Aaj Kya Banega?')),
          body: pages[_tab],
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.today), label: 'Today'),
              NavigationDestination(
                  icon: Icon(Icons.calendar_view_week), label: 'Week'),
              NavigationDestination(
                  icon: Icon(Icons.favorite_border), label: 'Health'),
              NavigationDestination(
                  icon: Icon(Icons.settings_outlined), label: 'Settings'),
            ],
          ),
        );
      },
    );
  }
}

Future<String?> _askText(BuildContext context, String title, String initial,
    {String? hint}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLines: null,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Save')),
      ],
    ),
  );
}

// --- first-run setup ------------------------------------------------------

/// Used only when Firebase is not set up: the app runs on this phone alone.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.store});
  final AppStore store;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  Role? _role;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Aaj Kya Banega?')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Who is using this phone?',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          RadioGroup<Role>(
            groupValue: _role,
            onChanged: (v) => setState(() => _role = v),
            child: Column(
              children: [
                for (final r in Role.values)
                  RadioListTile<Role>(value: r, title: Text(r.label)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Your name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sharing between phones is not set up in this build '
            '(google-services.json is missing), so the menu stays on this phone.',
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _role == null
                ? null
                : () => widget.store.setProfile(
                    _role!, _name.text.trim().isEmpty ? 'Me' : _name.text, null),
            child: const Text('Continue on this phone'),
          ),
        ],
      ),
    );
  }
}

// --- menu cards -----------------------------------------------------------

class SlotCard extends StatelessWidget {
  const SlotCard({
    super.key,
    required this.weekday,
    required this.slot,
    required this.store,
    this.highlight = false,
  });
  final int weekday;
  final Slot slot;
  final AppStore store;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dish = store.dish(weekday, slot);
    return Card(
      color: highlight ? cs.primaryContainer : null,
      child: ListTile(
        leading: Icon(slot.icon),
        title: Text('${slot.label} · ${formatMinutes(eatTime(weekday, slot))}'),
        subtitle: Text(
          dish.isEmpty ? 'Tap to add' : dish,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        trailing: const Icon(Icons.edit_outlined, size: 18),
        onTap: () async {
          final v = await _askText(
              context, '${dayNames[weekday - 1]} ${slot.label}', dish);
          if (v != null) store.setDish(weekday, slot, v);
        },
      ),
    );
  }
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.store});
  final AppStore store;

  bool _needsSoaking(DateTime now) => store
      .dish(now.add(const Duration(days: 1)).weekday, Slot.morning)
      .toLowerCase()
      .contains('almond');

  Widget _statusCard(BuildContext context, DateTime now) {
    final isCook = store.role == Role.cook;
    final cookDone = store.isDone(now, 'cook');
    final soakNeeded = _needsSoaking(now);
    final soakDone = store.isDone(now, 'soak');

    Widget row(String label, bool done, VoidCallback? onMark) => ListTile(
          dense: true,
          leading: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? Colors.green : null),
          title: Text(label),
          trailing: (isCook && !done && onMark != null)
              ? FilledButton.tonal(onPressed: onMark, child: const Text('Done'))
              : Text(done ? 'Done' : 'Not yet'),
        );

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(isCook ? 'Your checklist' : 'Kitchen status',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          row('Breakfast & lunch prepared', cookDone,
              () => Notifier.instance.markDone(now, 'cook')),
          if (soakNeeded)
            row('Dry fruits soaked for tomorrow', soakDone,
                () => Notifier.instance.markDone(now, 'soak')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    // Next upcoming meal (breakfast/lunch/dinner) is highlighted.
    Slot? next;
    for (final s in Slot.values.where((s) => s.isMeal)) {
      if (eatTime(now.weekday, s) + 60 > nowMin) {
        next = s;
        break;
      }
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Text(dayNames[now.weekday - 1],
              style: Theme.of(context).textTheme.headlineMedium),
        ),
        _statusCard(context, now),
        for (final s in Slot.values)
          if (store.dish(now.weekday, s).isNotEmpty || s.isMeal)
            SlotCard(
              weekday: now.weekday,
              slot: s,
              store: store,
              highlight: s == next,
            ),
      ],
    );
  }
}

class WeekPage extends StatelessWidget {
  const WeekPage({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (var d = 1; d <= 7; d++)
          Card(
            shape: d == today
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: Theme.of(context).colorScheme.primary, width: 2),
                  )
                : null,
            child: ListTile(
              title: Text(dayNames[d - 1],
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text([
                'B: ${store.dish(d, Slot.breakfast)}',
                'L: ${store.dish(d, Slot.lunch)}',
                'D: ${store.dish(d, Slot.dinner)}',
              ].join('\n')),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => DayEditPage(store: store, weekday: d)),
              ),
            ),
          ),
      ],
    );
  }
}

class DayEditPage extends StatelessWidget {
  const DayEditPage({super.key, required this.store, required this.weekday});
  final AppStore store;
  final int weekday;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(dayNames[weekday - 1])),
      body: ListenableBuilder(
        listenable: store,
        builder: (_, _) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final s in Slot.values)
              SlotCard(weekday: weekday, slot: s, store: store),
          ],
        ),
      ),
    );
  }
}

class HealthPage extends StatelessWidget {
  const HealthPage({super.key, required this.store});
  final AppStore store;

  Widget _section(BuildContext context, String title, List<String> items,
      void Function(List<String>) onChange, String addLabel) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            if (items.isEmpty) const Text('Nothing added yet'),
            for (var i = 0; i < items.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(items[i]),
                onTap: () async {
                  final v = await _askText(context, title, items[i]);
                  if (v == null) return;
                  final copy = [...items];
                  copy[i] = v.trim();
                  onChange(copy.where((e) => e.isNotEmpty).toList());
                },
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => onChange([...items]..removeAt(i)),
                ),
              ),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(addLabel),
              onPressed: () async {
                final v = await _askText(context, addLabel, '');
                if (v != null && v.trim().isNotEmpty) {
                  onChange([...items, v.trim()]);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _section(context, 'Daily guidelines', store.guidelines,
            store.setGuidelines, 'Add guideline'),
        _section(context, 'Medicine timings', store.medicines,
            store.setMedicines, 'Add medicine (e.g. 8:00 AM - name)'),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('STAY HEALTHY',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          ),
        ),
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store, this.session});
  final AppStore store;

  /// Null when running without accounts (Firebase not set up).
  final Session? session;

  Future<void> _pick(BuildContext context, bool weekend, Task task) async {
    final day = weekend ? DateTime.saturday : DateTime.monday;
    final cur = store.taskTime(task, day);
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
    );
    if (t != null) store.setTaskTime(weekend, task, t.hour * 60 + t.minute);
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change role or family?'),
        content: const Text(
            'This phone will go back to the setup screen. The shared menu stays online.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) {
      await Sync.stopBackground();
      store.resetProfile();
    }
  }

  List<Widget> _familySection(BuildContext context, String? code) {
    final s = session;
    final admin = store.isAdmin;
    return [
      if (s != null)
        ListTile(
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(s.name),
          subtitle: Text('@${s.username}\n${s.email}'),
          isThreeLine: true,
          trailing: TextButton(
            onPressed: () => _confirm(
              context,
              'Sign out?',
              'You will need to sign in again to use the app.',
              'Sign out',
              s.signOut,
            ),
            child: const Text('Sign out'),
          ),
        ),
      if (code == null)
        const ListTile(
          leading: Icon(Icons.phone_android),
          title: Text('This phone only'),
          subtitle: Text('The menu is not shared with anyone'),
        )
      else ...[
        ListTile(
          leading: const Icon(Icons.group_outlined),
          title: Text(store.familyName.isEmpty ? 'Family' : store.familyName),
          subtitle: Text(
              'Your role: ${store.role!.label}${admin ? ' (Admin)' : ''}'),
        ),
        if (admin) ...[
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_outlined),
            title: const Text('Invite someone'),
            subtitle: const Text('By email or username'),
            onTap: () => _inviteDialog(context, code),
          ),
          ValueListenableBuilder<List<PendingInvite>>(
            valueListenable: Sync.pendingInvites,
            builder: (context, list, _) => Column(
              children: [
                for (final p in list)
                  ListTile(
                    leading: const Icon(Icons.mail_outline),
                    title: Text(p.key),
                    subtitle: Text('Invited as ${p.role.label} - waiting'),
                    trailing: IconButton(
                      tooltip: 'Cancel invite',
                      icon: const Icon(Icons.close),
                      onPressed: () => Sync.cancelInvite(code, p.key),
                    ),
                  ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text('Family members',
              style: Theme.of(context).textTheme.titleSmall),
        ),
        ValueListenableBuilder<List<Member>>(
          valueListenable: Sync.members,
          builder: (context, list, _) => Column(
            children: [
              for (final m in list) _memberTile(context, code, m, admin),
              if (list.isEmpty)
                const ListTile(
                    dense: true,
                    title: Text('Loading members... (needs internet)')),
            ],
          ),
        ),
        if (!admin && s != null)
          ListTile(
            leading: const Icon(Icons.exit_to_app),
            title: const Text('Leave family'),
            onTap: () => _confirm(
              context,
              'Leave ${store.familyName}?',
              'You will stop getting its menu and reminders. The admin can invite you again.',
              'Leave',
              s.leaveFamily,
            ),
          ),
      ],
    ];
  }

  Widget _memberTile(BuildContext context, String code, Member m, bool admin) {
    final isMe = m.uid == FirebaseAuth.instance.currentUser?.uid;
    return ListTile(
      leading: Icon(m.admin
          ? Icons.admin_panel_settings_outlined
          : Icons.person_outline),
      title: Text('${m.name.isEmpty ? m.username : m.name}${isMe ? ' (you)' : ''}'),
      subtitle: Text(
          '@${m.username} - ${m.role.label}${m.admin ? ' - Admin' : ''}'),
      trailing: admin
          ? PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'remove') {
                  _confirm(
                    context,
                    'Remove ${m.name}?',
                    'They will lose access to the shared menu and its reminders.',
                    'Remove',
                    () => Sync.removeMember(code, m.uid),
                  );
                } else {
                  await Sync.changeRole(code, m.uid, Role.values.byName(v));
                }
              },
              itemBuilder: (_) => [
                for (final r in Role.values)
                  if (r != m.role)
                    PopupMenuItem(value: r.name, child: Text('Make ${r.label}')),
                if (!m.admin)
                  const PopupMenuItem(value: 'remove', child: Text('Remove from family')),
              ],
            )
          : null,
    );
  }

  Future<void> _confirm(BuildContext context, String title, String body,
      String action, Future<void> Function() onYes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    if (ok == true) await onYes();
  }

  Future<void> _inviteDialog(BuildContext context, String code) async {
    final input = TextEditingController();
    var role = Role.me;
    String? error;
    var busy = false;
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Invite someone'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: input,
                  autofocus: true,
                  autocorrect: false,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Email or username',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                const Text('Their role:'),
                RadioGroup<Role>(
                  groupValue: role,
                  onChanged: (v) => setState(() => role = v ?? role),
                  child: Column(
                    children: [
                      for (final r in Role.values)
                        RadioListTile<Role>(
                            dense: true, value: r, title: Text(r.label)),
                    ],
                  ),
                ),
                if (error != null)
                  Text(error!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final k = await Sync.invite(
                          code: code,
                          familyName: store.familyName,
                          input: input.text,
                          role: role,
                          invitedBy: store.myName,
                        );
                        if (ctx.mounted) Navigator.pop(ctx, k);
                      } catch (e) {
                        setState(() {
                          busy = false;
                          error = errorMessage(e);
                        });
                      }
                    },
              child: const Text('Invite'),
            ),
          ],
        ),
      ),
    );
    if (key == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Invited $key. They will see it after signing in.'),
      action: SnackBarAction(
        label: 'Tell them',
        onPressed: () => SharePlus.instance.share(ShareParams(
          text: 'I invited you to "${store.familyName}" on Aaj Kya Banega. '
              'Install the app, sign up or log in with ${isEmail(key) ? 'this email: $key' : 'the username: $key'}, '
              'and accept the invitation.',
        )),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final role = store.role!;
    final code = store.familyCode;
    return ListView(
      children: [
        if (session == null)
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(store.myName.isEmpty ? role.label : store.myName),
            subtitle: Text(role.label),
            trailing: TextButton(
              onPressed: () => _confirmReset(context),
              child: const Text('Change'),
            ),
          ),
        ..._familySection(context, code),
        const Divider(),
        SwitchListTile(
          title: const Text('Notifications'),
          value: store.notificationsOn,
          onChanged: store.setNotificationsOn,
        ),
        for (final weekend in [false, true]) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              weekend
                  ? 'Weekend reminder times (Sat-Sun)'
                  : 'Weekday reminder times (Mon-Fri)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final t in Task.forRole(role))
            ListTile(
              title: Text(t.label),
              trailing: Text(formatMinutes(store.taskTime(
                  t, weekend ? DateTime.saturday : DateTime.monday))),
              onTap: () => _pick(context, weekend, t),
            ),
        ],
        const Divider(),
        if (code != null)
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Check for menu changes now'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await Sync.backgroundCheck();
                await store.reload();
                messenger.showSnackBar(
                    const SnackBar(content: Text('Checked for changes')));
              } catch (_) {
                messenger.showSnackBar(
                    const SnackBar(content: Text('Could not check. Are you online?')));
              }
            },
          ),
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('Send test notification'),
          onTap: () => Notifier.instance
              .showNow('Aaj Kya Banega?', 'Notifications are working.'),
        ),
      ],
    );
  }
}
