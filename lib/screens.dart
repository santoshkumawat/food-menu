import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'notifications.dart';
import 'store.dart';
import 'sync.dart';
import 'tasks.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});
  final AppStore store;

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
      onJoinRequest: (name) => _snack('$name wants to join your family'),
      onRemoved: () {
        Sync.stopBackground();
        _store.resetProfile();
        _snack('You were removed from the family');
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The background check may have changed the saved data meanwhile.
    if (state == AppLifecycleState.resumed) _store.reload();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        if (!_store.isSetUp) return SetupPage(store: _store);
        final pages = [
          TodayPage(store: _store),
          WeekPage(store: _store),
          HealthPage(store: _store),
          SettingsPage(store: _store),
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

class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.store});
  final AppStore store;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  Role? _role;
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Set while waiting for the admin to answer a join request.
  String? _waitingFor;
  String? _pendingCode;
  StreamSubscription<Decision>? _decisionSub;

  @override
  void dispose() {
    _decisionSub?.cancel();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _displayName => _name.text.trim().isEmpty
      ? (_role == Role.cook ? 'Cook' : 'Me')
      : _name.text.trim();

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not reach the server. Check the internet and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() => _run(() async {
        final code =
            await Sync.createFamily(widget.store, _displayName, _role!);
        widget.store.setProfile(_role!, _displayName, code, admin: true);
        await Sync.startBackground();
      });

  Future<void> _join() => _run(() async {
        final code = _code.text.trim().toUpperCase();
        final r = await Sync.requestJoin(code, _displayName, _role!);
        switch (r.result) {
          case JoinResult.notFound:
            setState(() => _error = 'No family found with that code.');
          case JoinResult.alreadyMember:
            await _enter(code);
          case JoinResult.pending:
            setState(() {
              _waitingFor = r.adminName ?? 'the admin';
              _pendingCode = code;
            });
            _decisionSub?.cancel();
            _decisionSub = Sync.watchDecision(code).listen((d) async {
              _decisionSub?.cancel();
              if (d == Decision.approved) {
                await _enter(code);
              } else if (mounted) {
                setState(() {
                  _waitingFor = null;
                  _error = 'The admin declined your request.';
                });
              }
            });
        }
      });

  Future<void> _enter(String code) async {
    await Sync.loadShared(widget.store, code);
    widget.store.setProfile(_role!, _displayName, code);
    await Sync.startBackground();
  }

  Future<void> _cancelWaiting() async {
    _decisionSub?.cancel();
    final code = _pendingCode;
    if (code != null) await Sync.cancelRequest(code);
    if (mounted) setState(() => _waitingFor = null);
  }

  void _localOnly() => widget.store.setProfile(_role!, _displayName, null);

  Widget _waiting() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Waiting for $_waitingFor to approve you...',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text(
                  'You can close the app. Come back and enter the same code once approved.'),
              const SizedBox(height: 8),
              TextButton(
                  onPressed: _cancelWaiting,
                  child: const Text('Cancel request')),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Aaj Kya Banega?')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_waitingFor != null)
            _waiting()
          else ...[
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
                labelText: 'Your name (shown to the family)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_role != null) ...[
              const SizedBox(height: 24),
              if (Sync.available) ...[
                FilledButton(
                  onPressed: _busy ? null : _create,
                  child: const Text('Start a new family (you become admin)'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Family code from the admin',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _busy ? null : _join,
                  child: const Text('Ask to join this family'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _busy ? null : _localOnly,
                  child: const Text('Use on this phone only (no sharing)'),
                ),
              ] else ...[
                const Text(
                  'Sharing between phones is not set up in this build '
                  '(google-services.json is missing), so the menu stays on this phone.',
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _localOnly,
                  child: const Text('Continue on this phone'),
                ),
              ],
            ],
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
  const SettingsPage({super.key, required this.store});
  final AppStore store;

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
    if (code == null) {
      return const [
        ListTile(
          leading: Icon(Icons.phone_android),
          title: Text('This phone only'),
          subtitle: Text('The menu is not shared with another phone'),
        ),
      ];
    }
    final admin = store.isAdmin;
    return [
      if (admin) ...[
        ListTile(
          leading: const Icon(Icons.vpn_key_outlined),
          title: Text('Family code: $code'),
          subtitle: const Text('People who enter it must be approved by you'),
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Code copied')));
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.person_add_alt_1_outlined),
          title: const Text('Invite someone'),
          subtitle: const Text('Share the family code'),
          onTap: () => SharePlus.instance.share(ShareParams(
            text: 'Join my family on Aaj Kya Banega? '
                'Open the app, choose "Ask to join this family" and enter this code: $code. '
                "I'll approve you.",
          )),
        ),
        ValueListenableBuilder<List<JoinRequest>>(
          valueListenable: Sync.requests,
          builder: (context, list, _) => Column(
            children: [
              for (final r in list)
                Card(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.how_to_reg_outlined),
                    title: Text('${r.name} wants to join'),
                    subtitle: Text(r.role.label),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Decline',
                          icon: const Icon(Icons.close),
                          onPressed: () => Sync.decline(code, r),
                        ),
                        IconButton(
                          tooltip: 'Allow',
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: () => Sync.approve(code, r),
                        ),
                      ],
                    ),
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
            for (final m in list)
              ListTile(
                leading: Icon(m.admin
                    ? Icons.admin_panel_settings_outlined
                    : Icons.person_outline),
                title: Text(m.name.isEmpty ? m.role.label : m.name),
                subtitle: Text('${m.role.label}${m.admin ? ' - Admin' : ''}'),
                trailing: (admin && !m.admin)
                    ? IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.person_remove_outlined),
                        onPressed: () => _confirmRemove(context, code, m),
                      )
                    : null,
              ),
            if (list.isEmpty)
              const ListTile(
                  dense: true, title: Text('Loading members... (needs internet)')),
          ],
        ),
      ),
    ];
  }

  Future<void> _confirmRemove(
      BuildContext context, String code, Member m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${m.name}?'),
        content: const Text(
            'They will lose access to the shared menu and stop getting its reminders.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await Sync.removeMember(code, m.uid);
  }

  @override
  Widget build(BuildContext context) {
    final role = store.role!;
    final code = store.familyCode;
    return ListView(
      children: [
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
