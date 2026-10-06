import 'package:flutter/material.dart';

import 'notifications.dart';
import 'store.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});
  final AppStore store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final pages = [
      TodayPage(store: s),
      WeekPage(store: s),
      HealthPage(store: s),
      SettingsPage(store: s),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Aaj Kya Banega?')),
      body: ListenableBuilder(
        listenable: s,
        builder: (_, _) => pages[_tab],
      ),
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

  Future<void> _pick(BuildContext context, bool weekend, Slot slot) async {
    final day = weekend ? DateTime.saturday : DateTime.monday;
    final cur = store.notifyTime(day, slot);
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
    );
    if (t != null) store.setNotifyTime(weekend, slot, t.hour * 60 + t.minute);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SwitchListTile(
          title: const Text('Daily notifications'),
          value: store.notificationsOn,
          onChanged: store.setNotificationsOn,
        ),
        for (final weekend in [false, true]) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              weekend ? 'Weekend reminder times (Sat-Sun)' : 'Weekday reminder times (Mon-Fri)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final s in Slot.values)
            ListTile(
              leading: Icon(s.icon),
              title: Text(s.label),
              trailing: Text(formatMinutes(store.notifyTime(
                  weekend ? DateTime.saturday : DateTime.monday, s))),
              onTap: () => _pick(context, weekend, s),
            ),
        ],
        const Divider(),
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('Send test notification'),
          onTap: () => Notifier.instance.showTest(),
        ),
      ],
    );
  }
}
