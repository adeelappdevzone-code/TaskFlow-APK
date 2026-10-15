import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_stats.dart';

void main() {
  // Wednesday 2026-04-15 12:00 -> week starts Monday 2026-04-13.
  final now = DateTime(2026, 4, 15, 12);
  final team = Team(
    id: 'T',
    name: 'SEO',
    color: 1,
    ownerId: 'own',
    memberIds: ['own', 'adl', 'sar'],
    managerIds: [],
    members: {
      'own': const TeamMemberInfo(name: 'Owner', email: ''),
      'adl': const TeamMemberInfo(name: 'Adeel', email: ''),
      'sar': const TeamMemberInfo(name: 'Sara', email: ''),
    },
    createdAt: now,
    updatedAt: now,
  );

  TaskItem task(String id,
          {String? to,
          String status = TaskStatus.pending,
          required DateTime start,
          DateTime? done}) =>
      TaskItem(
        id: id,
        title: id,
        assigneeId: to,
        status: status,
        startAt: start,
        endAt: start.add(const Duration(hours: 1)),
        completedAt: done,
        createdAt: now,
        updatedAt: now,
      );

  test('team dashboard numbers', () {
    final st = TeamStats.compute(
        team,
        [
          task('late1', to: 'adl', start: DateTime(2026, 4, 14, 9)), // overdue
          task('late2', to: 'adl', start: DateTime(2026, 4, 10, 9)), // overdue, older
          task('future', to: 'sar', start: DateTime(2026, 4, 20, 9)),
          task('open', start: DateTime(2026, 4, 20, 9)), // unassigned
          task('doneWeek',
              to: 'sar',
              status: TaskStatus.completed,
              start: DateTime(2026, 4, 13),
              done: DateTime(2026, 4, 14, 10)),
          task('doneOld',
              to: 'adl',
              status: TaskStatus.completed,
              start: DateTime(2026, 4, 1),
              done: DateTime(2026, 4, 2)),
          task('cancelled', to: 'adl', status: TaskStatus.cancelled, start: DateTime(2026, 4, 1)),
          task('former', to: 'gone', start: DateTime(2026, 4, 20)), // removed member
        ],
        now);

    expect(st.total, 7);
    expect(st.done, 2);
    expect(st.pending, 5);
    expect(st.overdue, 2);
    expect(st.unassigned, 1);
    expect(st.doneThisWeek, 1);
    expect(st.overdueTasks.map((t) => t.id), ['late2', 'late1']);

    // Most overdue first, then most pending, then by name.
    expect(st.members.map((m) => m.uid), ['adl', 'sar', 'own']);
    final adeel = st.members.first;
    expect(adeel.pending, 2);
    expect(adeel.overdue, 2);
    expect(adeel.done, 1);
    expect(adeel.doneThisWeek, 0);
    final sara = st.members[1];
    expect(sara.pending, 1);
    expect(sara.doneThisWeek, 1);
    expect(sara.progress, 0.5);
  });

  test('week starts on Monday', () {
    expect(TeamStats.weekStart(DateTime(2026, 4, 15, 12)), DateTime(2026, 4, 13));
    expect(TeamStats.weekStart(DateTime(2026, 4, 13, 0, 5)), DateTime(2026, 4, 13));
    expect(TeamStats.weekStart(DateTime(2026, 4, 19, 23)), DateTime(2026, 4, 13));
  });
}
