import 'app_store.dart';
import 'models.dart';
import 'team_models.dart';
import 'team_store.dart';

/// Start/Stop work timers on personal and team tasks. Only one of my timers
/// runs at a time: starting one stops the others.
class TimeTracker {
  TimeTracker._();

  /// My running timers: (team or null for a personal task, task).
  static List<(Team?, TaskItem)> running() => [
        for (final t in AppStore.instance.runningTimers) (null, t),
        for (final (team, t) in TeamStore.instance.myRunningTimers) (team, t),
      ];

  static void start(TaskItem task, {Team? team}) {
    for (final (otherTeam, other) in running()) {
      if (other.id != task.id) stop(other, team: otherTeam);
    }
    if (team == null) {
      AppStore.instance.startTimer(task);
    } else {
      TeamStore.instance.startTimer(team, task);
    }
  }

  static void stop(TaskItem task, {Team? team, DateTime? end}) {
    if (team == null) {
      AppStore.instance.stopTimer(task, end: end);
    } else {
      TeamStore.instance.stopTimer(team, task, end: end);
    }
  }
}
