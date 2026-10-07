import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'account.dart';
import 'auth_screens.dart';
import 'notifications.dart';
import 'store.dart';
import 'sync.dart';
import 'tasks.dart';
import 'widgets.dart';

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
          SettingsPage(store: _store, session: widget.session),
          HealthPage(store: _store),
        ];
        final cs = Theme.of(context).colorScheme;
        final dark = Theme.of(context).brightness == Brightness.dark;
        final family = _store.familyName.trim();
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 64,
            titleSpacing: 16,
            title: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF7043), Color(0xFFD84315)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.soup_kitchen, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Aaj Kya Banega?',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      if (family.isNotEmpty)
                        Text(family,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              AppMenuButton<String>(
                tooltip: 'Menu',
                onSelected: _onMenu,
                options: [
                  MenuOption(
                      'theme',
                      dark ? 'Light theme' : 'Dark theme',
                      dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                  const MenuOption('reminders', 'Reminders & times', Icons.alarm),
                  const MenuOption('test', 'Send test notification',
                      Icons.notifications_active_outlined),
                  if (_store.familyCode != null)
                    const MenuOption(
                        'sync', 'Check for menu changes', Icons.sync),
                  if (Sync.available)
                    const MenuOption('signout', 'Sign out', Icons.logout,
                        dividerBefore: true),
                ],
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: pages[_tab],
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.today_outlined),
                  selectedIcon: Icon(Icons.today),
                  label: 'Today'),
              NavigationDestination(
                  icon: Icon(Icons.calendar_view_week_outlined),
                  selectedIcon: Icon(Icons.calendar_view_week),
                  label: 'Week'),
              NavigationDestination(
                  icon: Icon(Icons.group_outlined),
                  selectedIcon: Icon(Icons.group),
                  label: 'Family'),
              NavigationDestination(
                  icon: Icon(Icons.favorite_border),
                  selectedIcon: Icon(Icons.favorite),
                  label: 'Health'),
            ],
          ),
        );
      },
    );
  }

  Future<void> _onMenu(String value) async {
    switch (value) {
      case 'theme':
        _store.setThemeMode(
            Theme.of(context).brightness == Brightness.dark
                ? ThemeMode.light
                : ThemeMode.dark);
      case 'reminders':
        await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ReminderSettingsPage(store: _store)),
        );
      case 'test':
        await Notifier.instance
            .showNow('Aaj Kya Banega?', 'Notifications are working.');
      case 'sync':
        try {
          await Sync.backgroundCheck();
          await _store.reload();
          _snack('Checked for changes');
        } catch (_) {
          _snack('Could not check. Are you online?');
        }
      case 'signout':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Sign out?'),
            content: const Text('You will need to sign in again to use the app.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Sign out')),
            ],
          ),
        );
        if (ok == true) await widget.session.signOut();
    }
  }
}

/// Notification switch and reminder times for this phone's role.
class ReminderSettingsPage extends StatelessWidget {
  const ReminderSettingsPage({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders & times')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) =>
            SettingsPage(store: store, remindersOnly: true),
      ),
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
                    _role!, _name.text.trim().isEmpty ? _role!.shortName : _name.text, null),
            child: const Text('Continue on this phone'),
          ),
        ],
      ),
    );
  }
}

// --- menu cards -----------------------------------------------------------

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _greeting(DateTime now) {
  final h = now.hour;
  return h < 12
      ? 'Good morning'
      : h < 17
          ? 'Good afternoon'
          : 'Good evening';
}

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
    final text = Theme.of(context).textTheme;
    final dish = store.dish(weekday, slot);
    final tone = slot.tone(Theme.of(context).brightness);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      color: highlight ? cs.primaryContainer.withValues(alpha: 0.55) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: highlight ? cs.primary : cs.outlineVariant,
          width: highlight ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        onTap: () async {
          final v = await _askText(
              context, '${dayNames[weekday - 1]} - ${slot.label}', dish);
          if (v != null) store.setDish(weekday, slot, v);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(slot.icon, color: tone),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(slot.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        const Spacer(),
                        if (highlight)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('NEXT',
                                style: TextStyle(
                                    color: cs.onPrimary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      dish.isEmpty ? 'Tap to add' : dish,
                      style: text.bodyLarge?.copyWith(
                        color: dish.isEmpty ? cs.onSurfaceVariant : null,
                        fontStyle:
                            dish.isEmpty ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pills for All + each meal slot, with counts.
List<List<PillItem<Slot?>>> _slotPills(int Function(Slot) count, int total) => [
      [
        PillItem<Slot?>(null, 'All', count: total),
        for (final s in Slot.values)
          PillItem<Slot?>(s, s.shortLabel, icon: s.icon, count: count(s)),
      ],
    ];

class TodayPage extends StatefulWidget {
  const TodayPage({super.key, required this.store});
  final AppStore store;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  Slot? _filter;

  AppStore get store => widget.store;

  bool _needsSoaking(DateTime now) => store
      .dish(now.add(const Duration(days: 1)).weekday, Slot.morning)
      .toLowerCase()
      .contains('almond');

  /// The cook's checklist. Only shown on the cook's phone.
  Widget _statusCard(BuildContext context, DateTime now) {
    final cookDone = store.isDone(now, 'cook');
    final soakNeeded = _needsSoaking(now);
    final soakDone = store.isDone(now, 'soak');
    final total = soakNeeded ? 2 : 1;
    final doneCount = (cookDone ? 1 : 0) + (soakNeeded && soakDone ? 1 : 0);

    Widget row(String label, bool done, VoidCallback? onMark) => ListTile(
          dense: true,
          leading: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? Colors.green : null),
          title: Text(label),
          trailing: (!done && onMark != null)
              ? FilledButton.tonal(onPressed: onMark, child: const Text('Done'))
              : const Text('Done'),
        );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('Your checklist',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text('$doneCount/$total done',
                    style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
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

  Widget _reminderBanner(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 5),
        child: ListTile(
          leading: const Icon(Icons.alarm_add_outlined),
          title: const Text('Set your reminder times'),
          subtitle: const Text('Choose when you want each reminder.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ReminderSettingsPage(store: store)),
          ),
        ),
      );

  Widget _emptyMenuHint(BuildContext context) => const Card(
        margin: EdgeInsets.symmetric(vertical: 5),
        child: ListTile(
          leading: Icon(Icons.restaurant_menu),
          title: Text('No menu yet'),
          subtitle: Text('Tap a meal below to add what is being cooked.'),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    // The meal to think about now: breakfast in the morning, lunch until
    // the afternoon, dinner after that.
    final Slot next = nowMin < 11 * 60
        ? Slot.breakfast
        : nowMin < 16 * 60
            ? Slot.lunch
            : Slot.dinner;

    int count(Slot s) => store.dish(now.weekday, s).isEmpty ? 0 : 1;
    final total = Slot.values.where((s) => count(s) > 0).length;
    final shown = _filter == null
        ? [
            for (final s in Slot.values)
              if (count(s) > 0 || s.isMeal) s
          ]
        : [_filter!];
    final name = store.myName.trim();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? _greeting(now) : '${_greeting(now)}, $name',
                    style: text.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text(
                  '${dayNames[now.weekday - 1]}, ${now.day} ${_monthNames[now.month - 1]}',
                  style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        FilterPills<Slot?>(
          groups: _slotPills(count, total),
          selected: _filter,
          onSelected: (v) => setState(() => _filter = v),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            children: [
              if (_filter == null && !store.hasAnyTaskTime && store.notificationsOn)
                _reminderBanner(context),
              if (_filter == null && total == 0) _emptyMenuHint(context),
              if (_filter == null && store.role == Role.cook)
                _statusCard(context, now),
              for (final s in shown)
                SlotCard(
                  weekday: now.weekday,
                  slot: s,
                  store: store,
                  highlight: _filter == null && s == next,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _DayOrder { week, today }

class WeekPage extends StatefulWidget {
  const WeekPage({super.key, required this.store});
  final AppStore store;

  @override
  State<WeekPage> createState() => _WeekPageState();
}

class _WeekPageState extends State<WeekPage> {
  Slot? _filter;
  _DayOrder _order = _DayOrder.week;

  AppStore get store => widget.store;

  Widget _line(BuildContext context, Slot s, int day) {
    final dish = store.dish(day, s);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(s.icon, size: 16, color: s.tone(Theme.of(context).brightness)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              dish.isEmpty ? 'Not set' : dish,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: dish.isEmpty ? cs.onSurfaceVariant : null,
                fontStyle: dish.isEmpty ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now().weekday;
    final days = _order == _DayOrder.week
        ? [for (var d = 1; d <= 7; d++) d]
        : [for (var i = 0; i < 7; i++) (today - 1 + i) % 7 + 1];

    int count(Slot s) =>
        [for (var d = 1; d <= 7; d++) store.dish(d, s)].where((v) => v.isNotEmpty).length;
    final total = Slot.values.where((s) => count(s) > 0).length;
    final slots = _filter == null
        ? [Slot.breakfast, Slot.lunch, Slot.dinner]
        : [_filter!];

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilterPills<Slot?>(
                groups: _slotPills(count, total),
                selected: _filter,
                onSelected: (v) => setState(() => _filter = v),
              ),
            ),
            AppMenuButton<_DayOrder>(
              tooltip: 'Sort days',
              selected: _order,
              onSelected: (v) => setState(() => _order = v),
              options: const [
                MenuOption(_DayOrder.week, 'Monday to Sunday',
                    Icons.calendar_view_week),
                MenuOption(_DayOrder.today, 'Starting today', Icons.today),
              ],
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            children: [
              for (final d in days)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: d == today ? cs.primary : cs.outlineVariant,
                      width: d == today ? 1.6 : 1,
                    ),
                  ),
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => DayEditPage(store: store, weekday: d)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(dayNames[d - 1],
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800)),
                              if (d == today) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text('TODAY',
                                      style: TextStyle(
                                          color: cs.onPrimary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800)),
                                ),
                              ],
                              const Spacer(),
                              Icon(Icons.chevron_right,
                                  color: cs.onSurfaceVariant),
                            ],
                          ),
                          for (final s in slots) _line(context, s, d),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
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
      void Function(List<String>) onChange, String addLabel,
      {String? note}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(note,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
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
        _section(
            context,
            'Daily guidelines',
            store.guidelines,
            store.setGuidelines,
            'Add guideline',
            note: store.familyCode == null ? null : 'Shared with your family'),
        _section(
            context,
            'My medicine timings',
            store.medicines,
            store.setMedicines,
            'Add medicine (e.g. 8:00 AM - name)',
            note: 'Private: only you can see this'),
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
  const SettingsPage(
      {super.key, required this.store, this.session, this.remindersOnly = false});
  final AppStore store;

  /// Null when running without accounts (Firebase not set up).
  final Session? session;

  /// Show the reminder times instead of the family and account section.
  final bool remindersOnly;

  Future<void> _pick(BuildContext context, bool weekend, Task task) async {
    final day = weekend ? DateTime.saturday : DateTime.monday;
    final cur = store.taskTime(task, day) ?? 8 * 60;
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
              'Your role: ${store.role!.shortName}${admin ? ' (Admin)' : ''}'),
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
                    subtitle: Text('Invited as ${p.role.shortName} - waiting'),
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
          '@${m.username} - ${m.role.shortName}${m.admin ? ' - Admin' : ''}'),
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
                    PopupMenuItem(value: r.name, child: Text('Make ${r.shortName}')),
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
    var role = Role.familyMember;
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

  Widget _timeTile(BuildContext context, bool weekend, Task t) {
    final minutes =
        store.taskTime(t, weekend ? DateTime.saturday : DateTime.monday);
    return ListTile(
      title: Text(t.label),
      trailing: minutes == null
          ? Text('Not set',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(formatMinutes(minutes)),
                IconButton(
                  tooltip: 'Remove time',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => store.clearTaskTime(weekend, t),
                ),
              ],
            ),
      onTap: () => _pick(context, weekend, t),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = store.role!;
    final code = store.familyCode;

    if (!remindersOnly) {
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
        ],
      );
    }

    return ListView(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.notifications_outlined),
          title: const Text('Notifications'),
          subtitle: Text('Reminders for: ${role.shortName}'),
          value: store.notificationsOn,
          onChanged: store.setNotificationsOn,
        ),
        if (!store.hasAnyTaskTime)
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('No reminder times yet'),
            subtitle: Text('Tap a reminder below to choose its time. '
                'Reminders without a time stay off.'),
          ),
        for (final weekend in [false, true]) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(
              weekend
                  ? 'Weekend reminder times (Sat-Sun)'
                  : 'Weekday reminder times (Mon-Fri)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final t in Task.forRole(role))
            _timeTile(context, weekend, t),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
