import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/core/utils.dart';
import 'package:taskflow/data/app_store.dart';
import 'package:taskflow/data/capacity.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/task_repository.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/data/workload.dart';
import 'package:taskflow/screens/approvals_screen.dart';
import 'package:taskflow/screens/create_task_dialog.dart';
import 'package:taskflow/screens/planner_screen.dart';

// Adeel is in SEO and SMM. SEO gave him 2h, he has 1h 30m personal; SMM's
// manager assigns 6h more for the same day: SMM must see he's overloaded,
// and Adeel can ask SMM to move it.
void main() {
  // Friday 16 Oct 2026, 10:00.
  final now = DateTime(2026, 10, 16, 10);
  final fri = DateTime(2026, 10, 16);

  TaskItem task(String id, String to, DateTime day, int est,
          {String by = 'boss', Priority p = Priority.medium, String stage = TaskStage.todo}) =>
      TaskItem(
          id: id,
          title: 'Task $id',
          assigneeId: to,
          createdBy: by,
          assignedBy: by,
          priority: p,
          stage: stage,
          startAt: day,
          endAt: DateTime(day.year, day.month, day.day, 23, 59),
          createdAt: now,
          updatedAt: now,
          estimateMinutes: est);

  Team team(String id, String name, String owner, Map<String, TeamMemberInfo> members) => Team(
        id: id,
        name: name,
        color: 0xFF16A34A,
        ownerId: owner,
        memberIds: members.keys.toList(),
        managerIds: const [],
        members: members,
        createdAt: now,
        updatedAt: now,
      );

  group('busy time', () {
    test('per day: late work on today, sent-for-review and far days left out', () {
      final mine = [
        TaskRef(task('a', 'me', fri, 120)),
        TaskRef(task('late', 'me', DateTime(2026, 10, 13), 60)),
        TaskRef(task('rev', 'me', fri, 300, stage: TaskStage.review)),
        TaskRef(task('mon', 'me', DateTime(2026, 10, 19), 90)),
        TaskRef(task('far', 'me', DateTime(2026, 11, 20), 90)),
      ];
      final b = busyByDay(mine, now);
      expect(b, {'20261016': 180, '20261019': 90});
      expect(dayKey(DateTime(2026, 1, 5)), '20260105');
    });

    test('member info keeps work hours and busy time; sameAs skips equal writes', () {
      const i = TeamMemberInfo(
          name: 'Adeel',
          email: 'a@x.com',
          weekMinutes: 2550,
          dayMinutes: 510,
          workDays: [1, 2, 3, 4, 5],
          busy: {'20261016': 210});
      final back = TeamMemberInfo.fromMap(i.toMap());
      expect(back.sameAs(i), isTrue);
      expect(back.busy['20261016'], 210);
      expect(back.sameAs(const TeamMemberInfo(name: 'Adeel', email: 'a@x.com')), isFalse);
      expect(const TeamMemberInfo(name: 'A', email: 'b').toMap().keys, ['name', 'email']);
    });

    test("manager's view: visible work + elsewhere against their day", () {
      // Adeel shares 3h 30m busy on Friday (2h SEO + 1h 30m personal).
      final smm = team('SMM', 'SMM', 'boss', {
        'boss': const TeamMemberInfo(name: 'Boss', email: 'b@x.com'),
        'me': const TeamMemberInfo(
            name: 'Adeel',
            email: 'a@x.com',
            dayMinutes: 510,
            workDays: [1, 2, 3, 4, 5],
            busy: {'20261016': 210}),
      });
      final tasks = {'SMM': <TaskItem>[]};
      var l = loadOn('me', fri, [smm], (id) => tasks[id]!, now, team: smm);
      expect((l.visible, l.elsewhere, l.capacity), (0, 210, 510));
      expect(l.overloadWith(360), 60); // 6h more: 9h 30m on a 8h 30m day
      // Saturday is not his work day.
      expect(loadOn('me', DateTime(2026, 10, 17), [smm], (id) => tasks[id]!, now).capacity, 0);
      // Next day with room for 6h: Monday.
      expect(nextFreeDay('me', fri, 360, [smm], (id) => tasks[id]!, now), DateTime(2026, 10, 19));

      // Once SMM's 6h exist they count as visible, not twice.
      tasks['SMM'] = [task('s1', 'me', fri, 360)];
      l = loadOn('me', fri, [smm], (id) => tasks[id]!, now);
      expect((l.visible, l.elsewhere), (360, 0)); // his shared 210 is older
      // Not shared yet: the team's hours over Mon–Fri.
      final plain = team('P', 'P', 'boss', {
        'boss': const TeamMemberInfo(name: 'Boss', email: 'b@x.com'),
        'x': const TeamMemberInfo(name: 'X', email: 'x@x.com'),
      });
      expect(dayCapacity('x', fri, [plain]), 8 * 60);
    });

    test('workload counts busy elsewhere in the load', () {
      final smm = team('SMM', 'SMM', 'boss', {
        'boss': const TeamMemberInfo(name: 'Boss', email: 'b@x.com'),
        'me': const TeamMemberInfo(
            name: 'Adeel', email: 'a@x.com', busy: {'20261016': 570, '20261019': 120}),
      });
      final tasks = [task('s1', 'me', fri, 360)];
      final r = buildWorkload([smm], (_) => tasks, WorkloadPeriod.thisWeek, now);
      final m = r.members.firstWhere((m) => m.uid == 'me');
      expect(m.minutes, 360);
      expect(m.elsewhereMinutes, 210); // Friday only (Monday is next week)
      expect(m.totalMinutes, 570);
    });
  });

  group('screens', () {
    final seoTeam = team('SEO', 'SEO', 'seoboss', {
      'seoboss': const TeamMemberInfo(name: 'SEO Boss', email: 's@x.com'),
      'me': const TeamMemberInfo(name: 'Adeel', email: 'a@x.com'),
    });
    late Team smmTeam;

    void seed(String uid, {List<TaskItem>? smm}) {
      smmTeam = team('SMM', 'SMM', 'boss', {
        'boss': const TeamMemberInfo(name: 'SMM Boss', email: 'b@x.com'),
        'me': const TeamMemberInfo(
            name: 'Adeel',
            email: 'a@x.com',
            dayMinutes: 510,
            workDays: [1, 2, 3, 4, 5, 6, 7],
            busy: {}),
      });
      final today = dateOnly(DateTime.now());
      smmTeam.members['me'] = TeamMemberInfo(
          name: 'Adeel',
          email: 'a@x.com',
          dayMinutes: 510,
          workDays: const [1, 2, 3, 4, 5, 6, 7],
          busy: {dayKey(today): 210});
      AppStore.instance
        ..currentUser = null
        ..workStart = 9 * 60
        ..workEnd = 17 * 60 + 30
        ..workDays = const [1, 2, 3, 4, 5, 6, 7]
        ..tasks = [task('p1', 'me', today, 90, by: 'me')..assigneeId = null];
      TeamStore.instance
        ..teams = uid == 'boss' ? [smmTeam] : [seoTeam, smmTeam]
        ..invites = []
        ..setForTest(uid: uid, tasks: {
          if (uid != 'boss') 'SEO': [task('e1', 'me', today, 120, by: 'seoboss')],
          'SMM': smm ?? [],
        });
    }

    tearDown(() => AppStore.instance
      ..tasks = []
      ..workDays = AppStore.defaultWorkDays);

    testWidgets('SMM manager sees Adeel will be overloaded when assigning', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      seed('boss');
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
                onPressed: () => showCreateTask(context, team: smmTeam), child: const Text('open')),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select a team member'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adeel').last);
      await tester.pumpAndSettle();
      expect(find.text('Adeel has time'), findsOneWidget);

      await tester.tap(find.text('Not set'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('6 hours').last);
      await tester.pumpAndSettle();
      expect(find.text('Adeel will be overloaded'), findsOneWidget);
      expect(find.textContaining('already has 3h 30m'), findsOneWidget);
      expect(find.textContaining('outside this team'), findsOneWidget);
      expect(find.textContaining('1h over'), findsOneWidget);
      await tester.tap(find.textContaining('Move to '));
      await tester.pumpAndSettle();
      expect(find.text('Adeel has time'), findsOneWidget);
    });

    testWidgets('Adeel asks SMM to move a task; the manager moves it', (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final today = dateOnly(DateTime.now());
      final smmTasks = [
        task('s1', 'me', today, 360, p: Priority.high),
        task('s2', 'me', today, 60, p: Priority.low),
      ];
      seed('me', smm: smmTasks);
      await tester
          .pumpWidget(MaterialApp(theme: buildAppTheme(), home: const PlannerScreen(page: true)));
      await tester.pumpAndSettle();
      // 2h SEO + 1h 30m personal + 7h SMM.
      expect(find.textContaining('SEO 2h 00m'), findsOneWidget);
      expect(find.textContaining('SMM 7h 00m'), findsOneWidget);
      expect(find.text("Team tasks you can't move yourself"), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('ask_s1')), matching: find.text('Ask to move')));
      await tester.pumpAndSettle();
      expect(find.text('Ask to move this task'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '2 urgent SEO tasks today');
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();
      final asked = smmTasks.firstWhere((t) => t.moveAskedTo != null);
      expect(asked.moveAskedTo!.isAfter(today), isTrue);
      expect(asked.history.last.kind, HistoryKind.moveAsked);
      expect(find.text('Cancel request'), findsOneWidget);

      // The SMM manager sees it in Approvals and moves it.
      TeamStore.instance.setForTest(uid: 'boss', tasks: {'SMM': smmTasks});
      TeamStore.instance.teams = [smmTeam];
      expect(TeamStore.instance.moveRequestsForMe.length, 1);
      await tester
          .pumpWidget(MaterialApp(theme: buildAppTheme(), home: const ApprovalsScreen(page: true)));
      await tester.pumpAndSettle();
      expect(find.text('Date change requests (1)'), findsOneWidget);
      expect(find.text('"2 urgent SEO tasks today"'), findsOneWidget);
      final to = asked.moveAskedTo!;
      await tester.tap(find.text('Move'));
      await tester.pumpAndSettle();
      expect(asked.moveAskedTo, isNull);
      expect(dateOnly(asked.startAt), to);
      expect(asked.history.last.kind, HistoryKind.moveOk);
      expect(TeamStore.instance.moveRequestsForMe, isEmpty);
    });
  });
}
