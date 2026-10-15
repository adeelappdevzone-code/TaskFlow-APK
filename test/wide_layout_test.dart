import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/app_store.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/screens/main_shell.dart';
import 'package:taskflow/screens/team_screen.dart';

// Laptop-size screen: side menu, task panel on the right, full board.
void main() {
  final now = DateTime.now();
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

  Future<void> laptop(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('side menu and task panel', (tester) async {
    await laptop(tester);
    AppStore.instance.tasks = [
      TaskItem(
        id: 'p1',
        title: 'Plan the week',
        description: 'Personal task',
        startAt: DateTime(now.year, now.month, now.day, 23),
        createdAt: now,
        updatedAt: now,
      ),
    ];
    TeamStore.instance
      ..teams = [team]
      ..invites = []
      ..setForTest(uid: 'own');
    await tester.pumpWidget(app(const MainShell()));
    expect(find.text('New Task'), findsOneWidget);
    expect(find.text('My Tasks'), findsOneWidget);

    await tester.tap(find.text('Plan the week'));
    await tester.pumpAndSettle();
    // Opened in the panel (same page), with a close button.
    expect(find.text('Personal task'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Personal task'), findsNothing);
    expect(tester.takeException(), isNull);
    AppStore.instance.tasks = [];
  });

  testWidgets('board shows all columns without scrolling', (tester) async {
    await laptop(tester);
    TeamStore.instance
      ..teams = [team]
      ..setForTest(uid: 'own', tasks: {
        'T': [
          TaskItem(
            id: 'b1',
            title: 'Review card',
            assigneeId: 'adl',
            stage: TaskStage.review,
            startAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      });
    await tester.pumpWidget(app(const TeamScreen(teamId: 'T')));
    // Laptop layout opens on the board, with the summary card on top.
    expect(find.text('0 of 1 tasks completed'), findsOneWidget);
    for (final col in ['To do', 'In progress', 'Review', 'Done']) {
      expect(find.text(col), findsWidgets);
    }
    expect(find.text('Review card'), findsOneWidget);
    // The Overview tab uses two columns and shows the chart.
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    expect(find.text('Done per day (this week)'), findsOneWidget);
    // Members: stats on top, people list.
    await tester.tap(find.text('Members (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Add person by email'), findsOneWidget);
    expect(find.text('Team members (2)'), findsOneWidget);
    expect(find.text('Adeel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
