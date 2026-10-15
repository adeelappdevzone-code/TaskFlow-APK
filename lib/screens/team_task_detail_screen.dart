import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import 'task_form_screen.dart';

void openTeamTask(BuildContext context, Team team, TaskItem task) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => TeamTaskDetailScreen(teamId: team.id, taskId: task.id)),
  );
}

/// A team task. Owner/managers can edit, cancel and delete it; the person it
/// is assigned to can tick the checklist and mark it done.
class TeamTaskDetailScreen extends StatelessWidget {
  final String teamId;
  final String taskId;
  const TeamTaskDetailScreen({super.key, required this.teamId, required this.taskId});

  Future<void> _onMenu(BuildContext context, String action, Team team, TaskItem task) async {
    final store = TeamStore.instance;
    switch (action) {
      case 'edit':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => TaskFormScreen(task: task, team: team)));
        break;
      case 'cancel':
        final ok = await confirmDialog(context,
            title: 'Cancel task?',
            message: 'The task will be marked as cancelled for everyone. You can restore it later.',
            confirmLabel: 'Cancel task',
            danger: true);
        if (ok) store.cancelTask(team, task);
        break;
      case 'restore':
        store.cancelTask(team, task, restore: true);
        break;
      case 'delete':
        final ok = await confirmDialog(context,
            title: 'Delete task?',
            message: 'This task will be deleted for everyone in ${team.name}.',
            confirmLabel: 'Delete',
            danger: true);
        if (ok) {
          store.deleteTask(team, task);
          if (context.mounted) Navigator.pop(context);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final team = store.teamById(teamId);
        final task = team == null ? null : store.taskById(teamId, taskId);
        if (team == null || task == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.delete_outline_rounded,
              title: 'Task not found',
              subtitle: 'It may have been deleted.',
            ),
          );
        }
        final admin = store.isAdmin(team);
        final canComplete = store.canComplete(team, task);
        final priorityColor = switch (task.priority) {
          Priority.low => AppColors.success,
          Priority.medium => AppColors.primary,
          Priority.high => AppColors.danger,
        };
        final timeText = task.endAt == null
            ? formatTime(task.startAt)
            : '${formatTime(task.startAt)} - ${formatTime(task.endAt!)}';

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            title: Text(team.name, style: const TextStyle(fontSize: 15)),
            actions: [
              if (admin)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (a) => _onMenu(context, a, team, task),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit / reassign')),
                    if (task.isCancelled)
                      const PopupMenuItem(value: 'restore', child: Text('Restore task'))
                    else
                      const PopupMenuItem(value: 'cancel', child: Text('Cancel task')),
                    const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete', style: TextStyle(color: AppColors.danger))),
                  ],
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(task.title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    decoration: task.isCancelled ? TextDecoration.lineThrough : null,
                  )),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [_statusChip(task)]),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(task.description,
                    style: const TextStyle(color: Color(0xFF374151), fontSize: 14.5, height: 1.5)),
              ],
              const SizedBox(height: 20),
              _InfoRow(
                icon: Icons.calendar_today_outlined,
                child: Text('${formatFullDate(task.startAt)}  •  $timeText',
                    style: const TextStyle(fontSize: 14)),
              ),
              _InfoRow(
                icon: Icons.local_fire_department_rounded,
                iconColor: priorityColor,
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Priority: ', style: TextStyle(fontSize: 14)),
                  TextSpan(
                      text: task.priority.label,
                      style: TextStyle(
                          fontSize: 14, color: priorityColor, fontWeight: FontWeight.w700)),
                ])),
              ),
              _person('Assigned to',
                  task.assigneeId == null ? 'Nobody yet' : team.nameOf(task.assigneeId)),
              if (task.assignedBy != null) _person('Assigned by', team.nameOf(task.assignedBy)),
              if (task.isCompleted && task.completedAt != null)
                _InfoRow(
                  icon: Icons.check_circle_rounded,
                  iconColor: AppColors.success,
                  child: Text(
                      'Completed ${relativeDay(task.completedAt!)} at ${formatTime(task.completedAt!)}',
                      style: const TextStyle(fontSize: 14)),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Text('Checklist',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  if (task.checklist.isNotEmpty)
                    Text('${task.checklistDone}/${task.checklist.length} done',
                        style: const TextStyle(
                            color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              if (task.checklist.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No checklist items.', style: TextStyle(color: AppColors.textMuted)),
                )
              else
                for (final c in task.checklist)
                  Row(
                    children: [
                      Checkbox(
                        value: c.isDone,
                        onChanged: canComplete && !task.isCancelled
                            ? (_) => store.toggleChecklistItem(team, task, c)
                            : null,
                      ),
                      Expanded(
                        child: Text(c.title,
                            style: TextStyle(
                              fontSize: 14,
                              color: c.isDone ? AppColors.textMuted : AppColors.text,
                              decoration: c.isDone ? TextDecoration.lineThrough : null,
                            )),
                      ),
                    ],
                  ),
            ],
          ),
          bottomNavigationBar: task.isCancelled || !canComplete
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: task.isCompleted
                        ? PrimaryButton(
                            label: 'Mark as not done',
                            icon: Icons.undo_rounded,
                            color: AppColors.textMuted,
                            onPressed: () => store.setCompleted(team, task, false),
                          )
                        : PrimaryButton(
                            label: 'Mark as Done',
                            icon: Icons.check_rounded,
                            onPressed: () async {
                              final open = task.checklist.length - task.checklistDone;
                              if (open > 0) {
                                final ok = await confirmDialog(context,
                                    title: 'Finish task?',
                                    message:
                                        '$open checklist item(s) are still open. Mark the task as done anyway?',
                                    confirmLabel: 'Mark done');
                                if (!ok) return;
                              }
                              store.setCompleted(team, task, true);
                            },
                          ),
                  ),
                ),
        );
      },
    );
  }

  Widget _person(String label, String name) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Avatar(name: name, size: 36),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                Text(name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      );

  Widget _statusChip(TaskItem t) => switch (t.displayStatus) {
        DisplayStatus.completed => const TagChip(label: 'Completed', color: AppColors.success),
        DisplayStatus.inProgress => const TagChip(label: 'In progress', color: AppColors.purple),
        DisplayStatus.cancelled => const TagChip(label: 'Cancelled', color: AppColors.danger),
        DisplayStatus.pending => t.isOverdue
            ? const TagChip(label: 'Overdue', color: AppColors.danger)
            : const TagChip(label: 'Pending', color: AppColors.warning),
      };
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final Widget child;
  const _InfoRow({required this.icon, required this.child, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor ?? AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}
