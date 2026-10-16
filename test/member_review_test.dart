import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/app_store.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/task_repository.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/screens/approvals_screen.dart';
import 'package:taskflow/screens/task_page.dart';
import 'package:taskflow/screens/task_comments.dart';
import 'package:taskflow/screens/team_screen.dart';

void main() {
  final now = DateTime.now();
  final team = Team(
    id: 'T',
    name: 'SEO Dev',
    color: 0xFF16A34A,
    ownerId: 'boss',
    memberIds: ['boss', 'me'],
    managerIds: [],
    members: {
      'boss': const TeamMemberInfo(name: 'GlazeMe Nail Polish', email: 'b@x.com'),
      'me': const TeamMemberInfo(name: 'Adeel App Devzone', email: 'a@x.com'),
    },
    createdAt: now,
    updatedAt: now,
  );
  TaskItem t(String id, String title,
          {String by = 'boss', String stage = TaskStage.todo, bool done = false}) =>
      TaskItem(
          id: id,
          title: title,
          assigneeId: 'me',
          createdBy: by,
          stage: stage,
          status: done ? TaskStatus.completed : TaskStatus.pending,
          completedAt: done ? now : null,
          startAt: now,
          endAt: now.add(const Duration(hours: 1)),
          createdAt: now,
          updatedAt: now);

  void seed(String uid) {
    AppStore.instance
      ..currentUser = null
      ..tasks = [];
    TeamStore.instance
      ..teams = [team]
      ..invites = []
      ..setForTest(uid: uid, tasks: {
        'T': [
          t('given', 'Glaze me Collection banners'),
          t('mine', 'My own note', by: 'me'),
          t('rev', 'Glazeme Shopify Live', stage: TaskStage.review),
          t('fin', 'Old banner', done: true),
        ],
      });
  }

  test('who may finish', () {
    seed('me');
    final s = TeamStore.instance;
    final given = s.taskById('T', 'given')!;
    final mine = s.taskById('T', 'mine')!;
    expect(s.canFinish(team, given), isFalse);
    expect(TaskRef(given, team).sendsForReview, isTrue);
    expect(s.canFinish(team, mine), isTrue);
    expect(TaskRef(mine, team).sendsForReview, isFalse);
    // Ticking "done" on a manager's task does nothing by itself.
    s.setCompleted(team, given, true);
    expect(given.isCompleted, isFalse);
    seed('boss');
    expect(TeamStore.instance.canFinish(team, TeamStore.instance.taskById('T', 'given')!), isTrue);
  });

  test("member's finished team tasks are in My Tasks", () {
    seed('me');
    expect(
        TaskRepository.myTasks().where((r) => r.task.isCompleted).map((r) => r.task.id), ['fin']);
  });

  Future<void> page(WidgetTester tester, Widget w, {Size size = const Size(1500, 1000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: w));
    await tester.pumpAndSettle();
  }

  testWidgets('member: Send for review instead of Mark done; can add links', (tester) async {
    seed('me');
    await page(tester, const TaskPage(taskId: 'given', teamId: 'T'));
    expect(find.text('Mark done'), findsNothing);
    expect(find.text('Send for review'), findsWidgets);
    expect(find.text('Add link'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('member: own task can be marked done', (tester) async {
    seed('me');
    await page(tester, const TaskPage(taskId: 'mine', teamId: 'T'));
    expect(find.text('Mark done'), findsOneWidget);
  });

  testWidgets('member board has no Done column; owner board has it', (tester) async {
    seed('me');
    await page(tester, const TeamScreen(teamId: 'T'));
    expect(find.textContaining('Done', findRichText: true), findsNothing);
    expect(find.text('Old banner'), findsNothing);
    seed('boss');
    await page(tester, const TeamScreen(teamId: 'T'));
    expect(find.textContaining('Done', findRichText: true), findsWidgets);
    expect(find.text('Old banner'), findsOneWidget);
  });

  testWidgets('review page shows comments', (tester) async {
    seed('boss');
    await page(tester, const ReviewScreen(teamId: 'T', taskId: 'rev'));
    expect(find.byType(TaskComments), findsOneWidget);
    expect(find.text('Approve work'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
