import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/weekly_report.dart';

void main() {
  // Thursday 16 Apr 2026, 12:00. This week = Mon 13 .. Sun 19 Apr.
  final now = DateTime(2026, 4, 16, 12);
  final created = DateTime(2026, 4, 1);
  final team = Team(
    id: 'T',
    name: 'SEO',
    color: 1,
    ownerId: 'own',
    memberIds: ['own', 'adl', 'sar'],
    managerIds: [],
    members: {
      'own': const TeamMemberInfo(name: 'Tabish', email: ''),
      'adl': const TeamMemberInfo(name: 'Adeel', email: ''),
      'sar': const TeamMemberInfo(name: 'Sara', email: ''),
    },
    createdAt: created,
    updatedAt: created,
  );

  TaskItem task(String id, String? to, DateTime due, {DateTime? doneAt, bool cancelled = false}) =>
      TaskItem(
        id: id,
        title: 'Task $id',
        assigneeId: to,
        status: cancelled
            ? TaskStatus.cancelled
            : (doneAt != null ? TaskStatus.completed : TaskStatus.pending),
        startAt: due.subtract(const Duration(hours: 1)),
        endAt: due,
        completedAt: doneAt,
        createdAt: created,
        updatedAt: created,
      );

  final tasks = [
    task('a', 'adl', DateTime(2026, 4, 14, 10), doneAt: DateTime(2026, 4, 14, 9)), // done on time
    task('b', 'adl', DateTime(2026, 4, 13, 10),
        doneAt: DateTime(2026, 4, 15, 9)), // done late, this week
    task('c', 'sar', DateTime(2026, 4, 15, 10)), // late, still open
    task('d', 'sar', DateTime(2026, 4, 18, 10)), // due later this week, not late yet
    task('e', 'adl', DateTime(2026, 4, 8, 10), doneAt: DateTime(2026, 4, 9)), // last week
    task('f', null, DateTime(2026, 4, 10, 10)), // late since last week, unassigned
    task('g', 'sar', DateTime(2026, 4, 14), cancelled: true), // ignored
  ];

  test('this week', () {
    final r = WeeklyReport.compute(team, tasks, now);
    expect(r.start, DateTime(2026, 4, 13));
    expect(r.end, DateTime(2026, 4, 20));
    expect(r.rangeLabel, '13 – 19 Apr 2026');
    expect(r.done.map((t) => t.id), ['a', 'b']);
    expect(r.late.map((t) => t.id), ['f', 'c']);
    expect(r.dueThisWeek, 4); // a, b, c, d
    expect(r.members.first.name, 'Adeel');
    expect(r.members.first.done, 2);
    final sara = r.members.firstWhere((m) => m.uid == 'sar');
    expect(sara.late, 1);
  });

  test('last week', () {
    final r = WeeklyReport.compute(team, tasks, now, weeksBack: 1);
    expect(r.rangeLabel, '6 – 12 Apr 2026');
    expect(r.done.map((t) => t.id), ['e']);
    // At the end of last week f was late; b and a were not due yet.
    expect(r.late.map((t) => t.id), ['f']);
  });

  test('text for WhatsApp', () {
    final text = WeeklyReport.compute(team, tasks, now).toText(maxItems: 1);
    expect(text, contains('*SEO* — weekly report'));
    expect(text, contains('✅ Done: 2   ⏰ Late: 2'));
    expect(text, contains('👤 Adeel: 2 done'));
    expect(text, contains('👤 Sara: 0 done, 1 late'));
    expect(text, contains('• Task a (Adeel)'));
    expect(text, contains('…and 1 more'));
    expect(text, contains('(unassigned) — due Fri 10 Apr'));
  });
}
