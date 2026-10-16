import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/approvals.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/screens/approvals_screen.dart';

void main() {
  final now = DateTime.now();
  DateTime ago(int hours) => now.subtract(Duration(hours: hours));
  TaskEvent ev(String kind, String by, int hoursAgo, {String? to, String? note}) =>
      TaskEvent(kind: kind, by: by, at: ago(hoursAgo), to: to, note: note);

  final team = Team(
    id: 'T',
    name: 'UI UX',
    color: 0xFF1F6FEB,
    ownerId: 'own',
    memberIds: ['own', 'ali'],
    managerIds: [],
    members: {
      'own': const TeamMemberInfo(name: 'Adeel Devzone', email: 'a@x.com'),
      'ali': const TeamMemberInfo(name: 'Ali Khan', email: 'ali@x.com'),
    },
    createdAt: ago(200),
    updatedAt: now,
  );

  TaskItem task(String id, String title,
          {String stage = TaskStage.todo,
          bool done = false,
          List<TaskEvent> history = const [],
          List<TaskLink> links = const []}) =>
      TaskItem(
        id: id,
        title: title,
        assigneeId: 'ali',
        stage: stage,
        status: done ? TaskStatus.completed : TaskStatus.pending,
        completedAt: done ? ago(1) : null,
        startAt: now.add(const Duration(days: 2)),
        endAt: now.add(const Duration(days: 2, hours: 1)),
        createdAt: ago(100),
        updatedAt: ago(1),
      )
        ..history = [...history]
        ..links = [...links];

  // Sent → changes → sent again (waiting).
  final homepage = task('h', 'Homepage Design', stage: TaskStage.review, history: [
    ev(HistoryKind.created, 'own', 90),
    ev(HistoryKind.submitted, 'ali', 50, to: TaskStage.review, note: 'All three sizes are ready.'),
    ev(HistoryKind.changes, 'own', 26,
        to: TaskStage.doing, note: 'Looks great!\n1. New headline\n2. Brand blue button'),
    ev(HistoryKind.submitted, 'ali', 2, to: TaskStage.review, note: 'Changes done.'),
  ], links: [
    const TaskLink(title: 'homepage-desktop', url: 'https://www.figma.com/file/abc'),
    const TaskLink(url: 'https://drive.google.com/x'),
  ]);
  // Dragged to Review, approved 4 h later.
  final logo = task('l', 'Logo', done: true, history: [
    ev(HistoryKind.stage, 'ali', 10, to: TaskStage.review),
    ev(HistoryKind.approved, 'own', 6),
  ]);
  // Changes asked, not sent again yet.
  final banner = task('b', 'Banner', stage: TaskStage.doing, history: [
    ev(HistoryKind.submitted, 'ali', 30, to: TaskStage.review),
    ev(HistoryKind.changes, 'own', 28, to: TaskStage.doing),
  ]);
  final plain = task('p', 'Plain task');

  void seed({String uid = 'own'}) {
    TeamStore.instance
      ..teams = [team]
      ..invites = []
      ..setForTest(uid: uid, tasks: {
        'T': [homepage, logo, banner, plain],
      });
  }

  test('state of each task', () {
    expect(approvalStateOf(homepage), ApprovalState.pending);
    expect(approvalStateOf(logo), ApprovalState.approved);
    expect(approvalStateOf(banner), ApprovalState.changes);
    expect(approvalStateOf(plain), isNull);
    expect(lastSubmission(homepage)!.note, 'Changes done.');
  });

  test('stats: requests, decisions, average time, on time', () {
    final s = approvalStats([homepage, logo, banner, plain]);
    expect(s.requests, 4);
    expect(s.approved, 1);
    expect(s.changes, 2);
    expect(s.pending, 1);
    // 24 h (homepage), 4 h (logo), 2 h (banner) → 10 h.
    expect(s.averageTime, const Duration(hours: 10));
    expect(s.onTime, 1);
    expect(approvalTimeText(s.averageTime), '10 h');
    expect(approvalTimeText(const Duration(hours: 43)), '1.8 days');
  });

  test('items: managers see all, members only their own', () {
    seed();
    expect(approvalItems([team], TeamStore.instance.tasksOf, 'own').length, 3);
    final other = Team(
        id: 'O',
        name: 'Other',
        color: 1,
        ownerId: 'zz',
        memberIds: ['zz', 'own'],
        managerIds: [],
        members: const {},
        createdAt: now,
        updatedAt: now);
    List<TaskItem> tasksOf(String id) => id == 'O'
        ? [
            task('x', 'Not mine', stage: TaskStage.review)..assigneeId = 'zz',
            task('y', 'Mine', stage: TaskStage.review)..assigneeId = 'own',
          ]
        : const [];
    expect(approvalItems([other], tasksOf, 'own').map((i) => i.task.title), ['Mine']);
  });

  test('feedback text numbers the points', () {
    expect(feedbackText(' Nice work ', ['Headline', ' ', 'Colors']),
        'Nice work\n1. Headline\n2. Colors');
    expect(feedbackText('', []), '');
  });

  test('history note survives toMap / fromMap', () {
    final e = TaskEvent.tryFrom(ev(HistoryKind.changes, 'own', 1, note: 'Fix it').toMap())!;
    expect(e.note, 'Fix it');
    expect(TaskEvent.tryFrom(ev(HistoryKind.done, 'own', 1).toMap())!.note, isNull);
  });

  Future<void> show(WidgetTester tester, Size size, Widget page, {String uid = 'own'}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seed(uid: uid);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: page));
    await tester.pumpAndSettle();
  }

  for (final (name, size) in [
    ('laptop', const Size(1600, 1100)),
    ('phone', const Size(400, 860))
  ]) {
    testWidgets('approval center on a $name', (tester) async {
      await show(tester, size, const ApprovalsScreen(page: true));
      expect(find.text('Pending (1)'), findsOneWidget);
      expect(find.text('Homepage Design'), findsWidgets);
      expect(find.text('Review'), findsOneWidget);
      expect(find.text('Approval summary'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Changes requested').first);
      await tester.pumpAndSettle();
      expect(find.text('Banner'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('review page on a $name', (tester) async {
      await show(tester, size, const ReviewScreen(teamId: 'T', taskId: 'h'));
      expect(find.text('Deliverables (2)'), findsOneWidget);
      expect(find.text('Changes done.'), findsOneWidget);
      expect(find.text('Version 2'), findsOneWidget);
      expect(find.text('Approve work'), findsOneWidget);
      expect(find.text('Request changes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('request changes page on a $name', (tester) async {
      await show(tester, size, const RequestChangesScreen(teamId: 'T', taskId: 'h'));
      await tester.tap(find.text('Add another change'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Send feedback'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('approval history on a $name', (tester) async {
      await show(tester, size, const ApprovalHistoryScreen(teamId: 'T', taskId: 'h'));
      expect(find.text('New version submitted'), findsOneWidget);
      expect(find.text('Changes requested'), findsWidgets);
      expect(find.text('Sent for approval'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('member: no approve buttons, can send a new version', (tester) async {
    await show(tester, const Size(1400, 1000), const ReviewScreen(teamId: 'T', taskId: 'b'),
        uid: 'ali');
    expect(find.text('Approve work'), findsNothing);
    expect(find.text('Send new version'), findsOneWidget);
  });

  test('report text', () {
    final r = ApprovalHistoryScreen.report(team, homepage);
    expect(r, contains('Approval history: Homepage Design (UI UX)'));
    expect(r, contains('New version submitted by Ali Khan'));
    expect(r, contains('1. New headline'));
  });
}
