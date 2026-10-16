import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/app_store.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/reports.dart';
import 'package:taskflow/data/task_repository.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/data/template_library.dart';
import 'package:taskflow/data/time_report.dart';
import 'package:taskflow/screens/reports_screen.dart';
import 'package:taskflow/screens/templates_screen.dart';

void main() {
  final now = DateTime.now();
  final month = DateTime(now.year, now.month);
  DateTime d(int day, [int h = 10]) => month.add(Duration(days: day, hours: h));

  final team = Team(
    id: 'T',
    name: 'Website Redesign',
    color: 0xFF1F6FEB,
    ownerId: 'own',
    memberIds: ['own', 'hm'],
    managerIds: [],
    members: {
      'own': const TeamMemberInfo(name: 'Adeel Devzone', email: 'a@x.com'),
      'hm': const TeamMemberInfo(name: 'Harry Mosa', email: 'h@x.com'),
    },
    createdAt: month,
    updatedAt: month,
  );
  TaskItem t(String id, int day, {String? to, bool done = false, String stage = 'todo'}) =>
      TaskItem(
        id: id,
        title: 'Task $id',
        assigneeId: to,
        stage: stage,
        status: done ? TaskStatus.completed : TaskStatus.pending,
        completedAt: done ? d(day, 12) : null,
        startAt: d(day),
        endAt: d(day, 11),
        createdAt: month,
        updatedAt: month,
      );

  void seed() {
    AppStore.instance
      ..tasks = [t('p1', 0, done: true), t('p2', 1)]
      ..templates = [
        TaskTemplate(
            id: 'mine', name: 'My checklist', title: 'Do it', createdAt: month, checklist: ['a'])
      ]
      ..projects = [];
    TeamStore.instance
      ..teams = [team]
      ..invites = []
      ..setForTest(uid: 'own', tasks: {
        'T': [
          t('a', 0, to: 'hm', done: true),
          t('b', 1, to: 'hm', stage: 'doing'),
          t('c', 0, to: 'own'),
          // Last month: for the change %.
          TaskItem(
              id: 'old',
              title: 'Old',
              startAt: month.subtract(const Duration(days: 3)),
              createdAt: month,
              updatedAt: month,
              assigneeId: 'own'),
        ],
      })
      ..setTemplatesForTest('T', [
        TaskTemplate(
          id: 'tt',
          name: 'Team flow',
          title: 'Step 1',
          createdAt: month,
          category: 'Agency',
          tasks: [TemplateTask(title: 'Step 1'), TemplateTask(title: 'Step 2', offsetDays: 3)],
        )..teamId = 'T',
      ]);
  }

  test('report numbers, people and projects', () {
    seed();
    final (s, e) = rangeDates(ReportRange.thisMonth, now);
    final later = month.add(const Duration(days: 20));
    final r = buildReport(reportTasks(), s, e, later);
    expect(r.numbers.total, 5);
    expect(r.numbers.completed, 2);
    expect(r.previous.total, 1);
    expect(changePct(1, 5), 400);
    final hm = r.people.firstWhere((p) => p.uid == 'hm');
    expect(hm.assigned, 2);
    expect(hm.completed, 1);
    expect(r.byProject.first.$1, 'Website Redesign');
    expect(r.trend, isNotEmpty);
  });

  test('ranges', () {
    final wed = DateTime(2026, 10, 14);
    expect(rangeDates(ReportRange.lastWeek, wed), (DateTime(2026, 10, 5), DateTime(2026, 10, 12)));
    expect(rangeDates(ReportRange.lastMonth, wed), (DateTime(2026, 9), DateTime(2026, 10)));
  });

  test('PDF is made', () async {
    seed();
    final (s, e) = rangeDates(ReportRange.thisMonth, now);
    final r = buildReport(reportTasks(), s, e, now);
    final bytes = await buildReportPdf(r, timeRows(timeTasks(), s, e), by: 'Adeel', range: 'x');
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('templates: library, workflow, round trip', () {
    seed();
    expect(builtInTemplates.length, greaterThanOrEqualTo(10));
    expect(builtInTemplates.every((t) => t.workflow.isNotEmpty && t.builtIn), isTrue);
    expect(allTemplates().map((t) => t.id), containsAll(['mine', 'tt', 'builtin-website']));
    final mine = AppStore.instance.templates.first;
    expect(mine.workflow.single.checklist, ['a']);
    final tt = TeamStore.instance.teamTemplates.single;
    expect(tt.spanDays, 4);
    final back = TaskTemplate.fromMap(tt.toMap());
    expect(back.tasks.map((x) => x.offsetDays), [0, 3]);
    expect(back.category, 'Agency');
  });

  for (final (name, size) in [
    ('laptop', const Size(1600, 1100)),
    ('phone', const Size(400, 860))
  ]) {
    testWidgets('reports on a $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      seed();
      await tester
          .pumpWidget(MaterialApp(theme: buildAppTheme(), home: const ReportsScreen(page: true)));
      await tester.pumpAndSettle();
      expect(find.text('Total tasks'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final tab in ['Team', 'Projects', 'Time Tracking']) {
        await tester.tap(find.text(tab).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
    });

    testWidgets('templates on a $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      seed();
      await tester
          .pumpWidget(MaterialApp(theme: buildAppTheme(), home: const TemplatesScreen(page: true)));
      await tester.pumpAndSettle();
      expect(find.text('Website Project'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.textContaining('Operations').first);
      await tester.pumpAndSettle();
      expect(find.text('Website Project'), findsNothing);
      expect(find.text('Client Onboarding'), findsOneWidget);
      await tester.tap(find.text('Use Template').first);
      await tester.pumpAndSettle();
      expect(find.text('Create tasks'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('template editor', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seed();
    await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: TemplateEditScreen(template: builtInTemplates.first, isCopy: true)));
    await tester.pumpAndSettle();
    expect(find.text('Tasks (${builtInTemplates.first.workflow.length})'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('TaskRef sources for reports', () {
    seed();
    expect(reportTasks().where((r) => r.isTeam).length, 4);
    expect(reportTasks().whereType<TaskRef>().length, 6);
  });
}
