import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/app_store.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/task_repository.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/data/time_report.dart';
import 'package:taskflow/screens/time_screen.dart';

void main() {
  final now = DateTime.now();
  final week = weekStartOf(now);
  DateTime at(int day, int h, [int m = 0]) => week.add(Duration(days: day, hours: h, minutes: m));

  final team = Team(
    id: 'T',
    name: 'Acme',
    color: 0xFF1F6FEB,
    ownerId: 'own',
    memberIds: ['own', 'ali'],
    managerIds: [],
    members: {
      'own': const TeamMemberInfo(name: 'Adeel Devzone', email: 'a@x.com'),
      'ali': const TeamMemberInfo(name: 'Ali Khan', email: 'ali@x.com'),
    },
    createdAt: now,
    updatedAt: now,
  );

  TaskItem task(String id, String title, List<TimeEntry> log, {String? to}) => TaskItem(
      id: id,
      title: title,
      assigneeId: to,
      startAt: week,
      endAt: week.add(const Duration(hours: 23)),
      createdAt: week,
      updatedAt: week)
    ..timeLog = log;

  final homepage = task(
      'h',
      'Homepage UI Design',
      [
        TimeEntry(by: 'own', start: at(0, 9), end: at(0, 11, 30)),
        TimeEntry(by: 'own', start: at(1, 13, 30), end: at(1, 15, 15), note: 'Client revisions'),
        TimeEntry(by: 'ali', start: at(0, 10), end: at(0, 12)),
      ],
      to: 'own');
  final meeting = task('m', 'Team Meeting', [
    TimeEntry(by: 'own', start: at(0, 11, 45), end: at(0, 12, 30), billable: false),
    // Last week: not counted.
    TimeEntry(by: 'own', start: at(-3, 9), end: at(-3, 10)),
  ]);

  void seed() {
    AppStore.instance
      ..tasks = [meeting]
      ..categories = []
      ..projects = [];
    TeamStore.instance
      ..teams = [team]
      ..invites = []
      ..setForTest(uid: 'own', tasks: {
        'T': [homepage],
      });
  }

  test('rows, totals, timesheet', () {
    seed();
    final refs = [TaskRef(meeting), TaskRef(homepage, team)];
    final mine = timeRows(refs, week, week.add(const Duration(days: 7)), by: 'own');
    expect(mine.length, 3);
    final t = timeTotals(mine);
    expect(t.total, 150 + 105 + 45);
    expect(t.billable, 255);
    expect(t.nonBillable, 45);
    final sheet = timesheet(mine, week);
    expect(sheet.first.ref.task.id, 'h');
    expect(sheet.first.days.take(2), [150, 105]);
    expect(timeRows(refs, week, week.add(const Duration(days: 7))).length, 4);
    expect(hm(150), '2h 30m');
    expect(hm(45), '45m');
  });

  test('entries keep billable and note', () {
    final e = TimeEntry.tryFrom(
        TimeEntry(by: 'a', start: at(0, 9), end: at(0, 10), billable: false, note: 'x').toMap())!;
    expect(e.billable, isFalse);
    expect(e.note, 'x');
    expect(TimeEntry.tryFrom(TimeEntry(by: 'a', start: at(0, 9), end: at(0, 10)).toMap())!.billable,
        isTrue);
  });

  test('work minutes so far', () {
    final mon = DateTime(2026, 10, 12);
    final wed = DateTime(2026, 10, 14, 13);
    // Mon + Tue full (8h30 each) + Wed 9:00–13:00.
    expect(workMinutesSoFar(mon, mon.add(const Duration(days: 7)), wed, 540, 1050), 2 * 510 + 240);
  });

  for (final (name, size) in [
    ('laptop', const Size(1600, 1100)),
    ('phone', const Size(400, 860))
  ]) {
    testWidgets('time tracking on a $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      seed();
      await tester
          .pumpWidget(MaterialApp(theme: buildAppTheme(), home: const TimeScreen(page: true)));
      await tester.pump();
      expect(find.text('5h'), findsOneWidget); // total tracked
      expect(find.text('No timer running'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final tab in ['Team', 'Timesheet']) {
        await tester.tap(find.text(tab).first);
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Week total: 5h'), findsOneWidget);
      await tester.tap(find.text('Team').first);
      await tester.pump();
      expect(find.text('Ali Khan'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
