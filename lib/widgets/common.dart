import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/models.dart';

class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(70),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: size * 0.5,
          height: size * 0.5,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(size * 0.1),
          ),
          child: Icon(Icons.check_rounded,
              color: AppColors.primary, size: size * 0.4),
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final Color color;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withAlpha(150),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                  Text(label),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: 8),
                    Icon(trailingIcon, size: 20)
                  ],
                ],
              ),
      ),
    );
  }
}

class TagChip extends StatelessWidget {
  final String label;
  final Color color;
  const TagChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
        ),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Text(actionLabel!,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const EmptyState(
      {super.key, required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
                color: AppColors.primaryLight, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.primary, size: 34),
          ),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

class WhiteCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const WhiteCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(14),
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEEF1F6)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Round status indicator used on task rows.
class StatusCircle extends StatelessWidget {
  final TaskItem task;
  final VoidCallback? onTap;
  const StatusCircle({super.key, required this.task, this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget inner = const SizedBox(width: 24, height: 24);
    switch (task.displayStatus) {
      case DisplayStatus.completed:
        inner = Container(
          width: 24,
          height: 24,
          decoration:
              const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
        );
        break;
      case DisplayStatus.inProgress:
        inner = Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.purple, width: 2),
          ),
          child: const Icon(Icons.timelapse_rounded, color: AppColors.purple, size: 15),
        );
        break;
      case DisplayStatus.cancelled:
        inner = Container(
          width: 24,
          height: 24,
          decoration:
              const BoxDecoration(color: AppColors.dangerLight, shape: BoxShape.circle),
          child: const Icon(Icons.close_rounded, color: AppColors.danger, size: 16),
        );
        break;
      case DisplayStatus.pending:
        inner = Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFC7CDD6), width: 2),
          ),
        );
        break;
    }
    return GestureDetector(
      onTap: task.isCancelled ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(padding: const EdgeInsets.all(4), child: inner),
    );
  }
}

/// One task row (used on Home, Tasks, Calendar and Project screens).
class TaskTile extends StatelessWidget {
  final TaskItem task;
  final VoidCallback onTap;
  final bool showDay;

  /// Team tasks: what the round status button does (null = not allowed) and
  /// what is shown on the right (instead of the personal category).
  final bool teamTask;
  final VoidCallback? onToggle;
  final Widget? trailing;

  const TaskTile(
      {super.key,
      required this.task,
      required this.onTap,
      this.showDay = true,
      this.teamTask = false,
      this.onToggle,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final cat = teamTask ? null : store.categoryById(task.categoryId);
    final done = task.isCompleted || task.isCancelled;
    final time = timeRangeText(task.startAt, task.endAt);
    final sub = showDay ? '${relativeDay(task.startAt)} • $time' : time;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WhiteCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
        child: Row(
          children: [
            StatusCircle(
              task: task,
              onTap: teamTask ? onToggle : () => store.setCompleted(task, !task.isCompleted),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: done ? AppColors.textMuted : AppColors.text,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (task.priority == Priority.high && !done) ...[
                        const Icon(Icons.local_fire_department_rounded,
                            size: 14, color: AppColors.danger),
                        const SizedBox(width: 3),
                      ],
                      Flexible(
                        child: Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: task.isOverdue ? AppColors.danger : AppColors.textMuted,
                          ),
                        ),
                      ),
                      if (task.checklist.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.checklist_rounded,
                            size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 2),
                        Text('${task.checklistDone}/${task.checklist.length}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textMuted)),
                      ],
                      if (task.links.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.link_rounded, size: 14, color: AppColors.textMuted),
                      ],
                      if (task.timerRunning) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.timer_rounded, size: 14, color: AppColors.primary),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (cat != null) ...[
              const SizedBox(width: 8),
              TagChip(label: cat.name, color: Color(cat.color)),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class ColorPickerRow extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const ColorPickerRow({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in kPaletteColors)
          GestureDetector(
            onTap: () => onChanged(c),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                    color: selected == c ? AppColors.text : Colors.transparent,
                    width: 2.5),
              ),
              child: selected == c
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          ),
      ],
    );
  }
}

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  final Color color;
  const Avatar(
      {super.key, required this.name, this.size = 40, this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withAlpha(35), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials(name),
        style: TextStyle(
            color: color, fontWeight: FontWeight.w700, fontSize: size * 0.36),
      ),
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel,
              style: TextStyle(
                  color: danger ? AppColors.danger : AppColors.primary,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

/// Dialog with a single text field; returns the trimmed text or null.
Future<String?> textInputDialog(BuildContext context,
    {required String title, String hint = '', String initial = '', String okLabel = 'Save'}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: fieldDecoration(hint),
        inputFormatters: [LengthLimitingTextInputFormatter(100)],
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final v = ctrl.text.trim();
            if (v.isNotEmpty) Navigator.pop(ctx, v);
          },
          child: Text(okLabel),
        ),
      ],
    ),
  );
}

/// Segmented-control style tab (All / Pending / Done ...).
class TabPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const TabPill({super.key, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? AppColors.primary : AppColors.border),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  color: active ? Colors.white : AppColors.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5)),
        ),
      ),
    );
  }
}
