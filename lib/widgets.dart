import 'package:flutter/material.dart';

class PillItem<T> {
  const PillItem(this.value, this.label, {this.icon, this.count});
  final T value;
  final String label;
  final IconData? icon;
  final int? count;
}

/// Horizontally scrolling filter pills, in groups separated by a divider.
/// The selected pill is filled; the others are outlined. Each pill can show
/// an icon and a count.
class FilterPills<T> extends StatelessWidget {
  const FilterPills({
    super.key,
    required this.groups,
    required this.selected,
    required this.onSelected,
  });

  final List<List<PillItem<T>>> groups;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (var g = 0; g < groups.length; g++) ...[
            if (g > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: VerticalDivider(width: 12, color: cs.outlineVariant),
              ),
            for (final item in groups[g])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Pill<T>(
                  item: item,
                  active: item.value == selected,
                  onTap: () => onSelected(item.value),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Pill<T> extends StatelessWidget {
  const _Pill({required this.item, required this.active, required this.onTap});
  final PillItem<T> item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = active ? cs.onPrimary : cs.onSurfaceVariant;
    return Material(
      color: active ? cs.primary : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(color: active ? cs.primary : cs.outlineVariant),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.icon != null) ...[
                Icon(item.icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Text(item.label,
                  style: TextStyle(
                      color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
              if (item.count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: active
                        ? cs.onPrimary.withValues(alpha: 0.22)
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${item.count}',
                      style: TextStyle(
                          color: fg,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class MenuOption<T> {
  const MenuOption(this.value, this.label, this.icon, {this.dividerBefore = false});
  final T value;
  final String label;
  final IconData icon;
  final bool dividerBefore;
}

/// Hamburger button that opens a dropdown of icon + label rows, with a
/// check mark on the selected one (when [selected] is given).
class AppMenuButton<T> extends StatelessWidget {
  const AppMenuButton({
    super.key,
    required this.options,
    required this.onSelected,
    this.selected,
    this.tooltip = 'Menu',
    this.icon = Icons.menu,
  });

  final List<MenuOption<T>> options;
  final ValueChanged<T> onSelected;
  final T? selected;
  final String tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<T>(
      tooltip: tooltip,
      icon: Icon(icon),
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final o in options) ...[
          if (o.dividerBefore) const PopupMenuDivider(),
          PopupMenuItem<T>(
            value: o.value,
            child: Row(
              children: [
                Icon(o.icon,
                    size: 19,
                    color: o.value == selected ? cs.primary : cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(o.label,
                      style: TextStyle(
                          fontWeight: o.value == selected
                              ? FontWeight.w700
                              : FontWeight.w500)),
                ),
                if (o.value == selected)
                  Icon(Icons.check, size: 18, color: cs.primary),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
