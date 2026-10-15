import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/app_store.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/screens/main_shell.dart';
import 'package:taskflow/screens/tasks_screen.dart';
import 'package:taskflow/screens/teams_screen.dart';

// Laptop Teams/Tasks pages and the phone versions render with sample data.
void main() {
  final now = DateTime.now();
  DateTime d(int day, int h) => DateTime(now.year, now.month, now.day + day, h);
  final teams = [
    for (final (id, name, c) in [
      ('T1', 'UI UX', 0xFF1F6FEB),
      ('T2', 'Marketing', 0xFFDB2777),
      ('T3', 'Development', 0xFF16A34A)
    ])
      Team(
          id: id,
          name: name,
          color: c,
          ownerId: id == 'T1' ? 'own' : 'x',
          memberIds: ['own', 'gn', 'hm', 'x'],
          managerIds: [],
          members: {
            'own': const TeamMemberInfo(name: 'Adeel App', email: 'a@x.com'),
            'gn': const TeamMemberInfo(name: 'GlazeMe Nail', email: 'g@x.com'),
            'hm': const TeamMemberInfo(name: 'Harry Mosa', email: 'h@x.com'),
            'x': const TeamMemberInfo(name: 'Xavier Q', email: 'x@x.com')
          },
          createdAt: d(-3, 9),
          updatedAt: now),
  ];
  TaskItem t(String id, String title,
          {String? to, int day = 0, bool done = false, String? cat, String? by}) =>
      TaskItem(
          id: id,
          title: title,
          assigneeId: to,
          categoryId: cat,
          status: done ? TaskStatus.completed : TaskStatus.pending,
          startAt: d(day, 11),
          endAt: d(day, 12),
          completedAt: done ? d(-1, 18) : null,
          completedBy: done ? to : null,
          assignedBy: by,
          assignedAt: by == null ? null : d(-1, 16),
          createdAt: d(-2, 9),
          updatedAt: now,
          priority: id.endsWith('h') ? Priority.high : Priority.medium);

  void seed() {
    TeamStore.instance
      ..teams = teams
      ..invites = []
      ..setForTest(uid: 'own', tasks: {
        'T1': [
          t('a', 'SEO', to: 'gn', day: -1, by: 'own'),
          t('b', 'Website live', to: 'hm', done: true),
          t('c', 'Web audit', day: 1)
        ],
        'T2': [t('d', 'Ads', to: 'x', day: 2)],
        'T3': [t('e', 'API', to: 'own', day: 0)],
      });
    TeamStore.instance.sentInvites['T1'] = [
      TeamInvite(
          id: 'T1_j',
          teamId: 'T1',
          teamName: 'UI UX',
          email: 'james.smith@gmail.com',
          invitedBy: 'own',
          invitedByName: 'Adeel App',
          createdAt: d(-2, 10))
    ];
    final store = AppStore.instance;
    store.categories = [
      Category(id: 'w', name: 'Work', color: 0xFF1F6FEB, createdAt: now, updatedAt: now),
      Category(id: 'r', name: 'Research', color: 0xFFF97316, createdAt: now, updatedAt: now)
    ];
    store.tasks = [
      t('p1h', 'Team meeting', day: -1, cat: 'w'),
      t('p2', 'Design app UI', day: -1, cat: 'r'),
      t('p3h', 'Code review', day: 0, cat: 'w'),
      t('p4', 'Research new feature', day: 0, cat: 'r'),
      t('p5', 'Social media plan', day: 2, cat: 'w'),
      t('p6', 'Prepare weekly report', day: -1, done: true, cat: 'w')
    ];
  }

  void check(String name) {
    switch (name) {
      case 'g_teams_wide':
        expect(find.text('Total teams'), findsOneWidget);
        expect(find.text('Recent Activity'), findsOneWidget);
        expect(find.text('Pending Invites'), findsOneWidget);
        expect(find.text('James Smith'), findsOneWidget); // invite from the email
        expect(find.textContaining('completed'), findsWidgets);
      case 'g_tasks_wide':
        expect(find.text('Total tasks'), findsOneWidget);
        expect(find.text("Today's Focus"), findsOneWidget);
        expect(find.text('Task Progress'), findsOneWidget);
        expect(find.text('Upcoming Tasks'), findsOneWidget);
        expect(find.text('All (7)'), findsOneWidget); // 6 personal + 1 assigned team task
        expect(find.text('Development'), findsWidgets); // team chip
      case 'g_tasks_board':
        expect(find.text('In progress'), findsOneWidget);
        expect(find.text('Review'), findsOneWidget);
      case 'g_teams_phone':
        expect(find.text('Total teams'), findsOneWidget);
        expect(find.text('Create new team'), findsOneWidget);
      case 'g_tasks_phone':
        expect(find.text('Overdue'), findsWidgets);
        expect(find.byTooltip('Sort'), findsOneWidget);
    }
  }

  Future<void> shot(WidgetTester tester, Size size, Widget home, String name,
      {Future<void> Function()? then}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seed();
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: home));
    await tester.pumpAndSettle();
    if (then != null) await then();
    check(name);
    expect(tester.takeException(), isNull);
  }

  testWidgets(
      'teams wide',
      (tester) async =>
          shot(tester, const Size(1600, 1000), const MainShell(), 'g_teams_wide', then: () async {
            await tester.tap(find.text('Teams').first);
            await tester.pumpAndSettle();
          }));
  testWidgets(
      'tasks wide',
      (tester) async =>
          shot(tester, const Size(1600, 1000), const MainShell(), 'g_tasks_wide', then: () async {
            await tester.tap(find.text('My Tasks').first);
            await tester.pumpAndSettle();
          }));
  testWidgets(
      'tasks wide board',
      (tester) async =>
          shot(tester, const Size(1600, 1000), const MainShell(), 'g_tasks_board', then: () async {
            await tester.tap(find.text('My Tasks').first);
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('Board view'));
            await tester.pumpAndSettle();
          }));
  testWidgets(
      'teams phone',
      (tester) async => shot(
          tester, const Size(400, 1400), const Scaffold(body: TeamsScreen()), 'g_teams_phone'));
  testWidgets(
      'tasks phone',
      (tester) async =>
          shot(tester, const Size(400, 900), const Scaffold(body: TasksScreen()), 'g_tasks_phone'));
}
