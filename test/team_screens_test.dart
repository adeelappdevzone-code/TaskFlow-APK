import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/screens/task_form_screen.dart';
import 'package:taskflow/screens/team_screen.dart';
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
    expect(find.text('New task • SEO'), findsOneWidget);
    expect(find.text('Category'), findsNothing);
    expect(find.text('Project'), findsNothing);
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
    expect(find.text('Adeel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Teams tab shows the summary for owners', (tester) async {
    TeamStore.instance.setForTest(uid: 'own');
    await tester.pumpWidget(app(const Scaffold(body: TeamsScreen())));
    expect(find.text('Your team at a glance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
