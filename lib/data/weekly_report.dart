import 'package:intl/intl.dart';

import '../core/utils.dart';
import 'models.dart';
import 'team_models.dart';
import 'team_stats.dart';

/// One person's line in the weekly report.
class ReportMember {
  final String uid;
  final String name;
  int done = 0;
  int late = 0;

  /// Time tracked during the week.
  Duration time = Duration.zero;

  ReportMember(this.uid, this.name);
}

/// What a team did in one week (Monday 00:00 to next Monday 00:00).
class WeeklyReport {
  final Team team;
  final DateTime start;
  final DateTime end;

  /// Finished during the week.
  final List<TaskItem> done;

  /// Due before the end of the week (or now, for the current week) and not
  /// finished by then.
  final List<TaskItem> late;

  /// Due during the week (finished or not).
  final int dueThisWeek;

  /// Most done first.
  final List<ReportMember> members;

  /// Time everyone tracked during the week.
  final Duration totalTime;

  WeeklyReport._(this.team, this.start, this.end, this.done, this.late, this.dueThisWeek,
      this.members, this.totalTime);

  /// [weeksBack] = 0 for this week, 1 for last week, ...
  factory WeeklyReport.compute(Team team, Iterable<TaskItem> tasks, DateTime now,
      {int weeksBack = 0}) {
    final thisMonday = TeamStats.weekStart(now);
    final start = DateTime(thisMonday.year, thisMonday.month, thisMonday.day - 7 * weeksBack);
    final end = DateTime(start.year, start.month, start.day + 7);
    final cutoff = now.isBefore(end) ? now : end;

    final byMember = {for (final uid in team.memberIds) uid: ReportMember(uid, team.nameOf(uid))};
    final done = <TaskItem>[];
    final late = <TaskItem>[];
    var due = 0;

    var totalTime = Duration.zero;
    for (final t in tasks) {
      // Work sessions count even if the task was cancelled later; a session
      // belongs to the week it ended in.
      for (final e in t.timeLog) {
        if (!e.end.isBefore(start) && e.end.isBefore(end)) {
          totalTime += e.duration;
          final m = byMember[e.by];
          if (m != null) m.time += e.duration;
        }
      }
      if (t.isCancelled) continue;
      final dueAt = t.endAt ?? t.startAt;
      final finished = t.isCompleted ? t.completedAt : null;
      final m = byMember[t.assigneeId];

      if (!dueAt.isBefore(start) && dueAt.isBefore(end)) due++;
      if (finished != null && !finished.isBefore(start) && finished.isBefore(end)) {
        done.add(t);
        m?.done++;
      }
      final finishedInTime = finished != null && finished.isBefore(cutoff);
      if (dueAt.isBefore(cutoff) && !finishedInTime && t.createdAt.isBefore(cutoff)) {
        late.add(t);
        m?.late++;
      }
    }
    done.sort((a, b) => a.completedAt!.compareTo(b.completedAt!));
    late.sort((a, b) => (a.endAt ?? a.startAt).compareTo(b.endAt ?? b.startAt));
    final members = byMember.values.toList()
      ..sort((a, b) {
        final d = b.done.compareTo(a.done);
        if (d != 0) return d;
        final l = a.late.compareTo(b.late);
        if (l != 0) return l;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return WeeklyReport._(team, start, end, done, late, due, members, totalTime);
  }

  /// "13 – 19 Apr 2026"
  String get rangeLabel {
    final last = end.subtract(const Duration(days: 1));
    final sameMonth = start.month == last.month && start.year == last.year;
    final from = DateFormat(sameMonth ? 'd' : 'd MMM').format(start);
    return '$from – ${DateFormat('d MMM yyyy').format(last)}';
  }

  String assigneeName(TaskItem t) =>
      t.assigneeId == null ? 'unassigned' : team.nameOf(t.assigneeId);

  /// Plain text for WhatsApp etc. Long lists are cut to [maxItems].
  String toText({int maxItems = 15}) {
    final b = StringBuffer()
      ..writeln('📊 *${team.name}* — weekly report')
      ..writeln(rangeLabel)
      ..writeln()
      ..writeln('✅ Done: ${done.length}   ⏰ Late: ${late.length}   📋 Due this week: $dueThisWeek'
          '${totalTime > Duration.zero ? '   ⏱ Time: ${formatDuration(totalTime)}' : ''}')
      ..writeln();
    for (final m in members) {
      b.writeln('👤 ${m.name}: ${m.done} done${m.late > 0 ? ', ${m.late} late' : ''}'
          '${m.time > Duration.zero ? ', ${formatDuration(m.time)}' : ''}');
    }
    void list(String title, List<TaskItem> items, String Function(TaskItem) line) {
      if (items.isEmpty) return;
      b
        ..writeln()
        ..writeln(title);
      for (final t in items.take(maxItems)) {
        b.writeln('• ${line(t)}');
      }
      if (items.length > maxItems) b.writeln('…and ${items.length - maxItems} more');
    }

    list('✅ *Done*', done, (t) => '${t.title} (${assigneeName(t)})');
    list(
        '⏰ *Late*',
        late,
        (t) =>
            '${t.title} (${assigneeName(t)}) — due ${DateFormat('EEE d MMM').format(t.endAt ?? t.startAt)}');
    b
      ..writeln()
      ..write('— TaskFlow');
    return b.toString();
  }
}
