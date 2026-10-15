import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/screens/home_screen.dart';
import 'package:taskflow/screens/report_screen.dart';
import 'package:taskflow/screens/task_form_screen.dart';
import 'package:taskflow/screens/team_screen.dart';
import 'package:taskflow/screens/team_task_detail_screen.dart';
import 'package:taskflow/screens/teams_screen.dart';

// Renders the team screens with sample data (no Firebase needed) to catch
// layout errors.
void main() {
  final now = DateTime(2026, 4, 1, 10);
  final team = Team(
    id: 'T',
    name: 'SEO',
    color: 0xFF1F6FEB,
    ownerId: 'own',
    memberIds: ['own', 'adl'],
    managerIds: [],
    members: {
      'own': const TeamMemberInfo(name: 'Tabish', email: 'tabish@x.com'),
      'adl': const TeamMemberInfo(name: 'Adeel', email: 'adeel@x.com'),
    },
    createdAt: now,
    updatedAt: now,
  );

  Widget app(Widget home) => MaterialApp(theme: buildAppTheme(), home: home);

  setUp(() {
    TeamStore.instance.setForTest();
    TeamStore.instance
      ..teams = [team]
      ..invites = [
        TeamInvite(
          id: 'X_me@x.com',
          teamId: 'X',
          teamName: 'Marketing',
          email: 'me@x.com',
          invitedBy: 'boss',
          invitedByName: 'Boss',
          createdAt: now,
        ),
      ];
  });

  testWidgets('Teams tab shows invitations and teams', (tester) async {
    await tester.pumpWidget(app(const Scaffold(body: TeamsScreen())));
    expect(find.text('Invitations'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('SEO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Team screen: tasks and members tabs', (tester) async {
    await tester.pumpWidget(app(const TeamScreen(teamId: 'T')));
    expect(find.text('No tasks yet'), findsOneWidget);
    await tester.tap(find.text('Members (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Adeel'), findsOneWidget);
    expect(find.text('Member'), findsOneWidget);
    // Overview tab exists only for owner/managers (no user logged in here).
    expect(find.text('Overview'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Team task form hides category/project', (tester) async {
    await tester.pumpWidget(app(TaskFormScreen(team: team)));
    expect(find.text('New task'), findsOneWidget);
    expect(find.text('SEO'), findsWidgets); // team preselected
    expect(find.text('Category'), findsNothing);
    expect(find.text('Project'), findsNothing);
    await tester.scrollUntilVisible(find.text('Choose a team member'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Choose a team member'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Owner sees the Overview dashboard', (tester) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    TaskItem t(String id, String? to, String status) => TaskItem(
          id: id,
          title: 'Task $id',
          assigneeId: to,
          status: status,
          startAt: yesterday,
          completedAt: status == TaskStatus.completed ? DateTime.now() : null,
          createdAt: yesterday,
          updatedAt: yesterday,
        );
    TeamStore.instance.setForTest(uid: 'own', tasks: {
      'T': [
        t('1', 'adl', TaskStatus.pending),
        t('2', 'adl', TaskStatus.completed),
        t('3', null, TaskStatus.pending),
      ],
    });
    await tester.pumpWidget(app(const TeamScreen(teamId: 'T')));
    expect(find.text('Task 1'), findsOneWidget);
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 tasks done'), findsOneWidget);
    expect(find.text('Overdue'), findsWidgets);
    expect(find.text('Done per day (this week)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Adeel'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Adeel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Teams tab shows the summary for owners', (tester) async {
    TeamStore.instance.setForTest(uid: 'own');
    await tester.pumpWidget(app(const Scaffold(body: TeamsScreen())));
    expect(find.text('Total teams'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Board view shows the four columns', (tester) async {
    final now = DateTime.now();
    TaskItem t(String id, String stage, String status) => TaskItem(
          id: id,
          title: 'Card $id',
          assigneeId: 'adl',
          status: status,
          stage: stage,
          startAt: now,
          createdAt: now,
          updatedAt: now,
        );
    TeamStore.instance.setForTest(uid: 'own', tasks: {
      'T': [
        t('1', TaskStage.todo, TaskStatus.pending),
        t('2', TaskStage.doing, TaskStatus.pending),
        t('3', TaskStage.review, TaskStatus.pending),
        t('4', TaskStage.todo, TaskStatus.completed),
      ],
    });
    await tester.pumpWidget(app(const TeamScreen(teamId: 'T')));
    await tester.tap(find.byTooltip('Board view'));
    await tester.pumpAndSettle();
    expect(find.text('To do'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Card 1'), findsOneWidget);
    expect(find.text('Card 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Task form has repeat and templates', (tester) async {
    await tester.pumpWidget(app(TaskFormScreen(team: team)));
    await tester.scrollUntilVisible(find.text('Does not repeat'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Does not repeat'), findsOneWidget);
    expect(find.byTooltip('Templates'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('My Day lists team tasks assigned to me', (tester) async {
    final now = DateTime.now();
    final later = DateTime(now.year, now.month, now.day, 23, 0);
    TeamStore.instance.setForTest(uid: 'adl', tasks: {
      'T': [
        TaskItem(
          id: 'm1',
          title: 'Write SEO blog',
          assigneeId: 'adl',
          startAt: later,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    });
    await tester.pumpWidget(app(const Scaffold(body: HomeScreen())));
    expect(find.text('My Day (Today)'), findsOneWidget);
    expect(find.text('Write SEO blog'), findsOneWidget);
    expect(find.text('SEO'), findsOneWidget); // team chip
    expect(tester.takeException(), isNull);
  });

  testWidgets('Weekly report screen renders', (tester) async {
    final now = DateTime.now();
    TeamStore.instance.setForTest(uid: 'own', tasks: {
      'T': [
        TaskItem(
          id: 'r1',
          title: 'Keyword research',
          assigneeId: 'adl',
          status: TaskStatus.completed,
          startAt: now,
          completedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    });
    await tester.pumpWidget(app(const WeeklyReportScreen(teamId: 'T')));
    expect(find.text('This week'), findsOneWidget);
    expect(find.textContaining('Keyword research'), findsOneWidget);
    expect(find.text('Share as image'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous week'));
    await tester.pump();
    expect(find.text('Last week'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Team task: links, timer, history and @mention suggestions', (tester) async {
    final now = DateTime.now();
    final task = TaskItem(
      id: 'd1',
      title: 'Landing page',
      assigneeId: 'adl',
      startAt: now,
      createdAt: now,
      updatedAt: now,
      createdBy: 'own',
      assignedBy: 'own',
      assignedAt: now,
      links: [const TaskLink(title: 'Design brief', url: 'https://docs.google.com/x')],
      timeLog: [TimeEntry(by: 'adl', start: now, end: now.add(const Duration(minutes: 95)))],
    );
    task.addHistory(HistoryKind.created, 'own', at: now);
    task.addHistory(HistoryKind.assigned, 'own', to: 'adl', at: now);
    TeamStore.instance.setForTest(uid: 'adl', tasks: {
      'T': [task]
    });
    await tester.pumpWidget(app(const TeamTaskDetailScreen(teamId: 'T', taskId: 'd1')));
    await tester.pump();
    expect(find.text('Design brief'), findsOneWidget);
    expect(find.text('Time tracked'), findsOneWidget);
    expect(find.text('1h 35m'), findsWidgets);
    expect(find.text('Start'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Tabish assigned it to You'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Tabish created the task'), findsOneWidget);

    await tester.scrollUntilVisible(find.byType(TextField), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.byType(TextField), 'ping @Ta');
    await tester.pump();
    expect(find.widgetWithText(ActionChip, 'Tabish'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ActionChip, 'Tabish'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionChip, 'Tabish'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'ping @Tabish ');
    expect(tester.takeException(), isNull);
  });

  testWidgets('My Day shows a running timer', (tester) async {
    final now = DateTime.now();
    TeamStore.instance.setForTest(uid: 'adl', tasks: {
      'T': [
        TaskItem(
          id: 'r1',
          title: 'Fix sitemap',
          assigneeId: 'adl',
          startAt: now,
          createdAt: now,
          updatedAt: now,
          timerBy: 'adl',
          timerAt: now.subtract(const Duration(minutes: 3)),
        ),
      ],
    });
    await tester.pumpWidget(app(const Scaffold(body: HomeScreen())));
    expect(find.text('Stop'), findsOneWidget);
    expect(find.textContaining('SEO • 3:0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
