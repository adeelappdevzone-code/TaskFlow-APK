import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../data/task_repository.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../data/approvals.dart';
import '../screens/approvals_screen.dart';
import 'common.dart';

/// Waiting in Review & Feedback, not finished.
bool awaitingApproval(TaskItem t) => t.status == TaskStatus.pending && t.stage == TaskStage.review;

void approveTask(BuildContext context, Team team, TaskItem task) {
  TeamStore.instance.approve(team, task);
  showSnack(context, 'Approved "${task.title}"');
}

/// The latest reason given for a date change request.
String? moveReason(TaskItem t) {
  for (final e in t.history.reversed) {
    if (e.kind == HistoryKind.moveAsked) return e.note;
  }
  return null;
}

String _day(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${w[d.weekday - 1]} ${d.day} ${m[d.month - 1]}';
}

void approveMove(BuildContext context, Team team, TaskItem task) {
  final to = task.moveAskedTo;
  TeamStore.instance.answerMove(team, task, true);
  if (to != null) showSnack(context, '"${task.title}" moved to ${_day(to)}');
}

/// Owner/manager: say no to a date change, with an optional message.
Future<void> declineMove(BuildContext context, Team team, TaskItem task) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Keep the date?'),
      content: TextField(
        controller: c,
        maxLines: 3,
        maxLength: 300,
        decoration: const InputDecoration(
            hintText: 'Optional: why it has to stay (e.g. the client needs it today)',
            border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Keep date')),
      ],
    ),
  );
  if (ok == true) TeamStore.instance.answerMove(team, task, false, note: c.text);
}

/// On a team task: a date change request (Approve / Keep date for
/// owners and managers; waiting, with Cancel, for the assignee).
class MoveRequestBar extends StatelessWidget {
  final TaskRef ref;
  const MoveRequestBar({super.key, required this.ref});

  @override
  Widget build(BuildContext context) {
    final team = ref.team;
    final t = ref.task;
    final to = t.moveAskedTo;
    if (team == null || to == null || t.status != TaskStatus.pending) {
      return const SizedBox.shrink();
    }
    final store = TeamStore.instance;
    final admin = store.isAdmin(team);
    final mine = t.assigneeId == store.uid;
    if (!admin && !mine) return const SizedBox.shrink();
    final why = moveReason(t);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.purpleLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.purple.withAlpha(70)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.event_repeat_rounded, color: AppColors.purple),
            const SizedBox(width: 10),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    admin && !mine
                        ? '${team.nameOf(t.assigneeId)} asked to move this to ${_day(to)}'
                        : 'You asked to move this to ${_day(to)}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                    why != null && why.isNotEmpty
                        ? '"$why"'
                        : (admin && !mine
                            ? 'They are overloaded that day.'
                            : 'Waiting for a manager.'),
                    style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ]),
            ),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (admin) ...[
              OutlinedButton(
                  onPressed: () => declineMove(context, team, t), child: const Text('Keep date')),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: () => approveMove(context, team, t),
                  child: Text('Move to ${_day(to)}')),
            ] else
              TextButton(
                  onPressed: () => store.cancelMove(team, t), child: const Text('Cancel request')),
          ]),
        ],
      ),
    );
  }
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
    if (team == null || t.isCancelled) return const SizedBox.shrink();
    final store = TeamStore.instance;
    final admin = store.isAdmin(team);
    final mine = t.assigneeId != null && t.assigneeId == store.uid;
    final state = approvalStateOf(t);
    final history = TextButton(
      onPressed: () => openApprovalHistory(context, team, t),
      child: const Text('History'),
    );

    switch (state) {
      case ApprovalState.pending:
        return _box(
          color: AppColors.warning,
          bg: AppColors.warningLight,
          icon: Icons.hourglass_top_rounded,
          title: 'Awaiting approval',
          text: admin
              ? '${t.assigneeId == null ? 'This task' : team.nameOf(t.assigneeId)} sent it for review.'
              : 'A manager will approve it or ask for changes.',
          actions: [
            history,
            if (admin) ...[
              OutlinedButton(
                onPressed: () => openRequestChanges(context, team, t),
                child: const Text('Request changes'),
              ),
              FilledButton(
                onPressed: () => openReview(context, team, t),
                child: const Text('Review'),
              ),
            ],
          ],
        );
      case ApprovalState.approved:
        return _box(
          color: AppColors.success,
          bg: AppColors.successLight,
          icon: Icons.verified_rounded,
          title: 'Approved',
          text: 'This work was reviewed and approved.',
          actions: [history],
        );
      case ApprovalState.changes:
        if (!mine && !admin) return const SizedBox.shrink();
        return _box(
          color: AppColors.danger,
          bg: AppColors.dangerLight,
          icon: Icons.replay_rounded,
          title: 'Changes requested',
          text: mine ? 'Make the changes, then send a new version.' : 'Waiting for a new version.',
          actions: [
            history,
            if (mine)
              FilledButton(
                onPressed: () => sendForApprovalDialog(context, team, t),
                child: const Text('Send new version'),
              ),
          ],
        );
      case null:
        if (!mine || admin || t.status != TaskStatus.pending) return const SizedBox.shrink();
        return _box(
          color: AppColors.primary,
          bg: AppColors.primaryLight,
          icon: Icons.verified_outlined,
          title: 'Finished your part?',
          text: 'Send it to your manager for review and approval.',
          actions: [
            FilledButton(
              onPressed: () => sendForApprovalDialog(context, team, t),
              child: const Text('Send for approval'),
            ),
          ],
        );
    }
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
