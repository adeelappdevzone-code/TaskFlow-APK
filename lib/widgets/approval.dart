import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../data/task_repository.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import 'common.dart';

/// Waiting in Review & Feedback, not finished.
bool awaitingApproval(TaskItem t) => t.status == TaskStatus.pending && t.stage == TaskStage.review;

/// Owner/manager: send the task back to In Progress with a note.
Future<void> requestChangesDialog(BuildContext context, Team team, TaskItem task) async {
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Request changes'),
      content: SizedBox(
        width: 440,
        child: TextField(
          controller: note,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration:
              const InputDecoration(hintText: 'What should be changed? (added as a comment)'),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send back')),
      ],
    ),
  );
  if (ok != true) return;
  TeamStore.instance.requestChanges(team, task, note.text);
  if (context.mounted) showSnack(context, 'Sent back to ${team.nameOf(task.assigneeId)}');
}

void approveTask(BuildContext context, Team team, TaskItem task) {
  TeamStore.instance.approve(team, task);
  showSnack(context, 'Approved "${task.title}"');
}

/// On a team task: "Awaiting approval" with Approve / Request changes for
/// owners and managers, or "Send for approval" for the assignee.
class ApprovalBar extends StatelessWidget {
  final TaskRef ref;
  const ApprovalBar({super.key, required this.ref});

  @override
  Widget build(BuildContext context) {
    final team = ref.team;
    final t = ref.task;
    if (team == null || t.status != TaskStatus.pending) return const SizedBox.shrink();
    final store = TeamStore.instance;
    final admin = store.isAdmin(team);
    final mine = t.assigneeId != null && t.assigneeId == store.uid;

    if (awaitingApproval(t)) {
      return _box(
        color: AppColors.warning,
        bg: AppColors.warningLight,
        icon: Icons.hourglass_top_rounded,
        title: 'Awaiting approval',
        text: admin
            ? '${t.assigneeId == null ? 'This task' : team.nameOf(t.assigneeId)} sent it for review.'
            : 'A manager will approve it or ask for changes.',
        actions: admin
            ? [
                OutlinedButton(
                  onPressed: () => requestChangesDialog(context, team, t),
                  child: const Text('Request changes'),
                ),
                FilledButton.icon(
                  onPressed: () => approveTask(context, team, t),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Approve'),
                ),
              ]
            : const [],
      );
    }
    if (mine && !admin) {
      return _box(
        color: AppColors.primary,
        bg: AppColors.primaryLight,
        icon: Icons.verified_outlined,
        title: 'Finished your part?',
        text: 'Send it to your manager for review and approval.',
        actions: [
          FilledButton(
            onPressed: () {
              store.moveTo(team, t, TaskStage.review);
              showSnack(context, 'Sent for approval');
            },
            child: const Text('Send for approval'),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _box({
    required Color color,
    required Color bg,
    required IconData icon,
    required String title,
    required String text,
    required List<Widget> actions,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(70)),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, a) in actions.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    a,
                  ],
                ],
              ),
          ],
        ),
      );
}
