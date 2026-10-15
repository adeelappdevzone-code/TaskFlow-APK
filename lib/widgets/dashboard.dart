import 'package:flutter/material.dart';

import '../core/theme.dart';

// Building blocks for the laptop (wide screen) pages.

/// White rounded card with a soft shadow (laptop dashboards).
class DashCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const DashCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEEF1F6)),
          boxShadow: const [
            BoxShadow(color: Color(0x0A1F2937), blurRadius: 18, offset: Offset(0, 6)),
          ],
        ),
        child: child,
      );
}

/// Rounded filter button; filled blue when selected.
class FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const FilterPill({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppColors.primary : AppColors.border),
          ),
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.text)),
        ),
      );
}

/// Two-icon switch, e.g. board / list or grid / list.
class ViewToggle extends StatelessWidget {
  final bool board;
  final ValueChanged<bool> onChanged;
  final IconData firstIcon;
  final String firstTip;
  final IconData secondIcon;
  final String secondTip;
  const ViewToggle({
    super.key,
    required this.board,
    required this.onChanged,
    this.firstIcon = Icons.view_kanban_outlined,
    this.firstTip = 'Board view',
    this.secondIcon = Icons.view_list_rounded,
    this.secondTip = 'List view',
  });

  @override
  Widget build(BuildContext context) {
    Widget item(bool first, IconData icon, String tip) => Tooltip(
          message: tip,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onChanged(first),
            child: Container(
              width: 56,
              height: 40,
              decoration: BoxDecoration(
                color: board == first ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: board == first ? Colors.white : AppColors.textMuted, size: 22),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF1F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          item(true, firstIcon, firstTip),
          item(false, secondIcon, secondTip),
        ],
      ),
    );
  }
}

/// Number card with an icon in a soft circle: "3  Pending".
class StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int value;
  final String label;

  /// Colour the number like the icon (Pending/Overdue/Done) or keep it dark.
  final bool colorValue;
  const StatCard({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.colorValue = true,
  });

  @override
  Widget build(BuildContext context) => DashCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: color.withAlpha(28),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$value',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: colorValue ? color : AppColors.text)),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// "Sort: Name ▾" button that opens a menu of [options].
class SortButton extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  const SortButton(
      {super.key, required this.options, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Sort',
        onSelected: onSelected,
        itemBuilder: (_) => [
          for (final o in options)
            PopupMenuItem(
              value: o,
              child: Row(children: [
                SizedBox(
                    width: 24,
                    child: o == selected
                        ? const Icon(Icons.check_rounded, size: 18, color: AppColors.primary)
                        : null),
                Text(o),
              ]),
            ),
        ],
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_vert_rounded, size: 20, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Text('Sort: $selected', style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      );
}

/// Page title + subtitle used at the top of laptop pages.
class PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;
  const PageHeader(
      {super.key, required this.title, required this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 14.5)),
              ],
            ),
          ),
          ...actions,
        ],
      );
}
