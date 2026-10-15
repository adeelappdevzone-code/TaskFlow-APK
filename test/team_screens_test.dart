import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
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
}
