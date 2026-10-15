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

/// Ring chart card: done / pending / overdue with a legend.
class ProgressRingCard extends StatelessWidget {
  final int done;
  final int pending;
  final int overdue;
  final String title;
  final String? subtitle;
  const ProgressRingCard({
    super.key,
    required this.done,
    required this.pending,
    required this.overdue,
    this.title = 'Task progress',
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final total = done + pending;
    final pct = total == 0 ? 0 : (done * 100 / total).round();
    Widget row(Color c, String label, int v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text(label)),
              Text('$v', style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        );
    return DashCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (subtitle != null)
            Text(subtitle!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CustomPaint(
                  painter: _RingPainter(
                    done: done,
                    pending: pending - overdue,
                    overdue: overdue,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$pct%',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        Text('$done of $total done',
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  children: [
                    row(AppColors.success, 'Done', done),
                    row(AppColors.warning, 'Pending', pending),
                    row(AppColors.danger, 'Overdue', overdue),
                    row(const Color(0xFFD1D5DB), 'Total', total),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final int done;
  final int pending;
  final int overdue;
  _RingPainter({required this.done, required this.pending, required this.overdue});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0xFFEDF1F7);
    canvas.drawArc(rect, 0, 6.2832, false, base);
    final total = done + pending + overdue;
    if (total == 0) return;
    var start = -1.5708; // 12 o'clock
    for (final (value, color) in [
      (done, AppColors.success),
      (pending, AppColors.warning),
      (overdue, AppColors.danger),
    ]) {
      if (value == 0) continue;
      final sweep = 6.2832 * value / total;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt
          ..color = color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.done != done || old.pending != pending || old.overdue != overdue;
}
