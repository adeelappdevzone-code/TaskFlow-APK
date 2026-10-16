import 'dart:math' show max, min;

import '../core/utils.dart';
import 'models.dart';
import 'task_repository.dart';

// Daily planner / rescue: how much work is planned for a day against the
// time available in the work day, and a plan to fix an overloaded day
// (move flexible low-priority work to tomorrow, bring overdue work in, give
// every flexible task a time slot).

/// Minutes a task takes when it has no estimate and no times.
const kDefaultTaskMinutes = 30;

/// What a row in the plan says.
enum PlanMark { noChange, overloaded, overdue, rescheduled, focus, moved, scheduled }

class PlanEntry {
  final TaskRef ref;
  final DateTime start;
  final DateTime end;
  final PlanMark mark;

  /// Has a set time (a meeting / appointment); the plan does not move it.
  final bool fixed;

  /// No estimate: [kDefaultTaskMinutes] was used.
  final bool unestimated;
  const PlanEntry(this.ref, this.start, this.end, this.mark,
      {required this.fixed, required this.unestimated});

  int get minutes => end.difference(start).inMinutes;
}

enum RescueKind { moveLow, overdue, timeBlock }

class RescueSuggestion {
  final RescueKind kind;
  final List<TaskRef> tasks;

  /// Minutes taken off the day.
  final int saves;
  const RescueSuggestion(this.kind, this.tasks, this.saves);
}

/// The plan for one day.
class DayPlan {
  final DateTime day;
  final DateTime windowStart;
  final DateTime windowEnd;
  final List<PlanEntry> before;
  final List<RescueSuggestion> suggestions;

  const DayPlan({
    required this.day,
    required this.windowStart,
    required this.windowEnd,
    required this.before,
    required this.suggestions,
  });

  int get availableMinutes => max(0, windowEnd.difference(windowStart).inMinutes);
  int get plannedMinutes => before.fold(0, (s, e) => s + e.minutes);
  int get overloadMinutes => max(0, plannedMinutes - availableMinutes);
  int get overdueCount => before.where((e) => e.mark == PlanMark.overdue).length;
  int get flexibleCount => before.where((e) => !e.fixed && e.ref.canEdit).length;
  int get unestimatedCount => before.where((e) => e.unestimated).length;

  /// The day after the chosen suggestions.
  List<PlanEntry> after(Set<RescueKind> chosen) {
    final moved = <String>{
      for (final s in suggestions)
        if (chosen.contains(s.kind) && s.kind == RescueKind.moveLow)
          for (final r in s.tasks) r.task.id
    };
    final bringIn = <String>{
      for (final s in suggestions)
        if (chosen.contains(s.kind) && s.kind == RescueKind.overdue)
          for (final r in s.tasks) r.task.id
    };
    final keep = before.where((e) => !moved.contains(e.ref.task.id)).toList();
    return _layout(
      keep.map((e) => (e.ref, e.unestimated, e.fixed)).toList(),
      windowStart,
      windowEnd,
      priorityFirst: true,
      rescheduled: bringIn,
      timeBlocked: chosen.contains(RescueKind.timeBlock),
    );
  }

  int savedMinutes(Set<RescueKind> chosen) =>
      suggestions.where((s) => chosen.contains(s.kind)).fold(0, (a, s) => a + s.saves);
}

/// Minutes [t] needs: its estimate, else its time slot, else the default.
(int, bool) taskMinutes(TaskItem t) {
  final e = t.estimateMinutes;
  if (e != null && e > 0) return (e, false);
  if (!t.isAllDay && t.endAt != null) {
    final m = t.endAt!.difference(t.startAt).inMinutes;
    if (m > 0) return (min(m, 8 * 60), false);
  }
  return (kDefaultTaskMinutes, true);
}

DateTime _roundUp(DateTime d) {
  final m = (d.minute + 14) ~/ 15 * 15;
  return DateTime(d.year, d.month, d.day, d.hour).add(Duration(minutes: m));
}

int _prioRank(Priority p) => switch (p) {
      Priority.high => 0,
      Priority.medium => 1,
      Priority.low => 2,
    };

/// Places fixed tasks at their times and the rest one after another in the
/// free time. [priorityFirst]: high priority first (the rescue plan),
/// otherwise in their own order.
List<PlanEntry> _layout(
  List<(TaskRef, bool, bool)> items,
  DateTime from,
  DateTime to, {
  bool priorityFirst = false,
  Set<String> rescheduled = const {},
  bool timeBlocked = false,
}) {
  final out = <PlanEntry>[];
  final busy = <(DateTime, DateTime)>[];
  final today = dateOnly(from);
  for (final (r, unest, fixed) in items) {
    if (!fixed) continue;
    final (m, _) = taskMinutes(r.task);
    final s = r.task.startAt;
    final e = s.add(Duration(minutes: m));
    busy.add((s, e));
    final late = e.isAfter(to) && !s.isBefore(from);
    out.add(PlanEntry(r, s, e, late ? PlanMark.overloaded : PlanMark.noChange,
        fixed: true, unestimated: unest));
  }
  busy.sort((a, b) => a.$1.compareTo(b.$1));

  final flexible = items.where((i) => !i.$3).toList();
  if (priorityFirst) {
    flexible.sort((a, b) {
      final ov = (a.$1.task.isOverdue ? 0 : 1).compareTo(b.$1.task.isOverdue ? 0 : 1);
      if (ov != 0) return ov;
      return _prioRank(a.$1.task.priority).compareTo(_prioRank(b.$1.task.priority));
    });
  }
  var cursor = from;
  var focusGiven = false;
  for (final (r, unest, _) in flexible) {
    final (m, _) = taskMinutes(r.task);
    // Next free slot that fits, after the cursor.
    var start = cursor;
    for (final (bs, be) in busy) {
      if (start.add(Duration(minutes: m)).isAfter(bs) && start.isBefore(be)) start = be;
    }
    final end = start.add(Duration(minutes: m));
    cursor = end;
    final overdue = dateOnly(r.task.startAt).isBefore(today);
    PlanMark mark;
    if (end.isAfter(to)) {
      mark = PlanMark.overloaded;
    } else if (rescheduled.contains(r.task.id)) {
      mark = PlanMark.rescheduled;
    } else if (overdue) {
      mark = PlanMark.overdue;
    } else if (timeBlocked && !focusGiven && r.task.priority == Priority.high && r.canEdit) {
      mark = PlanMark.focus;
      focusGiven = true;
    } else if (timeBlocked && r.canEdit) {
      mark = PlanMark.scheduled;
    } else {
      mark = PlanMark.noChange;
    }
    out.add(PlanEntry(r, start, end, mark, fixed: false, unestimated: unest));
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// The plan for [day] from my tasks ([all], e.g. [TaskRepository.myTasks]).
/// The work day is [workStart]..[workEnd] minutes after midnight; today it
/// starts no earlier than [now].
DayPlan planDay(List<TaskRef> all, DateTime day, DateTime now,
    {int workStart = 9 * 60, int workEnd = 17 * 60 + 30}) {
  final d = dateOnly(day);
  final isToday = d == dateOnly(now);
  final dayStart = d.add(Duration(minutes: workStart));
  final windowEnd = d.add(Duration(minutes: max(workEnd, workStart)));
  var windowStart = isToday && now.isAfter(dayStart) ? _roundUp(now) : dayStart;
  if (windowStart.isAfter(windowEnd)) windowStart = windowEnd;

  final items = <(TaskRef, bool, bool)>[];
  for (final r in all) {
    final t = r.task;
    if (t.status != TaskStatus.pending) continue;
    final onDay = dateOnly(t.startAt) == d;
    final overdue = isToday && dateOnly(t.startAt).isBefore(d);
    if (!onDay && !overdue) continue;
    final (mins, unest) = taskMinutes(t);
    final fixed = onDay && !t.isAllDay;
    // Already over (today): not part of what is left.
    if (fixed && !t.startAt.add(Duration(minutes: mins)).isAfter(windowStart) && isToday) {
      continue;
    }
    items.add((r, unest, fixed));
  }
  final before = _layout(items, windowStart, windowEnd);

  // ---- suggestions
  final available = max(0, windowEnd.difference(windowStart).inMinutes);
  final planned = before.fold(0, (s, e) => s + e.minutes);
  var over = planned - available;
  final suggestions = <RescueSuggestion>[];
  final movable = before.where((e) => !e.fixed && e.ref.canEdit).toList();

  final moveLow = <TaskRef>[];
  var saves = 0;
  if (over > 0) {
    final candidates = movable.where((e) => e.ref.task.priority != Priority.high).toList()
      ..sort((a, b) {
        final p = _prioRank(b.ref.task.priority).compareTo(_prioRank(a.ref.task.priority));
        return p != 0 ? p : b.minutes.compareTo(a.minutes);
      });
    for (final e in candidates) {
      if (over <= 0) break;
      moveLow.add(e.ref);
      saves += e.minutes;
      over -= e.minutes;
    }
    if (moveLow.isNotEmpty) {
      suggestions.add(RescueSuggestion(RescueKind.moveLow, moveLow, saves));
    }
  }
  final movedIds = moveLow.map((r) => r.task.id).toSet();
  final overdue = [
    for (final e in movable)
      if (e.mark == PlanMark.overdue && !movedIds.contains(e.ref.task.id)) e.ref
  ];
  if (overdue.isNotEmpty) suggestions.add(RescueSuggestion(RescueKind.overdue, overdue, 0));
  final flexible = [
    for (final e in movable)
      if (!movedIds.contains(e.ref.task.id)) e.ref
  ];
  if (flexible.isNotEmpty) suggestions.add(RescueSuggestion(RescueKind.timeBlock, flexible, 0));

  return DayPlan(
    day: d,
    windowStart: windowStart,
    windowEnd: windowEnd,
    before: before,
    suggestions: suggestions,
  );
}

/// The changes to save for the chosen suggestions: task → new start/end
/// (null end keeps it all day).
Map<TaskRef, (DateTime, DateTime?)> rescueChanges(DayPlan plan, Set<RescueKind> chosen) {
  final out = <TaskRef, (DateTime, DateTime?)>{};
  final tomorrow = plan.day.add(const Duration(days: 1));
  for (final s in plan.suggestions) {
    if (!chosen.contains(s.kind) || s.kind != RescueKind.moveLow) continue;
    for (final r in s.tasks) {
      final t = r.task;
      if (t.isAllDay) {
        out[r] = (tomorrow, DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 23, 59));
      } else {
        final len = (t.endAt ?? t.startAt).difference(t.startAt);
        final s0 =
            DateTime(tomorrow.year, tomorrow.month, tomorrow.day, t.startAt.hour, t.startAt.minute);
        out[r] = (s0, s0.add(len));
      }
    }
  }
  final after = plan.after(chosen);
  final blocked = chosen.contains(RescueKind.timeBlock);
  for (final e in after) {
    if (e.fixed || !e.ref.canEdit || out.containsKey(e.ref)) continue;
    if (blocked && e.mark != PlanMark.overloaded) {
      out[e.ref] = (e.start, e.end);
    } else if (e.mark == PlanMark.rescheduled) {
      out[e.ref] = (plan.day, DateTime(plan.day.year, plan.day.month, plan.day.day, 23, 59));
    }
  }
  return out;
}
