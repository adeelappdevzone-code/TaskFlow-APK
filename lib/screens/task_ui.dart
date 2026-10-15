import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../data/task_repository.dart';
import '../data/team_store.dart';
import '../data/time_tracker.dart';
import '../widgets/common.dart';
import '../widgets/task_extras.dart';
import 'task_form_screen.dart';
import 'task_open.dart';

// Small pieces shared by Home, My Tasks and other task lists.

IconData taskIconFor(TaskRef r) {
  if (r.isTeam) return Icons.groups_outlined;
  if (r.task.priority == Priority.high) return Icons.flag_outlined;
  if (r.task.projectId != null) return Icons.folder_outlined;
  return Icons.description_outlined;
}

/// Where a task belongs: team name, project name or "Personal".
class SourceChip extends StatelessWidget {
  final TaskRef ref;
  final bool small;
  const SourceChip({super.key, required this.ref, this.small = false});

  @override
  Widget build(BuildContext context) {
    final color = Color(ref.sourceColor);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 3 : 5),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(ref.sourceLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              TextStyle(color: color, fontSize: small ? 11.5 : 12.5, fontWeight: FontWeight.w600)),
    );
  }
}

class TaskActionsMenu extends StatelessWidget {
  final TaskRef ref;
  const TaskActionsMenu({required this.ref});

  @override
  Widget build(BuildContext context) {
    final t = ref.task;
    final team = ref.team;
    final canTime = ref.canComplete && t.status == TaskStatus.pending;
    final canEdit = team == null || TeamStore.instance.canEdit(team, t);
    final canStop = t.timerRunning && (team == null || TeamStore.instance.canStopTimer(team, t));
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.text, size: 20),
      onSelected: (a) async {
        switch (a) {
          case 'open':
            openTaskRef(context, ref);
          case 'edit':
            Navigator.push(
                context, MaterialPageRoute(builder: (_) => TaskFormScreen(task: t, team: team)));
          case 'done':
            ref.setCompleted(!t.isCompleted);
          case 'start':
            TimeTracker.start(t, team: team);
          case 'stop':
            await stopTimerWithCheck(context, t, team: team);
          case 'delete':
            final ok = await confirmDialog(context,
                title: 'Delete task?',
                message: '"${t.title}" will be deleted.',
                confirmLabel: 'Delete',
                danger: true);
            if (ok) {
              if (team == null) {
                await AppStore.instance.deleteTask(t);
              } else {
                TeamStore.instance.deleteTask(team, t);
              }
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'open', child: Text('Open')),
        if (canEdit) const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (ref.canComplete)
          PopupMenuItem(
              value: 'done', child: Text(t.isCompleted ? 'Mark as not done' : 'Mark as done')),
        if (canStop)
          const PopupMenuItem(value: 'stop', child: Text('Stop timer'))
        else if (canTime && !t.timerRunning)
          const PopupMenuItem(value: 'start', child: Text('Start timer')),
        if (canEdit)
          const PopupMenuItem(
              value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.danger))),
      ],
    );
  }
}

class TickBox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const TickBox({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: value ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: value
                    ? AppColors.primary
                    : (enabled ? const Color(0xFFC5CBD5) : AppColors.border),
                width: 1.6),
          ),
          child: value ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
        ),
      ),
    );
  }
}

/// Donut chart: [parts] as (count, color) over [total], text in the middle.
class DonutRing extends StatelessWidget {
  final List<(int, Color)> parts;
  final int total;
  final String center;
  final String caption;
  const DonutRing(
      {required this.parts, required this.total, required this.center, required this.caption});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DonutPainter(parts, total),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text(caption, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<(int, Color)> parts;
  final int total;
  _DonutPainter(this.parts, this.total);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final side = math.min(size.width, size.height);
    final rect = Rect.fromCenter(
        center: size.center(Offset.zero), width: side - stroke, height: side - stroke);
    canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = const Color(0xFFEDF1F7));
    if (total == 0) return;
    var start = -math.pi / 2;
    for (final (n, color) in parts) {
      if (n == 0) continue;
      final sweep = math.pi * 2 * n / total;
      canvas.drawArc(
          rect,
          start,
          sweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = parts.length == 1 ? StrokeCap.round : StrokeCap.butt
            ..color = color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}

class IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBox({required this.icon, required this.color, this.size = 42});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withAlpha(24),
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        child: Icon(icon, color: color, size: size * 0.52),
      );
}

/// "Today 13:00", "Tomorrow", "Yesterday", "19 Oct".
String dueLabel(TaskItem t, DateTime now) {
  final d = t.startAt;
  if (isSameDay(d, now)) return t.isAllDay ? 'Today' : 'Today ${formatTime(d)}';
  if (isSameDay(d, now.add(const Duration(days: 1)))) return 'Tomorrow';
  if (isSameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return DateFormat(d.year == now.year ? 'd MMM' : 'd MMM yyyy').format(d);
}

/// Due text in red: late, or due today and not done.
bool dueIsUrgent(TaskItem t, DateTime now) =>
    t.isOverdue || (t.status == TaskStatus.pending && isSameDay(t.startAt, now));

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  final IconData? icon;
  const _Chip({required this.label, required this.color, required this.bg, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class PriorityChip extends StatelessWidget {
  final Priority priority;
  const PriorityChip({super.key, required this.priority});

  @override
  Widget build(BuildContext context) => switch (priority) {
        Priority.high => const _Chip(
            label: 'High',
            color: AppColors.danger,
            bg: AppColors.dangerLight,
            icon: Icons.local_fire_department_rounded),
        Priority.medium => const _Chip(
            label: 'Medium',
            color: Color(0xFFEA7A0C),
            bg: Color(0xFFFFF0DF),
            icon: Icons.local_fire_department_rounded),
        Priority.low =>
          const _Chip(label: 'Low', color: AppColors.textMuted, bg: Color(0xFFF1F3F6)),
      };
}

/// To Do / In Progress / Review / Overdue / Done.
class StatusChip extends StatelessWidget {
  final TaskItem task;
  const StatusChip({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final t = task;
    if (t.isCompleted) {
      return const _Chip(label: 'Done', color: AppColors.success, bg: AppColors.successLight);
    }
    if (t.isCancelled) {
      return const _Chip(label: 'Cancelled', color: AppColors.textMuted, bg: Color(0xFFF1F3F6));
    }
    if (t.isOverdue) {
      return const _Chip(label: 'Overdue', color: AppColors.danger, bg: AppColors.dangerLight);
    }
    return switch (t.stage) {
      TaskStage.doing =>
        const _Chip(label: 'In Progress', color: AppColors.primary, bg: AppColors.primaryLight),
      TaskStage.review =>
        const _Chip(label: 'Review', color: Color(0xFFB45309), bg: AppColors.warningLight),
      _ => const _Chip(label: 'To Do', color: Color(0xFF4B5563), bg: Color(0xFFF1F3F6)),
    };
  }
}

/// Who does the task: me for personal tasks, the assignee for team tasks.
String assigneeNameOf(TaskRef r) {
  final team = r.team;
  if (team == null) return AppStore.instance.currentUser?.name ?? 'Me';
  return r.task.assigneeId == null ? 'Unassigned' : team.nameOf(r.task.assigneeId);
}
