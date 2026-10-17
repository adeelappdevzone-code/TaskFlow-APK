import 'dart:async';
import 'dart:math' show max;

import '../core/utils.dart';
import 'app_store.dart';
import 'models.dart';
import 'planner.dart';
import 'task_repository.dart';
import 'team_models.dart';
import 'team_store.dart';

// How busy a person is on a day, across everything they do. Each person's app
// adds up their own open work per day (personal tasks and all their teams)
// and shares only the totals with their teams (TeamMemberInfo.busy). A
// manager then sees "Adeel already has 3h 30m that day" without seeing the
// other team's or personal tasks.

/// Days ahead that are shared.
const kBusyDays = 14;

/// "20261017".
String dayKey(DateTime d) =>
    '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

/// The day a task's work counts on: its day, or today when it is late.
DateTime workDayOf(TaskItem t, DateTime today) {
  final d = dateOnly(t.startAt);
  return d.isBefore(today) ? today : d;
}

/// Open work still to do: pending, and not already sent for review.
bool isOpenWork(TaskItem t) =>
    t.status == TaskStatus.pending && t.stage != TaskStage.review && !t.isCancelled;

/// My open work per day for the next [kBusyDays] days (late work on today).
Map<String, int> busyByDay(Iterable<TaskRef> mine, DateTime now) {
  final today = dateOnly(now);
  final end = today.add(const Duration(days: kBusyDays));
  final out = <String, int>{};
  for (final r in mine) {
    final t = r.task;
    if (!isOpenWork(t)) continue;
    final d = workDayOf(t, today);
    if (!d.isBefore(end)) continue;
    final k = dayKey(d);
    out[k] = (out[k] ?? 0) + taskMinutes(t).$1;
  }
  return out;
}

/// One person's day as a manager sees it.
class DayLoad {
  /// Work in teams I can see (counted from the tasks themselves).
  final int visible;

  /// Their other work (personal and teams I'm not in), from what they share.
  final int elsewhere;

  /// Their work day in minutes (0 on a day off).
  final int capacity;
  const DayLoad(this.visible, this.elsewhere, this.capacity);

  int get total => visible + elsewhere;
  int get free => max(0, capacity - total);
  int overloadWith(int extra) => max(0, total + extra - capacity);
}

/// What [uid] shared about their work hours, from any team we share.
TeamMemberInfo? _infoOf(String uid, List<Team> teams) {
  TeamMemberInfo? any;
  for (final t in teams) {
    final i = t.members[uid];
    if (i == null) continue;
    if (i.dayMinutes != null) return i;
    any ??= i;
  }
  return any;
}

/// [uid]'s work day length on [day]: their own hours and days when shared,
/// else the team's hours over Monday–Friday.
int dayCapacity(String uid, DateTime day, List<Team> teams, {Team? team}) {
  final info = _infoOf(uid, teams);
  final days = info?.workDays ?? const [1, 2, 3, 4, 5];
  if (!days.contains(day.weekday)) return 0;
  if (info?.dayMinutes != null) return info!.dayMinutes!;
  final from = team ?? teams.where((t) => t.memberIds.contains(uid)).firstOrNull;
  return (from?.weekHours ?? 40) * 60 ~/ 5;
}

/// [uid]'s load on [day]: their open tasks in [teams] (all teams I can see)
/// plus the rest of what they shared. [skipTaskId]: leave out a task being
/// edited.
DayLoad loadOn(String uid, DateTime day, List<Team> teams, List<TaskItem> Function(String) tasksOf,
    DateTime now,
    {Team? team, String? skipTaskId}) {
  final today = dateOnly(now);
  final d = dateOnly(day);
  var visible = 0;
  for (final t in teams) {
    if (!t.memberIds.contains(uid)) continue;
    for (final x in tasksOf(t.id)) {
      if (x.assigneeId != uid || x.id == skipTaskId || !isOpenWork(x)) continue;
      if (workDayOf(x, today) == d) visible += taskMinutes(x).$1;
    }
  }
  var shared = 0;
  for (final t in teams) {
    shared = max(shared, t.members[uid]?.busy[dayKey(d)] ?? 0);
  }
  return DayLoad(visible, max(0, shared - visible), dayCapacity(uid, d, teams, team: team));
}

/// The first day after [from] (within 30) where [uid] has room for [minutes].
DateTime? nextFreeDay(String uid, DateTime from, int minutes, List<Team> teams,
    List<TaskItem> Function(String) tasksOf, DateTime now,
    {Team? team}) {
  for (var i = 1; i <= 30; i++) {
    final d = DateTime(from.year, from.month, from.day + i);
    final l = loadOn(uid, d, teams, tasksOf, now, team: team);
    if (l.capacity > 0 && l.total + minutes <= l.capacity) return d;
  }
  return null;
}

/// Keeps my shared busy time current while I'm logged in.
class BusySync {
  BusySync._();
  static final instance = BusySync._();

  Timer? _debounce;
  bool _on = false;

  void start() {
    if (_on) return;
    _on = true;
    AppStore.instance.addListener(_changed);
    TeamStore.instance.addListener(_changed);
    _changed();
  }

  void stop() {
    if (!_on) return;
    _on = false;
    AppStore.instance.removeListener(_changed);
    TeamStore.instance.removeListener(_changed);
    _debounce?.cancel();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), _sync);
  }

  void _sync() {
    if (!_on || TeamStore.instance.uid == null || TeamStore.instance.teams.isEmpty) return;
    TeamStore.instance.setMyBusy(busyByDay(TaskRepository.myTasks(), DateTime.now()));
  }
}
