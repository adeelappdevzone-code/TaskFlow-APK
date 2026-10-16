import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/app_store.dart';
import 'package:taskflow/data/inbox.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/screens/inbox_screen.dart';
import 'package:taskflow/screens/notifications_screen.dart';
import 'package:taskflow/screens/task_page.dart';

void main() {
  // Wednesday 14 Oct 2026, 10:00.
  final wed = DateTime(2026, 10, 14, 10);

  group('quick capture parsing', () {
    test('tomorrow + pm time + priority + tag', () {
      final r = parseCapture('Call Ali tomorrow 5pm !high #marketing', wed);
      expect(r.title, 'Call Ali');
      expect(r.due, DateTime(2026, 10, 15, 17));
      expect(r.allDay, isFalse);
      expect(r.priority, Priority.high);
      expect(r.tag, 'marketing');
    });

    test('a day without time is all day', () {
      final r = parseCapture('Pay rent on friday', wed);
      expect(r.title, 'Pay rent');
      expect(r.due, DateTime(2026, 10, 16));
      expect(r.allDay, isTrue);
    });

    test('same weekday means next week', () {
      expect(parseCapture('Standup wednesday', wed).due, DateTime(2026, 10, 21));
    });

    test('24h time today, or tomorrow when already past', () {
      expect(parseCapture('Report at 14:00', wed).due, DateTime(2026, 10, 14, 14));
      expect(parseCapture('Report 9:30', wed).due, DateTime(2026, 10, 15, 9, 30));
    });

    test('dates: 19 oct, oct 19, next week, in 3 days, tonight', () {
      expect(parseCapture('Follow up 19 oct', wed).due, DateTime(2026, 10, 19));
      expect(parseCapture('Follow up Oct 19', wed).due, DateTime(2026, 10, 19));
      expect(parseCapture('Visa 3 jan', wed).due, DateTime(2027, 1, 3)); // past → next year
      expect(parseCapture('Plan next week', wed).due, DateTime(2026, 10, 21));
      expect(parseCapture('Plan in 3 days', wed).due, DateTime(2026, 10, 17));
      expect(parseCapture('Movie tonight', wed).due, DateTime(2026, 10, 14, 20));
      expect(parseCapture('12am backup today', wed).due, DateTime(2026, 10, 14, 0));
    });

    test('plain text stays as is', () {
      final r = parseCapture('Buy office supplies', wed);
      expect(r.title, 'Buy office supplies');
      expect(r.due, isNull);
      expect(r.priority, isNull);
      expect(r.tag, isNull);
    });

    test('email: subject is the title, Re/Fwd removed', () {
      expect(parseEmail('Re: Fwd: Contract', 'Please sign'), ('Contract', 'Please sign'));
      expect(parseEmail('', 'Budget proposal\nNumbers attached'),
          ('Budget proposal', 'Numbers attached'));
    });
  });

  final now = DateTime.now();
  final team = Team(
    id: 'T',
    name: 'Marketing',
    color: 0xFFDB2777,
    ownerId: 'own',
    memberIds: ['own', 'ali'],
    managerIds: [],
    members: {
      'own': const TeamMemberInfo(name: 'Adeel App', email: 'a@x.com'),
      'ali': const TeamMemberInfo(name: 'Ali Khan', email: 'ali@x.com'),
    },
    createdAt: now,
    updatedAt: now,
  );
  final memberTeam = Team(
    id: 'M',
    name: 'Design',
    color: 0xFF16A34A,
    ownerId: 'ali',
    memberIds: ['own', 'ali'],
    managerIds: [],
    members: team.members,
    createdAt: now,
    updatedAt: now,
  );

  InboxItem item(String id, String title,
          {String source = InboxSource.quick, DateTime? due, String? teamId, Priority? p}) =>
      InboxItem(
          id: id,
          title: title,
          source: source,
          createdAt: now.subtract(Duration(minutes: id.hashCode % 50)),
          dueAt: due,
          allDay: due != null && due.hour == 0,
          teamId: teamId,
          priority: p);

  void seed() {
    AppStore.instance
      ..currentUser = null
      ..categories = [
        Category(id: 'c', name: 'Product', color: 0xFF7C3AED, createdAt: now, updatedAt: now),
      ]
      ..notifications = [];
    TeamStore.instance
      ..teams = [team, memberTeam]
      ..invites = []
      ..setForTest(uid: 'own', tasks: {
        'T': [
          TaskItem(
              id: 'r1',
              title: 'Homepage design',
              assigneeId: 'ali',
              stage: TaskStage.review,
              startAt: now,
              createdAt: now,
              updatedAt: now),
        ],
      });
    InboxStore.instance.setForTest(uid: 'own', items: [
      item('1', 'Book flight for design conference', source: InboxSource.email),
      item('2', 'Review the latest product feedback'),
      item('3', 'Call with marketing team',
          source: InboxSource.voice, due: now.add(const Duration(days: 1))),
      item('4', 'Follow up with client about the contract',
          source: InboxSource.forwarded,
          due: DateTime(now.year, now.month, now.day + 3),
          p: Priority.high),
      item('5', 'Plan team building activity', teamId: 'T'),
    ]);
  }

  test('suggestions: team, label and dates', () {
    seed();
    final s = inboxSuggestions(InboxStore.instance.items, [team], AppStore.instance.categories);
    expect(s.map((x) => x.kind), [SuggestionKind.team, SuggestionKind.label, SuggestionKind.dates]);
    expect(s[0].itemIds, ['3']); // "marketing" (item 5 already has a team)
    expect(s[1].itemIds, ['2']); // "product"
    expect(s[2].itemIds.toSet(), {'1', '2', '5'});
  });

  test('capture: #team is picked up, unknown tags stay in the title', () {
    seed();
    final a = InboxStore.instance.capture('Ads budget tomorrow !low #marketing')!;
    expect(a.teamId, 'T');
    expect(a.title, 'Ads budget');
    expect(a.priority, Priority.low);
    expect(a.allDay, isTrue);
    final b = InboxStore.instance.capture('Fix bug #urgentstuff')!;
    expect(b.teamId, isNull);
    expect(b.title, 'Fix bug #urgentstuff');
    final c = InboxStore.instance.capture('Spec #product')!;
    expect(c.categoryId, 'c');
  });

  test('task made from an item; members can only take it themselves', () {
    seed();
    final i = item('x', 'Write copy', teamId: 'M', due: DateTime(2026, 10, 20, 15))
      ..assigneeId = 'ali';
    expect(InboxStore.instance.problem(i), isNotNull);
    i.assigneeId = null;
    expect(InboxStore.instance.problem(i), isNull);
    final t = InboxStore.instance.taskFor(i);
    expect(t.assigneeId, 'own');
    expect(t.startAt, DateTime(2026, 10, 20, 15));
    expect(t.endAt, DateTime(2026, 10, 20, 16));

    final p = item('y', 'Groceries');
    final pt = InboxStore.instance.taskFor(p, day: DateTime(2026, 10, 22));
    expect(pt.isAllDay, isTrue);
    expect(pt.startAt, DateTime(2026, 10, 22));
  });

  test('notification tabs', () {
    expect(NotifKind.tabOf(NotifKind.mention), 'mentions');
    expect(NotifKind.tabOf(NotifKind.changes), 'approvals');
    expect(NotifKind.tabOf('completed'), isNull);
  });

  Future<void> show(WidgetTester tester, Size size, Widget page) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seed();
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: page));
    await tester.pumpAndSettle();
  }

  testWidgets('inbox on a laptop', (tester) async {
    await show(tester, const Size(1600, 1100), const InboxScreen());
    expect(find.text('Quick Capture'), findsWidgets);
    expect(find.text('5 inbox items'), findsOneWidget);
    expect(find.text('Need due date'), findsOneWidget);
    expect(find.text('Organize suggestions'), findsOneWidget);
    expect(find.text('Capture sources'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Marketing'), findsWidgets); // team chip on item 5
    expect(tester.takeException(), isNull);

    // Filter by a stat tile.
    await tester.tap(find.text('From voice'));
    await tester.pumpAndSettle();
    expect(find.text('1 inbox item'), findsOneWidget);

    // Capture a new one.
    await tester.tap(find.text('From voice'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Send invoice friday !high');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('6 inbox items'), findsOneWidget);
    expect(find.text('Send invoice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inbox on a phone', (tester) async {
    await show(tester, const Size(400, 860), const InboxScreen(page: true));
    expect(find.text('5 inbox items'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  void notifs() {
    AppNotification n(String id, String kind, String title, String body,
            {int minsAgo = 5, bool read = false, String? task, String? actor}) =>
        AppNotification(
          id: id,
          type: 'task',
          kind: kind,
          title: title,
          body: body,
          taskId: task,
          teamId: task == null ? null : 'T',
          actorName: actor,
          createdAt: now.subtract(Duration(minutes: minsAgo)),
          readAt: read ? now : null,
        );
    AppStore.instance.notifications = [
      n('a', NotifKind.mention, 'Ali Khan mentioned you in Homepage design',
          '@Adeel can you check the layout?',
          task: 'r1', actor: 'Ali Khan'),
      n('b', NotifKind.assigned, 'SEO task was assigned to you', 'By Ali Khan.', minsAgo: 60),
      n('c', NotifKind.reminder, 'Reminder: Client call starts in 15 minutes', 'Personal',
          minsAgo: 90),
      n('d', NotifKind.approval, 'Homepage design is awaiting your approval',
          'Ali Khan sent it for review.',
          task: 'r1', minsAgo: 60 * 26, read: true),
    ];
  }

  testWidgets('notification center on a laptop', (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seed();
    notifs();
    await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const NotificationsScreen(page: false)));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Snooze'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget); // on the notification
    await tester.tap(find.text('Approvals').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Waiting for your approval'), findsOneWidget);
    await tester.tap(find.text('All').first);
    await tester.pumpAndSettle();
    expect(find.text('Notification settings'), findsOneWidget);
    expect(find.text('Unread overview'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Mentions').first);
    await tester.pumpAndSettle();
    expect(find.text('Snooze'), findsNothing);
    expect(find.text('Reply'), findsOneWidget);
  });

  testWidgets('notification center on a phone', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seed();
    notifs();
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const NotificationsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('task page: approve for managers, send for approval for members', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seed();
    await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const TaskPage(taskId: 'r1', teamId: 'T')));
    await tester.pumpAndSettle();
    expect(find.text('Awaiting approval'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Request changes'), findsOneWidget);

    // Ali (plain member) on his own task in To Do.
    TeamStore.instance.setForTest(uid: 'ali', tasks: {
      'T': [
        TaskItem(
            id: 'r2',
            title: 'Banner',
            assigneeId: 'ali',
            startAt: now,
            createdAt: now,
            updatedAt: now),
      ],
    });
    await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const TaskPage(taskId: 'r2', teamId: 'T')));
    await tester.pumpAndSettle();
    expect(find.text('Send for approval'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
