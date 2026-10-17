import '../core/utils.dart';
import 'app_store.dart';
import 'models.dart';
import 'task_repository.dart';
import 'team_models.dart';
import 'team_store.dart';

// Time Tracking: the saved work sessions (time_log on each task) for a week,
// mine or my team's, as totals, a day-by-day timesheet and a list.

/// One saved session, with its task.
class TimeRow {
  final TaskRef ref;
  final TimeEntry entry;
  const TimeRow(this.ref, this.entry);

  int get minutes => entry.duration.inMinutes;
}

/// Every task I can see time on: personal tasks and my teams' tasks.
List<TaskRef> timeTasks() => [
      for (final t in AppStore.instance.tasks) TaskRef(t),
      for (final team in TeamStore.instance.teams)
        for (final t in TeamStore.instance.tasksOf(team.id)) TaskRef(t, team),
    ];

/// Sessions that started in [start, end): by [by] (null: anyone), newest
/// first.
List<TimeRow> timeRows(Iterable<TaskRef> refs, DateTime start, DateTime end, {String? by}) {
  final out = <TimeRow>[];
  for (final r in refs) {
    for (final e in r.task.timeLog) {
      if (by != null && e.by != by) continue;
      if (e.start.isBefore(start) || !e.start.isBefore(end)) continue;
      out.add(TimeRow(r, e));
    }
  }
  out.sort((a, b) => b.entry.start.compareTo(a.entry.start));
  return out;
}

class TimeTotals {
  final int total;
  final int billable;
  const TimeTotals(this.total, this.billable);
  int get nonBillable => total - billable;
}

TimeTotals timeTotals(Iterable<TimeRow> rows) {
  var total = 0, billable = 0;
  for (final r in rows) {
    total += r.minutes;
    if (r.entry.billable) billable += r.minutes;
  }
  return TimeTotals(total, billable);
}

/// Minutes per label (team / project / Personal), biggest first.
List<(String, int, int)> minutesBySource(Iterable<TimeRow> rows) {
  final m = <String, (int, int)>{};
  for (final r in rows) {
    final k = r.ref.sourceLabel;
    final old = m[k];
    m[k] = ((old?.$1 ?? 0) + r.minutes, r.ref.sourceColor);
  }
  return [for (final e in m.entries) (e.key, e.value.$1, e.value.$2)]
    ..sort((a, b) => b.$2.compareTo(a.$2));
}

/// Work minutes in the days of [start, end) that have started by [now]
/// (the user's work days, Monday–Friday by default, and work hours).
int workMinutesSoFar(DateTime start, DateTime end, DateTime now, int workStart, int workEnd,
    [List<int> workDays = const [1, 2, 3, 4, 5]]) {
  var total = 0;
  final perDay = (workEnd - workStart).clamp(0, 24 * 60);
  for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
    if (!workDays.contains(d.weekday) || d.isAfter(now)) continue;
    if (isSameDay(d, now)) {
      final done = now.hour * 60 + now.minute - workStart;
      total += done.clamp(0, perDay);
    } else {
      total += perDay;
    }
  }
  return total;
}

/// Timesheet: per task, minutes on each of the 7 days from [weekStart].
class SheetRow {
  final TaskRef ref;
  final List<int> days = List.filled(7, 0);
  SheetRow(this.ref);
  int get total => days.fold(0, (a, b) => a + b);
}

List<SheetRow> timesheet(Iterable<TimeRow> rows, DateTime weekStart) {
  final byTask = <String, SheetRow>{};
  for (final r in rows) {
    final i = dateOnly(r.entry.start).difference(weekStart).inDays;
    if (i < 0 || i > 6) continue;
    byTask.putIfAbsent(r.ref.task.id, () => SheetRow(r.ref)).days[i] += r.minutes;
  }
  return byTask.values.toList()..sort((a, b) => b.total.compareTo(a.total));
}

/// Monday of the week [d] is in.
DateTime weekStartOf(DateTime d) => dateOnly(d).subtract(Duration(days: d.weekday - 1));

/// "32h 15m", "45m".
String hm(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// May I change this session: mine (and the task lets me), or I run the team.
bool canEditEntry(TaskRef r, TimeEntry e) {
  final team = r.team;
  final me = TeamStore.instance.uid ?? AppStore.instance.currentUser?.id;
  if (team == null) return true;
  if (TeamStore.instance.isAdmin(team)) return true;
  return e.by == me && r.task.assigneeId == me;
}

/// Team name of [by] for a session, or "You".
String whoOf(Team? team, String by) {
  final me = TeamStore.instance.uid ?? AppStore.instance.currentUser?.id;
  if (by == me) return 'You';
  return team?.nameOf(by) ?? 'Someone';
}
