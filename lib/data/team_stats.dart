import 'models.dart';
import 'team_models.dart';

/// Numbers for one person on the team dashboard.
class MemberStats {
  final String uid;
  int pending = 0;
  int overdue = 0;
  int done = 0;
  int doneThisWeek = 0;

  MemberStats(this.uid);

  int get total => pending + done;
  double get progress => total == 0 ? 0 : done / total;
}

/// Dashboard numbers for a team (cancelled tasks are left out).
class TeamStats {
  int total = 0;
  int done = 0;
  int pending = 0;
  int overdue = 0;
  int unassigned = 0;
  int doneThisWeek = 0;

  /// One entry per current member, most open work first.
  final List<MemberStats> members;

  /// Pending tasks whose time has passed, oldest first.
  final List<TaskItem> overdueTasks;

  /// Tasks finished on each day of this week, Monday first (7 numbers).
  final List<int> doneByDay = List.filled(7, 0);

  TeamStats._(this.members, this.overdueTasks);

  double get progress => total == 0 ? 0 : done / total;

  /// "This week" = since Monday 00:00 of [now]'s week.
  static DateTime weekStart(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - DateTime.monday));
  }

  factory TeamStats.compute(Team team, Iterable<TaskItem> tasks, DateTime now) {
    final byMember = {for (final uid in team.memberIds) uid: MemberStats(uid)};
    final overdueTasks = <TaskItem>[];
    final stats = TeamStats._([], overdueTasks);
    final monday = weekStart(now);

    for (final t in tasks) {
      if (t.isCancelled) continue;
      stats.total++;
      final m = t.assigneeId == null ? null : byMember[t.assigneeId];
      if (t.assigneeId == null) stats.unassigned++;
      if (t.isCompleted) {
        stats.done++;
        m?.done++;
        final at = t.completedAt;
        if (at != null && !at.isBefore(monday)) {
          stats.doneThisWeek++;
          m?.doneThisWeek++;
          final day = DateTime(at.year, at.month, at.day).difference(monday).inDays;
          if (day >= 0 && day < 7) stats.doneByDay[day]++;
        }
      } else {
        stats.pending++;
        m?.pending++;
        final due = t.endAt ?? t.startAt;
        if (due.isBefore(now)) {
          stats.overdue++;
          m?.overdue++;
          overdueTasks.add(t);
        }
      }
    }
    overdueTasks.sort((a, b) => (a.endAt ?? a.startAt).compareTo(b.endAt ?? b.startAt));
    stats.members
      ..addAll(byMember.values)
      ..sort((a, b) {
        final o = b.overdue.compareTo(a.overdue);
        if (o != 0) return o;
        final p = b.pending.compareTo(a.pending);
        if (p != 0) return p;
        return team.nameOf(a.uid).toLowerCase().compareTo(team.nameOf(b.uid).toLowerCase());
      });
    return stats;
  }
}
