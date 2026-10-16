import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/screens/team_board.dart';
import 'package:taskflow/screens/team_screen.dart';

void main() {
  final now = DateTime.now();
  final team = Team(
    id: 'T',
    name: 'SEO Dev',
    color: 0xFF16A34A,
    ownerId: 'boss',
    memberIds: ['boss', 'me', 'wa', 'ma'],
    managerIds: [],
    members: {
      'boss': const TeamMemberInfo(name: 'Boss', email: 'b@x.com'),
      'me': const TeamMemberInfo(name: 'Adeel App', email: 'a@x.com'),
      'wa': const TeamMemberInfo(name: 'waseem akram', email: 'w@x.com'),
      'ma': const TeamMemberInfo(name: 'M. Awais', email: 'm@x.com'),
    },
    createdAt: now,
    updatedAt: now,
  );
  TaskItem t(String id, String title, String to, {String stage = TaskStage.todo}) => TaskItem(
      id: id,
      title: title,
      assigneeId: to,
      stage: stage,
      startAt: now.add(const Duration(days: 2)),
      endAt: now.add(const Duration(days: 2, hours: 1)),
      createdAt: now,
      updatedAt: now);

  void seed() {
    TeamStore.instance
      ..teams = [team]
      ..invites = []
      ..setForTest(uid: 'me', tasks: {
        'T': [
          t('1', 'Glaze me Collection banners', 'me'),
          t('2', 'Alpha Smahs New Website Audit', 'ma'),
          t('3', 'Youtube 30 videos Creation', 'me', stage: TaskStage.doing),
          t('4', 'Alpha Website Spacing', 'wa', stage: TaskStage.review),
        ],
      });
  }

  testWidgets('laptop board: my tasks marked, "Assigned to me" shows only mine', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seed();
    await tester
        .pumpWidget(MaterialApp(theme: buildAppTheme(), home: const TeamScreen(teamId: 'T')));
    await tester.pumpAndSettle();
    expect(find.text('All (4)'), findsOneWidget);
    expect(find.text('Assigned to me (2)'), findsOneWidget);
    expect(find.byType(AssignedToYouChip), findsNWidgets(2));
    expect(find.text('Alpha Website Spacing'), findsOneWidget);
    expect(find.text('Pending (4)'), findsNothing);

    await tester.tap(find.text('Assigned to me (2)'));
    await tester.pumpAndSettle();
    expect(find.text('2 tasks assigned to you'), findsOneWidget);
    expect(find.text('Alpha Website Spacing'), findsNothing);
    expect(find.text('Youtube 30 videos Creation'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // List keeps the filter; my rows are marked.
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    expect(find.text('Glaze me Collection banners'), findsOneWidget);
    expect(find.text('Alpha Smahs New Website Audit'), findsNothing);
    await tester.tap(find.text('Clear filter'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha Smahs New Website Audit'), findsOneWidget);
    expect(find.byType(AssignedToYouChip), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone list: All / Assigned to me', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seed();
    await tester
        .pumpWidget(MaterialApp(theme: buildAppTheme(), home: const TeamScreen(teamId: 'T')));
    await tester.pumpAndSettle();
    expect(find.text('Assigned to me (2)'), findsOneWidget);
    expect(find.byType(AssignedToYouChip), findsNWidgets(2));
    await tester.tap(find.text('Assigned to me (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha Website Spacing'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
