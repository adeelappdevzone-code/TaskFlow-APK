import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/data/workload.dart';
import 'package:taskflow/screens/main_shell.dart';
import 'package:taskflow/screens/workload_screen.dart';

void main() {
  // Wednesday 14 Oct 2026.
  final now = DateTime(2026, 10, 14, 10);
  final team = Team(
    id: 'T',
    name: 'Design',
    color: 0xFF1F6FEB,
    ownerId: 'own',
    memberIds: ['own', 'hm', 'sk'],
    managerIds: [],
    members: {
      'own': const TeamMemberInfo(name: 'Adeel Devzone', email: 'a@x.com'),
      'hm': const TeamMemberInfo(name: 'Harry Mosa', email: 'h@x.com'),
      'sk': const TeamMemberInfo(name: 'Sara Khan', email: 's@x.com'),
    },
    createdAt: now,
    updatedAt: now,
  );
  TaskItem t(String id, String to, int day, int? est,
          {bool done = false, Priority p = Priority.medium}) =>
      TaskItem(
        id: id,
        title: 'Task $id',
        assigneeId: to,
        priority: p,
        status: done ? TaskStatus.completed : TaskStatus.pending,
        startAt: DateTime(2026, 10, day),
        endAt: DateTime(2026, 10, day, 23, 59),
        createdAt: now,
        updatedAt: now,
        estimateMinutes: est,
      );
  final tasks = [
    // Harry: 44h this week (over 40h), one low-priority 4h task.
    t('h1', 'hm', 13, 20 * 60),
    t('h2', 'hm', 15, 20 * 60),
    t('h3', 'hm', 16, 4 * 60, p: Priority.low),
    // Sara: 6h, one late from last week, one done.
    t('s1', 'sk', 8, 4 * 60),
    t('s2', 'sk', 14, 2 * 60),
    t('s3', 'sk', 14, 60, done: true),
    // Adeel: one task without estimate (30 min); next week task.
    t('a1', 'own', 15, null),
    t('a2', 'own', 20, 8 * 60),
    // Unassigned.
    TaskItem(
        id: 'u', title: 'Nobody', startAt: DateTime(2026, 10, 15), createdAt: now, updatedAt: now),
  ];

  test('periods', () {
    expect(periodRange(WorkloadPeriod.thisWeek, now),
        (DateTime(2026, 10, 12), DateTime(2026, 10, 19)));
    expect(periodRange(WorkloadPeriod.thisMonth, now).$2, DateTime(2026, 11));
    expect(workDays(DateTime(2026, 10, 12), DateTime(2026, 10, 19)), 5);
  });

  test('load per person and a rebalance', () {
    final r = buildWorkload([team], (_) => tasks, WorkloadPeriod.thisWeek, now);
    final by = {for (final m in r.members) m.uid: m};
    expect(by['hm']!.minutes, 44 * 60);
    expect(by['hm']!.capacityMinutes, 40 * 60);
    expect(by['sk']!.minutes, 6 * 60); // late task included
    expect(by['sk']!.doneCount, 1);
    expect(by['own']!.minutes, 30);
    expect(by['own']!.unestimated, 1);
    expect(r.unassigned.map((x) => x.task.id), ['u']);
    expect(r.members.first.uid, 'hm'); // busiest first
    final moves = r.rebalances();
    expect(moves.length, 1);
    expect(moves.first.task.task.id, 'h3');
    expect(moves.first.to.uid, 'own');

    final next = buildWorkload([team], (_) => tasks, WorkloadPeriod.nextWeek, now);
    expect({for (final m in next.members) m.uid: m.minutes}['own'], 8 * 60);
  });

  test("a member's own work week is their capacity", () {
    final mine = Team.fromMap(team.toMap())
      ..members['sk'] =
          const TeamMemberInfo(name: 'Sara Khan', email: 's@x.com', weekMinutes: 1200);
    final by = {
      for (final m in buildWorkload([mine], (_) => tasks, WorkloadPeriod.thisWeek, now).members)
        m.uid: m
    };
    expect(by['sk']!.capacityMinutes, 1200); // 20h, her own
    expect(by['hm']!.capacityMinutes, 40 * 60); // not set: team hours
    expect(Team.fromMap(mine.toMap()).members['sk']!.weekMinutes, 1200);
    expect(Team.fromMap(mine.toMap()).members['hm']!.weekMinutes, isNull);
  });

  test('team hours per week survive toMap / fromMap', () {
    team.weekHours = 30;
    expect(Team.fromMap(team.toMap()).weekHours, 30);
    team.weekHours = 40;
  });

  Future<void> seed() async {
    final today = DateTime.now();
    TeamStore.instance
      ..teams = [team]
      ..invites = []
      ..setForTest(uid: 'own', tasks: {
        'T': [
          for (final (i, x) in tasks.indexed)
            x
              ..startAt = DateTime(today.year, today.month, today.day)
              ..endAt = DateTime(today.year, today.month, today.day, 23, 59)
              ..id.length // keep ids
              ..title = 'Task number $i'
        ],
      });
  }

  for (final (name, size) in [
    ('laptop', const Size(1600, 1100)),
    ('phone', const Size(400, 860))
  ]) {
    testWidgets('workload on a $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await seed();
      await tester
          .pumpWidget(MaterialApp(theme: buildAppTheme(), home: const WorkloadScreen(page: true)));
      await tester.pumpAndSettle();
      expect(find.text('Harry Mosa'), findsOneWidget);
      expect(find.text('Assign Task'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final v in ['Tasks', 'Capacity']) {
        await tester.scrollUntilVisible(find.text(v).first, 300,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text(v).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.scrollUntilVisible(find.textContaining('overloaded').first, 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Reassign'), findsOneWidget);
    });
  }

  testWidgets('dark side menu in the design order', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await seed();
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const MainShell()));
    await tester.pumpAndSettle();
    final labels = [
      'Dashboard',
      'My Tasks',
      'Capture',
      'Daily Planner',
      'Calendar',
      'Teams',
      'Team Workload',
      'Approvals',
      'Notifications',
      'Settings'
    ];
    final ys = [for (final l in labels) tester.getTopLeft(find.text(l).first).dy];
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i], greaterThan(ys[i - 1]), reason: labels[i]);
    }
    await tester.tap(find.text('Team Workload').first);
    await tester.pumpAndSettle();
    expect(find.text('Team Capacity Overview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
