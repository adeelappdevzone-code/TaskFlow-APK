import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/reminders.dart';

void main() {
  final now = DateTime(2026, 3, 10, 12, 0);

  TaskItem task(String id, DateTime start, {String status = TaskStatus.pending}) =>
      TaskItem(
        id: id,
        title: 'Task $id',
        status: status,
        startAt: start,
        createdAt: now,
        updatedAt: now,
      );

  test('reminder is 15 minutes before the start', () {
    final plans = planReminders([task('a', DateTime(2026, 3, 10, 14, 0))], now);
    expect(plans, hasLength(1));
    expect(plans.single.at, DateTime(2026, 3, 10, 13, 45));
    expect(plans.single.taskId, 'a');
    expect(plans.single.title, 'Reminder: Task a');
  });

  test('skips done, cancelled and too-late tasks', () {
    final plans = planReminders([
      task('done', DateTime(2026, 3, 10, 15), status: TaskStatus.completed),
      task('cancelled', DateTime(2026, 3, 10, 15), status: TaskStatus.cancelled),
      task('past', DateTime(2026, 3, 10, 11)),
      task('in10min', DateTime(2026, 3, 10, 12, 10)), // reminder time already passed
      task('ok', DateTime(2026, 3, 10, 12, 30)),
    ], now);
    expect(plans.map((p) => p.taskId), ['ok']);
  });

  test('soonest first and limited to max', () {
    final tasks = [
      for (var i = 10; i > 0; i--) task('t$i', now.add(Duration(hours: i))),
    ];
    final plans = planReminders(tasks, now, max: 3);
    expect(plans.map((p) => p.taskId), ['t1', 't2', 't3']);
  });

  test('notification ids are stable, positive and differ per task', () {
    expect(reminderIdFor('abc'), reminderIdFor('abc'));
    expect(reminderIdFor('abc'), isNot(reminderIdFor('abd')));
    for (final id in ['', 'x', '6f1c2e0a-9a7b-4c1e-8f00-1234567890ab']) {
      final n = reminderIdFor(id);
      expect(n, greaterThanOrEqualTo(0));
      expect(n, lessThan(1 << 31));
    }
  });
}
