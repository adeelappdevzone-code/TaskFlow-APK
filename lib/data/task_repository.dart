import '../core/utils.dart';
import 'app_store.dart';
import 'models.dart';
import 'team_models.dart';
import 'team_store.dart';

/// A task together with where it belongs: a team, or null for a personal
/// task. Every screen that lists "my" tasks works with these, so a task is
/// the same record wherever it is shown.
class TaskRef {
  final TaskItem task;
  final Team? team;
  const TaskRef(this.task, [this.team]);

  bool get isTeam => team != null;

  /// "UI UX" for a team task, the project name for a personal task in a
  /// project, otherwise "Personal".
  String get sourceLabel {
    final t = team;
    if (t != null) return t.name;
    return AppStore.instance.projectById(task.projectId)?.name ?? 'Personal';
  }

  /// Color for [sourceLabel].
  int get sourceColor {
    final t = team;
    if (t != null) return t.color;
    return AppStore.instance.projectById(task.projectId)?.color ?? 0xFF7C3AED;
  }

  /// I may tick it done: always for personal tasks; for team tasks the
  /// assignee or an owner/manager.
  bool get canComplete {
    final t = team;
    return t == null || TeamStore.instance.canComplete(t, task);
  }

  /// May mark it done (personal tasks; team: owner/manager or a task I made
  /// for myself).
  bool get canFinish {
    final t = team;
    return t == null || TeamStore.instance.canFinish(t, task);
  }

  /// A team task given to me by a manager: I send it for review instead of
  /// marking it done.
  bool get sendsForReview => team != null && canComplete && !canFinish;

  /// Owner/manager, or my own task (personal, or one I made for myself).
  bool get canEdit {
    final t = team;
    return t == null || TeamStore.instance.canEdit(t, task);
  }

  /// Board column: a [TaskStage] or [TaskStage.boardDone].
  void moveTo(String column) {
    final t = team;
    if (t == null) {
      AppStore.instance.moveTo(task, column);
    } else if (sendsForReview && (column == TaskStage.boardDone || column == TaskStage.review)) {
      // "Done" for a member means: send it to the manager.
      if (task.isCompleted || (task.stage == TaskStage.review)) return;
      TeamStore.instance.submitForApproval(t, task);
    } else {
      TeamStore.instance.moveTo(t, task, column);
    }
  }

  void setChecklist(List<ChecklistItem> items) {
    final t = team;
    if (t == null) {
      AppStore.instance.setChecklist(task, items);
    } else {
      TeamStore.instance.setChecklist(t, task, items);
    }
  }

  void setLinks(List<TaskLink> links) {
    final t = team;
    if (t == null) {
      AppStore.instance.setLinks(task, links);
    } else {
      TeamStore.instance.setLinks(t, task, links);
    }
  }

  void setCompleted(bool done) {
    final t = team;
    if (t == null) {
      AppStore.instance.setCompleted(task, done);
    } else {
      TeamStore.instance.setCompleted(t, task, done);
    }
  }
}

/// Tasks of the logged-in user from both places: personal tasks and team
/// tasks assigned to me (cancelled ones left out).
class TaskRepository {
  TaskRepository._();

  static List<TaskRef> myTasks() => [
        for (final t in AppStore.instance.tasks)
          if (!t.isCancelled) TaskRef(t),
        for (final (team, t) in TeamStore.instance.myTeamTasksWithTeam) TaskRef(t, team),
      ];

  /// Team tasks I gave to someone else (not cancelled).
  static List<TaskRef> assignedByMe() {
    final me = TeamStore.instance.uid;
    return [
      for (final team in TeamStore.instance.teams)
        for (final t in TeamStore.instance.tasksOf(team.id))
          if (!t.isCancelled && t.assignedBy == me && t.assigneeId != null && t.assigneeId != me)
            TaskRef(t, team),
    ];
  }

  static int _byStart(TaskRef a, TaskRef b) => a.task.startAt.compareTo(b.task.startAt);

  /// Today's tasks (by start date), earliest first.
  static List<TaskRef> today(List<TaskRef> all, DateTime now) =>
      all.where((r) => isSameDay(r.task.startAt, now)).toList()..sort(_byStart);

  /// Late tasks from before today, oldest first.
  static List<TaskRef> overdue(List<TaskRef> all, DateTime now) =>
      all.where((r) => r.task.isOverdue && !isSameDay(r.task.startAt, now)).toList()
        ..sort(_byStart);

  /// Unfinished tasks after today, soonest first.
  static List<TaskRef> upcoming(List<TaskRef> all, DateTime now, {int limit = 5}) {
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final list = all
        .where((r) => r.task.status == TaskStatus.pending && !r.task.startAt.isBefore(tomorrow))
        .toList()
      ..sort(_byStart);
    return list.length > limit ? list.sublist(0, limit) : list;
  }
}

/// Completed / in progress / pending counts for a set of tasks.
class TaskCounts {
  int done = 0;
  int inProgress = 0;
  int pending = 0;

  TaskCounts(Iterable<TaskItem> tasks) {
    for (final t in tasks) {
      switch (t.displayStatus) {
        case DisplayStatus.completed:
          done++;
        case DisplayStatus.inProgress:
          inProgress++;
        case DisplayStatus.pending:
          pending++;
        case DisplayStatus.cancelled:
          break;
      }
    }
  }

  int get total => done + inProgress + pending;
  double get progress => total == 0 ? 0 : done / total;
  int pct(int n) => total == 0 ? 0 : (n * 100 / total).round();
}
