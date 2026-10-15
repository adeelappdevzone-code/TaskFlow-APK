import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/app_store.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/screens/profile_screen.dart';

// Profile page on a laptop and on a phone, with sample data.
void main() {
  final now = DateTime.now();

  void seed() {
    final store = AppStore.instance;
    store.currentUser = AppUser(
      id: 'own',
      name: 'Adeel App Devzone',
      email: 'adeel@x.com',
      passwordHash: '',
      createdAt: DateTime(2026, 3, 1),
      updatedAt: now,
    );
    store.jobTitle = 'CEO';
    store.tasks = [
      TaskItem(
        id: 'p1',
        title: 'Prepare weekly report',
        status: TaskStatus.completed,
        startAt: now,
        completedAt: now.subtract(const Duration(hours: 2)),
        createdAt: now,
        updatedAt: now,
      ),
      TaskItem(id: 'p2', title: 'Plan', startAt: now, createdAt: now, updatedAt: now),
    ];
    TeamStore.instance
      ..teams = [
        Team(
          id: 'T',
          name: 'Marketing',
          color: 0xFFDB2777,
          ownerId: 'own',
          memberIds: ['own'],
          managerIds: [],
          members: {'own': const TeamMemberInfo(name: 'Adeel App Devzone', email: 'adeel@x.com')},
          createdAt: now.subtract(const Duration(days: 1)),
          updatedAt: now,
        ),
      ]
      ..invites = []
      ..setForTest(uid: 'own');
  }

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seed();
    await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const Scaffold(body: ProfileScreen())));
    await tester.pumpAndSettle();
  }

  testWidgets('laptop profile', (tester) async {
    await pump(tester, const Size(1600, 1100));
    expect(find.text('Adeel App Devzone'), findsWidgets);
    expect(find.text('CEO'), findsWidgets);
    expect(find.text('Team Owner'), findsOneWidget);
    expect(find.text('Profile Information'), findsOneWidget);
    expect(find.text('Quick Settings'), findsOneWidget);
    expect(find.text('Security & Account'), findsOneWidget);
    expect(find.text('Completed a task'), findsOneWidget);
    expect(find.text('Created a new team'), findsOneWidget);
    // Other tabs.
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Notification settings'), findsOneWidget);
    await tester.tap(find.text('Security & Backup'));
    await tester.pumpAndSettle();
    expect(find.text('Logout'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone profile', (tester) async {
    await pump(tester, const Size(400, 2600));
    expect(find.text('Total Tasks'), findsOneWidget);
    expect(find.text('Teams'), findsOneWidget);
    expect(find.text('Task reminders'), findsOneWidget);
    expect(find.text('Email verification'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
    // Edit name inline.
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
