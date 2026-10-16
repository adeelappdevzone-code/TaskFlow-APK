import 'dart:math' show max;

import '../core/utils.dart';
import 'app_store.dart';
import 'models.dart';
import 'task_repository.dart';
import 'team_models.dart';
import 'team_store.dart';

// Reports Center: numbers for a date range over every task I can see
// (personal tasks and my teams' tasks).

enum ReportRange { thisWeek, lastWeek, thisMonth, lastMonth, last30 }

String rangeLabel(ReportRange r) => switch (r) {
      ReportRange.thisWeek => 'This week',
      ReportRange.lastWeek => 'Last week',
      ReportRange.thisMonth => 'This month',
      ReportRange.lastMonth => 'Last month',
      ReportRange.last30 => 'Last 30 days',
    };

/// [start, end) of a preset range.
(DateTime, DateTime) rangeDates(ReportRange r, DateTime now) {
  final today = dateOnly(now);
  final monday = today.subtract(Duration(days: today.weekday - 1));
  return switch (r) {
    ReportRange.thisWeek => (monday, monday.add(const Duration(days: 7))),
    ReportRange.lastWeek => (monday.subtract(const Duration(days: 7)), monday),
    ReportRange.thisMonth => (DateTime(now.year, now.month), DateTime(now.year, now.month + 1)),
    ReportRange.lastMonth => (DateTime(now.year, now.month - 1), DateTime(now.year, now.month)),
    ReportRange.last30 => (
        today.subtract(const Duration(days: 29)),
        today.add(const Duration(days: 1))
      ),
  };
}

/// Every task I can see (not cancelled).
List<TaskRef> reportTasks() => [
      for (final t in AppStore.instance.tasks)
        if (!t.isCancelled) TaskRef(t),
      for (final team in TeamStore.instance.teams)
        for (final t in TeamStore.instance.tasksOf(team.id))
          if (!t.isCancelled) TaskRef(t, team),
    ];

class TaskNumbers {
  final int total;
  final int completed;
  final int overdue;
  final int inProgress;
  const TaskNumbers(this.total, this.completed, this.overdue, this.inProgress);

  double get rate => total == 0 ? 0 : completed / total;
}

/// Tasks due in the range: how many, done, late, being worked on.
TaskNumbers numbersOf(Iterable<TaskItem> tasks, DateTime now) {
  var total = 0, done = 0, late = 0, doing = 0;
  for (final t in tasks) {
    total++;
    if (t.isCompleted) {
      done++;
    } else if ((t.endAt ?? t.startAt).isBefore(now)) {
      late++;
    } else if (t.stage != TaskStage.todo) {
      doing++;
    }
  }
  return TaskNumbers(total, done, late, doing);
}

/// Change from [before] to [now] in percent (null when there was nothing).
int? changePct(int before, int now) => before == 0 ? null : ((now - before) * 100 / before).round();

/// One person in Team Performance.
class PersonStats {
  final String uid;
  final String name;
  final String role;
  int assigned = 0, completed = 0, inProgress = 0, overdue = 0;
  PersonStats(this.uid, this.name, this.role);
  double get rate => assigned == 0 ? 0 : completed / assigned;
}

/// A day in the trend chart: created / completed so far, late at that day.
class TrendPoint {
  final DateTime day;
  final int created;
  final int completed;
  final int overdue;
  const TrendPoint(this.day, this.created, this.completed, this.overdue);
}

class ReportData {
  final DateTime start;
  final DateTime end;
  final List<TaskRef> inRange;
  final TaskNumbers numbers;
  final TaskNumbers previous;
  final List<TrendPoint> trend;

  /// (label, color, count, done) per project / team / Personal.
  final List<(String, int, int, int)> byProject;
  final List<PersonStats> people;
  final List<TaskRef> upcoming;

  const ReportData({
    required this.start,
    required this.end,
    required this.inRange,
    required this.numbers,
    required this.previous,
    required this.trend,
    required this.byProject,
    required this.people,
    required this.upcoming,
  });
}

bool _due(TaskItem t, DateTime start, DateTime end) =>
    !t.startAt.isBefore(start) && t.startAt.isBefore(end);

ReportData buildReport(List<TaskRef> all, DateTime start, DateTime end, DateTime now) {
  final inRange = all.where((r) => _due(r.task, start, end)).toList();
  final len = end.difference(start);
  final prevStart = start.subtract(len);
  final previous =
      numbersOf(all.where((r) => _due(r.task, prevStart, start)).map((r) => r.task), now);

  // Trend: one point per day up to today (about 31 points at most).
  final last = end.isAfter(now) ? dateOnly(now).add(const Duration(days: 1)) : end;
  final days = max(1, (last.difference(start).inHours / 24).ceil());
  final step = max(1, (days / 31).ceil());
  final trend = <TrendPoint>[];
  for (var i = 0; i < days; i += step) {
    final day = start.add(Duration(days: i));
    final dayEnd = day.add(const Duration(days: 1));
    var created = 0, done = 0, late = 0;
    for (final r in inRange) {
      final t = r.task;
      if (t.createdAt.isBefore(dayEnd)) created++;
      final c = t.completedAt;
      if (t.isCompleted && c != null && c.isBefore(dayEnd)) done++;
      final due = t.endAt ?? t.startAt;
      final doneBy = t.isCompleted && c != null && c.isBefore(dayEnd);
      if (due.isBefore(dayEnd) && !doneBy && due.isBefore(now)) late++;
    }
    trend.add(TrendPoint(day, created, done, late));
  }

  final projects = <String, (int, int, int)>{};
  for (final r in inRange) {
    final k = r.sourceLabel;
    final old = projects[k];
    projects[k] =
        (r.sourceColor, (old?.$2 ?? 0) + 1, (old?.$3 ?? 0) + (r.task.isCompleted ? 1 : 0));
  }
  final byProject = [for (final e in projects.entries) (e.key, e.value.$1, e.value.$2, e.value.$3)]
    ..sort((a, b) => b.$3.compareTo(a.$3));

  final people = <String, PersonStats>{};
  for (final r in inRange) {
    final team = r.team;
    final uid = r.task.assigneeId;
    if (team == null || uid == null) continue;
    final p = people.putIfAbsent(uid, () => PersonStats(uid, team.nameOf(uid), _role(team, uid)));
    p.assigned++;
    final t = r.task;
    if (t.isCompleted) {
      p.completed++;
    } else if ((t.endAt ?? t.startAt).isBefore(now)) {
      p.overdue++;
    } else if (t.stage != TaskStage.todo) {
      p.inProgress++;
    }
  }
  final peopleList = people.values.toList()
    ..sort((a, b) {
      final r = b.rate.compareTo(a.rate);
      return r != 0 ? r : b.assigned.compareTo(a.assigned);
    });

  final upcoming = all
      .where((r) => r.task.status == TaskStatus.pending && !r.task.startAt.isBefore(dateOnly(now)))
      .toList()
    ..sort((a, b) => a.task.startAt.compareTo(b.task.startAt));

  return ReportData(
    start: start,
    end: end,
    inRange: inRange,
    numbers: numbersOf(inRange.map((r) => r.task), now),
    previous: previous,
    trend: trend,
    byProject: byProject,
    people: peopleList,
    upcoming: upcoming.take(6).toList(),
  );
}

String _role(Team team, String uid) => switch (team.roleOf(uid)) {
      TeamRole.owner => 'Owner',
      TeamRole.manager => 'Manager',
      _ => 'Member',
    };
