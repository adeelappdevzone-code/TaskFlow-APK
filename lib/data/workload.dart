import '../core/utils.dart';
import 'models.dart';
import 'planner.dart' show taskMinutes;
import 'task_repository.dart';
import 'team_models.dart';

// Team Workload: open work per person (from estimates) against their
// capacity (the team's hours per week), for a week or a month.

enum WorkloadPeriod { thisWeek, nextWeek, thisMonth }

String periodLabel(WorkloadPeriod p) => switch (p) {
      WorkloadPeriod.thisWeek => 'This Week',
      WorkloadPeriod.nextWeek => 'Next Week',
      WorkloadPeriod.thisMonth => 'This Month',
    };

/// [start, end) of the period; weeks start on Monday.
(DateTime, DateTime) periodRange(WorkloadPeriod p, DateTime now) {
  final today = dateOnly(now);
  final monday = today.subtract(Duration(days: today.weekday - 1));
  return switch (p) {
    WorkloadPeriod.thisWeek => (monday, monday.add(const Duration(days: 7))),
    WorkloadPeriod.nextWeek => (
        monday.add(const Duration(days: 7)),
        monday.add(const Duration(days: 14))
      ),
    WorkloadPeriod.thisMonth => (DateTime(now.year, now.month), DateTime(now.year, now.month + 1)),
  };
}

/// Monday–Friday days in [start, end).
int workDays(DateTime start, DateTime end) {
  var n = 0;
  for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
    if (d.weekday <= 5) n++;
  }
  return n;
}

class MemberLoad {
  final String uid;
  final String name;
  final String role;
  final List<String> teamIds = [];
  final List<TaskRef> open = [];
  int doneCount = 0;
  int minutes = 0;
  int capacityMinutes = 0;
  int unestimated = 0;

  MemberLoad(this.uid, this.name, this.role);

  int get overdueCount => open.where((r) => r.task.isOverdue).length;

  /// Work / capacity (1.0 = full).
  double get ratio => capacityMinutes == 0 ? 0 : minutes / capacityMinutes;
}

/// A suggestion to even out the load: give [task] from [from] to [to].
class Rebalance {
  final MemberLoad from;
  final MemberLoad to;
  final TaskRef task;
  const Rebalance(this.from, this.to, this.task);
}

class WorkloadReport {
  final List<MemberLoad> members;
  final List<TaskRef> unassigned;
  final DateTime start;
  final DateTime end;
  const WorkloadReport(this.members, this.unassigned, this.start, this.end);

  int get openTasks => members.fold(0, (s, m) => s + m.open.length);
  int get totalMinutes => members.fold(0, (s, m) => s + m.minutes);
  int get capacityMinutes => members.fold(0, (s, m) => s + m.capacityMinutes);
  double get averageRatio => capacityMinutes == 0 ? 0 : totalMinutes / capacityMinutes;
  List<MemberLoad> get overloaded => members.where((m) => m.ratio > 1).toList();

  /// For each overloaded person, one task to hand to the least busy person in
  /// a shared team (only to someone under 80%, and only if it fits there).
  List<Rebalance> rebalances() {
    final out = <Rebalance>[];
    final extra = <String, int>{};
    for (final m in overloaded..sort((a, b) => b.ratio.compareTo(a.ratio))) {
      final tasks = [...m.open]..sort((a, b) {
          final p = a.task.priority.index.compareTo(b.task.priority.index);
          return p != 0 ? p : taskMinutes(a.task).$1.compareTo(taskMinutes(b.task).$1);
        });
      Rebalance? best;
      for (final r in tasks) {
        final team = r.team;
        if (team == null) continue;
        final mins = taskMinutes(r.task).$1;
        for (final other in members) {
          if (other.uid == m.uid || !team.memberIds.contains(other.uid)) continue;
          final after = other.minutes + (extra[other.uid] ?? 0) + mins;
          if (other.capacityMinutes == 0 || other.ratio >= 0.8) continue;
          if (after > other.capacityMinutes) continue;
          if (best == null || other.ratio < best.to.ratio) best = Rebalance(m, other, r);
        }
        if (best != null) break;
      }
      if (best != null) {
        out.add(best);
        extra[best.to.uid] = (extra[best.to.uid] ?? 0) + taskMinutes(best.task.task).$1;
      }
    }
    return out;
  }
}

String _roleName(TeamRole? r) => switch (r) {
      TeamRole.owner => 'Owner',
      TeamRole.manager => 'Manager',
      _ => 'Member',
    };

/// Load per person across [teams] for [period]. Open tasks due in the period
/// count, and (this week / this month) open tasks already late.
WorkloadReport buildWorkload(List<Team> teams, List<TaskItem> Function(String teamId) tasksOf,
    WorkloadPeriod period, DateTime now) {
  final (start, end) = periodRange(period, now);
  final includeLate = period != WorkloadPeriod.nextWeek;
  final days = workDays(start, end);
  final byUid = <String, MemberLoad>{};
  final unassigned = <TaskRef>[];

  for (final team in teams) {
    for (final uid in team.sortedMemberIds) {
      final m = byUid.putIfAbsent(
          uid, () => MemberLoad(uid, team.nameOf(uid), _roleName(team.roleOf(uid))));
      m.teamIds.add(team.id);
      // Their own work week when they set it, else the team's hours.
      final week = team.members[uid]?.weekMinutes ?? team.weekHours * 60;
      final cap = week * days ~/ 5;
      if (cap > m.capacityMinutes) m.capacityMinutes = cap;
    }
    for (final t in tasksOf(team.id)) {
      if (t.isCancelled) continue;
      final inRange = !t.startAt.isBefore(start) && t.startAt.isBefore(end);
      final late = includeLate && t.status == TaskStatus.pending && t.startAt.isBefore(start);
      if (!inRange && !late) continue;
      final ref = TaskRef(t, team);
      final m = t.assigneeId == null ? null : byUid[t.assigneeId];
      if (m == null) {
        if (t.status == TaskStatus.pending && t.assigneeId == null) unassigned.add(ref);
        continue;
      }
      if (t.isCompleted) {
        if (inRange) m.doneCount++;
        continue;
      }
      final (mins, unest) = taskMinutes(t);
      m.open.add(ref);
      m.minutes += mins;
      if (unest) m.unestimated++;
    }
  }
  final members = byUid.values.toList()..sort((a, b) => b.ratio.compareTo(a.ratio));
  return WorkloadReport(members, unassigned, start, end);
}
