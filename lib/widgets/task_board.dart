import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import 'responsive.dart';

/// Kanban board: To do | In progress | Review | Done. Long-press a card and
/// drag it to another column (when [canMove] allows it). Used for team tasks
/// and personal tasks.
class KanbanBoard extends StatelessWidget {
  final List<TaskItem> tasks;
  final bool Function(TaskItem task) canMove;

  /// [column] is a [TaskStage] or [TaskStage.boardDone].
  final void Function(TaskItem task, String column) onMove;
  final void Function(BuildContext context, TaskItem task) onOpen;

  /// Shown at the right of each card (assignee, category...).
  final Widget Function(TaskItem task)? trailing;

  /// Space around the board on wide screens.
  final EdgeInsetsGeometry padding;

  const KanbanBoard({
    super.key,
    required this.tasks,
    required this.canMove,
    required this.onMove,
    required this.onOpen,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 90),
  });

  static const _columns = [TaskStage.todo, TaskStage.doing, TaskStage.review, TaskStage.boardDone];

  static String columnOf(TaskItem t) => t.isCompleted ? TaskStage.boardDone : t.stage;

  @override
  Widget build(BuildContext context) {
    final visible = tasks.where((t) => !t.isCancelled).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    List<TaskItem> inColumn(String col) => visible.where((t) => columnOf(t) == col).toList();
    return LayoutBuilder(builder: (context, box) {
      // Big screen: all four columns side by side, no sideways scrolling.
      if (box.maxWidth >= kWideLayout) {
        return Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final col in _columns)
                Expanded(child: _BoardColumn(board: this, column: col, tasks: inColumn(col))),
            ],
          ),
        );
      }
      final width = (box.maxWidth * 0.78).clamp(220.0, 320.0);
      return ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        children: [
          for (final col in _columns)
            _BoardColumn(board: this, column: col, width: width, tasks: inColumn(col)),
        ],
      );
    });
  }
}

class _BoardColumn extends StatelessWidget {
  final KanbanBoard board;
  final String column;

  /// Fixed width when scrolling sideways; null to fill the space given.
  final double? width;
  final List<TaskItem> tasks;
  const _BoardColumn({required this.board, required this.column, this.width, required this.tasks});

  (String, Color) get _style => switch (column) {
        TaskStage.doing => ('In progress', AppColors.purple),
        TaskStage.review => ('Review', AppColors.warning),
        TaskStage.boardDone => ('Done', AppColors.success),
        _ => ('To do', AppColors.textMuted),
      };

  @override
  Widget build(BuildContext context) {
    final (label, color) = _style;
    return DragTarget<TaskItem>(
      onWillAcceptWithDetails: (d) =>
          KanbanBoard.columnOf(d.data) != column && board.canMove(d.data),
      onAcceptWithDetails: (d) => board.onMove(d.data, column),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return Container(
          width: width,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: hovering ? color.withAlpha(30) : const Color(0xFFEEF1F6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: hovering ? color : Colors.transparent, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  Text('${tasks.length}', style: const TextStyle(color: AppColors.textMuted)),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Text(hovering ? 'Drop here' : 'No tasks',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                      )
                    : ListView(
                        children: [
                          for (final t in tasks)
                            board.canMove(t)
                                ? LongPressDraggable<TaskItem>(
                                    data: t,
                                    feedback: Material(
                                      color: Colors.transparent,
                                      child: SizedBox(
                                          width: (width ?? 260) - 20,
                                          child: _BoardCard(board: board, task: t, lifted: true)),
                                    ),
                                    childWhenDragging: Opacity(
                                        opacity: 0.35, child: _BoardCard(board: board, task: t)),
                                    child: _BoardCard(board: board, task: t),
                                  )
                                : _BoardCard(board: board, task: t),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BoardCard extends StatelessWidget {
  final KanbanBoard board;
  final TaskItem task;
  final bool lifted;
  const _BoardCard({required this.board, required this.task, this.lifted = false});

  @override
  Widget build(BuildContext context) {
    final overdue = task.isOverdue;
    final done = task.isCompleted;
    final time = timeRangeText(task.startAt, task.endAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: done ? const Color(0xFFF0FAF3) : Colors.white,
        elevation: lifted ? 6 : 0,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: lifted ? null : () => board.onOpen(context, task),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                      color: task.isCompleted ? AppColors.textMuted : AppColors.text,
                    )),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (done)
                      const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success)
                    else if (task.priority == Priority.high)
                      const Icon(Icons.local_fire_department_rounded,
                          size: 15, color: AppColors.danger)
                    else
                      const Icon(Icons.calendar_today_outlined,
                          size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    if (Repeat.isOn(task.repeat)) ...[
                      const Icon(Icons.repeat_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 3),
                    ],
                    Expanded(
                      child: Text(
                        '${relativeDay(task.startAt)} • $time',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: overdue && !done ? AppColors.danger : AppColors.textMuted),
                      ),
                    ),
                    if (board.trailing != null) board.trailing!(task),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
