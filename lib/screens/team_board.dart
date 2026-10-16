import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../data/task_repository.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import 'create_task_dialog.dart';
import 'task_open.dart';
import 'task_ui.dart';

/// A team's board: To Do | In Progress | Review & Feedback | Done. Drag a
/// card to another column (long-press on a phone); "+" / "Add task" create a
/// task straight in that column.
class TeamBoard extends StatelessWidget {
  final Team team;
  final List<TaskItem> tasks;
  final EdgeInsetsGeometry padding;
  const TeamBoard(
      {super.key, required this.team, required this.tasks, this.padding = EdgeInsets.zero});

  static const _columns = [
    (TaskStage.todo, 'To Do', Color(0xFF4338CA), Color(0xFFF1F0FD)),
    (TaskStage.doing, 'In Progress', AppColors.primary, Color(0xFFEEF4FE)),
    (TaskStage.review, 'Review & Feedback', Color(0xFFB91C1C), Color(0xFFFFF3EC)),
    (TaskStage.boardDone, 'Done', Color(0xFF15803D), Color(0xFFEEF8F1)),
  ];

  static String columnOf(TaskItem t) => t.isCompleted ? TaskStage.boardDone : t.stage;

  @override
  Widget build(BuildContext context) {
    final visible = tasks.where((t) => !t.isCancelled).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    return LayoutBuilder(builder: (context, box) {
      final fits = box.maxWidth >= 900;
      final columns = [
        for (final (id, title, fg, bg) in _columns)
          _Column(
            team: team,
            id: id,
            title: title,
            fg: fg,
            bg: bg,
            tasks: visible.where((t) => columnOf(t) == id).toList(),
            touch: !fits,
          ),
      ];
      if (fits) {
        return Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, c) in columns.indexed) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: c),
              ],
            ],
          ),
        );
      }
      return ListView(
        scrollDirection: Axis.horizontal,
        padding: padding.add(const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
        children: [
          for (final (i, c) in columns.indexed) ...[
            if (i > 0) const SizedBox(width: 12),
            SizedBox(width: (box.maxWidth * 0.8).clamp(240.0, 300.0), child: c),
          ],
        ],
      );
    });
  }
}

class _Column extends StatelessWidget {
  final Team team;
  final String id;
  final String title;
  final Color fg;
  final Color bg;
  final List<TaskItem> tasks;
  final bool touch;
  const _Column({
    required this.team,
    required this.id,
    required this.title,
    required this.fg,
    required this.bg,
    required this.tasks,
    required this.touch,
  });

  bool get _canAdd => id != TaskStage.boardDone && TeamStore.instance.canCreateTask(team);

  void _add(BuildContext context) => showCreateTask(context, team: team, stage: id);

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    return DragTarget<TaskItem>(
      onWillAcceptWithDetails: (d) => TeamBoard.columnOf(d.data) != id,
      onAcceptWithDetails: (d) => store.moveTo(team, d.data, id),
      builder: (context, candidate, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: candidate.isNotEmpty ? fg.withAlpha(140) : Colors.transparent, width: 2),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 0, 10),
              child: Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(TextSpan(children: [
                        TextSpan(
                            text: title,
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: fg)),
                        TextSpan(
                            text: '  (${tasks.length})',
                            style: const TextStyle(fontSize: 16, color: Color(0xFF4B5563))),
                      ])),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (_canAdd)
                    Tooltip(
                      message: 'Add task to $title',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _add(context),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.add_rounded, color: fg, size: 22),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final t in tasks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _draggable(context, t),
                    ),
                  if (tasks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                          id == TaskStage.boardDone ? 'Finished tasks land here.' : 'No tasks.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ),
                  if (_canAdd)
                    Material(
                      color: Colors.white.withAlpha(150),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _add(context),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded, color: AppColors.primary),
                              SizedBox(width: 10),
                              Text('Add task',
                                  style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _draggable(BuildContext context, TaskItem t) {
    final card = _Card(team: team, task: t);
    if (!TeamStore.instance.canComplete(team, t)) return card;
    final feedback = Material(
      color: Colors.transparent,
      child: SizedBox(width: 260, child: Opacity(opacity: 0.92, child: card)),
    );
    final ghost = Opacity(opacity: 0.35, child: card);
    return touch
        ? LongPressDraggable<TaskItem>(
            data: t, feedback: feedback, childWhenDragging: ghost, child: card)
        : Draggable<TaskItem>(data: t, feedback: feedback, childWhenDragging: ghost, child: card);
  }
}

/// "Assigned to you" label on my tasks in a team.
class AssignedToYouChip extends StatelessWidget {
  const AssignedToYouChip({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration:
            BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.account_circle_rounded, size: 14, color: AppColors.primary),
          SizedBox(width: 4),
          Text('Assigned to you',
              style:
                  TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _Card extends StatelessWidget {
  final Team team;
  final TaskItem task;
  const _Card({required this.team, required this.task});

  @override
  Widget build(BuildContext context) {
    final t = task;
    final ref = TaskRef(t, team);
    final now = DateTime.now();
    final (Color dueFg, Color dueBg) = t.isCompleted
        ? (AppColors.success, AppColors.successLight)
        : (t.isOverdue || isSameDay(t.startAt, now))
            ? (AppColors.danger, AppColors.dangerLight)
            : (const Color(0xFFEA7A0C), const Color(0xFFFFF0DF));
    final dueText = isSameDay(t.startAt, now)
        ? 'Today'
        : DateFormat(t.startAt.year == now.year ? 'd MMM' : 'd MMM yy').format(t.startAt);
    final assignee = t.assigneeId == null ? null : team.nameOf(t.assigneeId);
    const muted = TextStyle(fontSize: 13.5, color: Color(0xFF4B5563));
    final mine = t.assigneeId != null && t.assigneeId == TeamStore.instance.uid;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openTaskRef(context, ref),
        // My tasks: a blue bar on the left and "Assigned to you".
        child: Container(
          decoration: mine
              ? const BoxDecoration(
                  border: Border(left: BorderSide(color: AppColors.primary, width: 4)))
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(t.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              decoration: t.isCompleted ? TextDecoration.lineThrough : null,
                              color: t.isCompleted ? AppColors.textMuted : AppColors.text,
                            )),
                      ),
                    ),
                    SizedBox(width: 36, height: 34, child: TaskActionsMenu(ref: ref)),
                  ],
                ),
                if (mine) ...[
                  const SizedBox(height: 6),
                  const AssignedToYouChip(),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration:
                          BoxDecoration(color: dueBg, borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.calendar_today_outlined, size: 14, color: dueFg),
                        const SizedBox(width: 6),
                        Text(dueText,
                            style: TextStyle(
                                color: dueFg, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    PriorityChip(priority: t.priority),
                  ],
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Row(
                    children: [
                      if (t.checklist.isNotEmpty) ...[
                        const Icon(Icons.check_box_outlined, size: 18, color: Color(0xFF6B7280)),
                        const SizedBox(width: 4),
                        Text('${t.checklistDone}/${t.checklist.length}', style: muted),
                        const SizedBox(width: 12),
                      ],
                      if (t.links.isNotEmpty) ...[
                        const Icon(Icons.link_rounded, size: 18, color: Color(0xFF6B7280)),
                        const SizedBox(width: 4),
                        Text('${t.links.length}', style: muted),
                        const SizedBox(width: 12),
                      ],
                      if (t.timerRunning)
                        const Icon(Icons.timer_rounded, size: 18, color: AppColors.primary),
                      const Spacer(),
                      if (assignee != null)
                        Tooltip(
                          message: assignee,
                          child: Avatar(
                              name: assignee,
                              size: 32,
                              color: t.assigneeId == TeamStore.instance.uid
                                  ? AppColors.primary
                                  : AppColors.purple),
                        )
                      else
                        const Tooltip(
                          message: 'Not assigned',
                          child:
                              Icon(Icons.person_off_outlined, size: 20, color: AppColors.textMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
