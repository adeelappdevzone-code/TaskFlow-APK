import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/app_store.dart';
import 'package:taskflow/data/chat_store.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/screens/main_shell.dart';

// Phone: bottom bar Home | My Tasks | (+) | Chats | Menu; Menu opens the side
// menu as a drawer.
void main() {
  final now = DateTime.now();
  final team = Team(
    id: 'T',
    name: 'SEO Dev',
    color: 0xFF16A34A,
    ownerId: 'me',
    memberIds: ['me', 'wa'],
    managerIds: [],
    members: {
      'me': const TeamMemberInfo(name: 'Adeel', email: 'a@x.com'),
      'wa': const TeamMemberInfo(name: 'Waseem', email: 'w@x.com'),
    },
    createdAt: now,
    updatedAt: now,
  );

  testWidgets('menu drawer opens pages and teams', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppStore.instance.tasks = [];
    TeamStore.instance
      ..teams = [team]
      ..invites = []
      ..setForTest(uid: 'me', tasks: {});
    ChatStore.instance.setForTest(uid: 'me');
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const MainShell()));
    await tester.pumpAndSettle();

    for (final l in ['Home', 'My Tasks', 'Chats', 'Menu']) {
      expect(find.text(l), findsOneWidget);
    }
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Daily Planner'), findsOneWidget);
    expect(find.text('MY TEAMS'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Reports').last);
    await tester.pumpAndSettle();
    expect(find.text('Daily Planner'), findsNothing); // drawer closed
    expect(find.widgetWithText(AppBar, 'Reports'), findsOneWidget); // page shown

    await tester.tap(find.text('Chats'));
    await tester.pumpAndSettle();
    expect(find.text('Messages'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
