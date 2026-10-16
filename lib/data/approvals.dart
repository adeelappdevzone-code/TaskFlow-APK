import 'models.dart';
import 'team_models.dart';

// Approvals inside a team: the assignee sends the task for review (it moves
// to Review & Feedback), an owner/manager approves it (done) or asks for
// changes (back to In Progress). Everything is read from the task history.

/// Sent for approval: the "Send for approval" button, or dragged to Review.
bool isSubmission(TaskEvent e) =>
    e.kind == HistoryKind.submitted || (e.kind == HistoryKind.stage && e.to == TaskStage.review);

bool isDecision(TaskEvent e) => e.kind == HistoryKind.approved || e.kind == HistoryKind.changes;

bool isApprovalEvent(TaskEvent e) => isSubmission(e) || isDecision(e);

enum ApprovalState { pending, changes, approved }

/// Where the task is in the approval flow, or null when it never was in it.
ApprovalState? approvalStateOf(TaskItem t) {
  if (t.isCancelled) return null;
  if (t.status == TaskStatus.pending && t.stage == TaskStage.review) return ApprovalState.pending;
  TaskEvent? last;
  for (final e in t.history) {
    if (isApprovalEvent(e)) last = e;
  }
  if (last == null) return null;
  if (last.kind == HistoryKind.approved && t.isCompleted) return ApprovalState.approved;
  if (last.kind == HistoryKind.changes && t.status == TaskStatus.pending) {
    return ApprovalState.changes;
  }
  return null;
}

/// The approval lines of a task, oldest first.
List<TaskEvent> approvalTimeline(TaskItem t) => t.history.where(isApprovalEvent).toList();

/// The latest "sent for approval" line (its note is the cover message).
TaskEvent? lastSubmission(TaskItem t) {
  TaskEvent? last;
  for (final e in t.history) {
    if (isSubmission(e)) last = e;
  }
  return last;
}

/// One task in the Approval Center.
class ApprovalItem {
  final Team team;
  final TaskItem task;
  final ApprovalState state;
  const ApprovalItem(this.team, this.task, this.state);

  TaskEvent? get submission => lastSubmission(task);

  /// 1 for the first submission, 2 after one round of changes...
  int get round => task.history.where(isSubmission).length;

  /// When it last moved in the approval flow.
  DateTime get at {
    final t = approvalTimeline(task);
    return t.isEmpty ? task.updatedAt : t.last.at;
  }
}

/// Approval tasks I can see: every task in the teams I run, my own tasks in
/// the others. Newest first.
List<ApprovalItem> approvalItems(
    List<Team> teams, List<TaskItem> Function(String teamId) tasksOf, String? me) {
  final out = <ApprovalItem>[];
  if (me == null) return out;
  for (final team in teams) {
    final admin = team.isAdmin(me);
    for (final t in tasksOf(team.id)) {
      if (!admin && t.assigneeId != me) continue;
      final s = approvalStateOf(t);
      if (s != null) out.add(ApprovalItem(team, t, s));
    }
  }
  out.sort((a, b) => b.at.compareTo(a.at));
  return out;
}

/// Numbers for the summary card.
class ApprovalStats {
  /// Sent for approval (every round counts).
  final int requests;
  final int approved;
  final int changes;

  /// Waiting for a decision now.
  final int pending;

  /// From being sent to the decision, on average (null: no decisions yet).
  final Duration? averageTime;

  /// Approved by the due day, out of [approved].
  final int onTime;

  const ApprovalStats({
    this.requests = 0,
    this.approved = 0,
    this.changes = 0,
    this.pending = 0,
    this.averageTime,
    this.onTime = 0,
  });

  double? get onTimeRate => approved == 0 ? null : onTime / approved;
}

/// Counts what happened on or after [since] (everything when null).
ApprovalStats approvalStats(Iterable<TaskItem> tasks, {DateTime? since}) {
  var requests = 0, approved = 0, changes = 0, pending = 0, onTime = 0;
  var total = Duration.zero;
  var decided = 0;
  bool inRange(DateTime d) => since == null || !d.isBefore(since);
  for (final t in tasks) {
    if (t.status == TaskStatus.pending && t.stage == TaskStage.review) pending++;
    DateTime? sentAt;
    for (final e in t.history) {
      if (isSubmission(e)) {
        sentAt = e.at;
        if (inRange(e.at)) requests++;
      } else if (isDecision(e)) {
        if (inRange(e.at)) {
          if (e.kind == HistoryKind.approved) {
            approved++;
            final due = t.endAt ?? t.startAt;
            final dueEnd = DateTime(due.year, due.month, due.day).add(const Duration(days: 1));
            if (e.at.isBefore(dueEnd)) onTime++;
          } else {
            changes++;
          }
          if (sentAt != null && !e.at.isBefore(sentAt)) {
            total += e.at.difference(sentAt);
            decided++;
          }
        }
        sentAt = null;
      }
    }
  }
  return ApprovalStats(
    requests: requests,
    approved: approved,
    changes: changes,
    pending: pending,
    averageTime: decided == 0 ? null : Duration(seconds: total.inSeconds ~/ decided),
    onTime: onTime,
  );
}

/// "1.8 days", "5 h", "20 min".
String approvalTimeText(Duration? d) {
  if (d == null) return '—';
  if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)} min';
  if (d.inHours < 24) return '${d.inHours} h';
  final days = d.inMinutes / (60 * 24);
  return '${days.toStringAsFixed(1)} days';
}

/// Feedback with numbered points, as one text (stored on the history line
/// and posted as a comment).
String feedbackText(String message, List<String> points) {
  final p = points.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  return [
    if (message.trim().isNotEmpty) message.trim(),
    for (final (i, s) in p.indexed) '${i + 1}. $s',
  ].join('\n');
}
