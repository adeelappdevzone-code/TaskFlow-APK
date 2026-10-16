import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/app_store.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/planner.dart';
import 'package:taskflow/data/task_repository.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/screens/planner_screen.dart';

void main() {
  final day = DateTime(2026, 10, 14);
  DateTime at(int h, [int m = 0, int d = 0]) => DateTime(2026, 10, 14 + d, h, m);

  TaskItem timed(String id, String title, int h, int m, int len) => TaskItem(
      id: id,
      title: title,
      startAt: at(h, m),
      endAt: at(h, m).add(Duration(minutes: len)),
      createdAt: day,
      updatedAt: day);
  TaskItem flexible(String id, String title, Priority p, int? est, {int dayOffset = 0}) => TaskItem(
      id: id,
      title: title,
      priority: p,
      startAt: at(0, 0, dayOffset),
      endAt: at(23, 59, dayOffset),
      createdAt: day,
      updatedAt: day,
      estimateMinutes: est);

  List<TaskRef> tasks() => [
        TaskRef(timed('s', 'Team standup', 9, 0, 30)),
        TaskRef(timed('c', 'Client call', 11, 30, 30)),
        TaskRef(timed('m', 'Marketing sync', 15, 0, 30)),
        TaskRef(flexible('q', 'Q4 budget proposal', Priority.high, 120)),
        TaskRef(flexible('f', 'Review product feedback', Priority.medium, 60, dayOffset: -2)),
        TaskRef(flexible('d', 'Design new feature', Priority.high, 120)),
        TaskRef(flexible('r', 'Prepare user research report', Priority.low, 90)),
        TaskRef(flexible('u', 'Update onboarding docs', Priority.low, null)),
        TaskRef(flexible('t', 'Tomorrow thing', Priority.low, 60, dayOffset: 1)),
      ];

  test('overloaded day: numbers and suggestions', () {
    final plan = planDay(tasks(), day, at(8), workStart: 9 * 60, workEnd: 15 * 60 + 30);
    expect(plan.availableMinutes, 390);
    // 3 x 30 fixed + 120 + 60 + 120 + 90 + 30 (no estimate)
    expect(plan.plannedMinutes, 510);
    expect(plan.overloadMinutes, 120);
    expect(plan.overdueCount, 1);
    expect(plan.unestimatedCount, 1);
    final move = plan.suggestions.firstWhere((s) => s.kind == RescueKind.moveLow);
    expect(move.tasks.map((r) => r.task.id), ['r', 'u']);
    expect(move.saves, 120);
    expect(plan.suggestions.map((s) => s.kind),
        [RescueKind.moveLow, RescueKind.overdue, RescueKind.timeBlock]);

    final all = {RescueKind.moveLow, RescueKind.overdue, RescueKind.timeBlock};
    final after = plan.after(all);
    expect(after.fold(0, (s, e) => s + e.minutes), 390);
    expect(after.any((e) => e.mark == PlanMark.overloaded), isFalse);
    expect(after.firstWhere((e) => e.ref.task.id == 'q').mark, PlanMark.focus);
    expect(after.firstWhere((e) => e.ref.task.id == 'f').mark, PlanMark.rescheduled);
    // Fixed tasks keep their time, nothing overlaps them.
    expect(after.firstWhere((e) => e.ref.task.id == 'c').start, at(11, 30));
    for (final e in after.where((e) => !e.fixed)) {
      for (final f in after.where((e) => e.fixed)) {
        expect(e.end.isAfter(f.start) && e.start.isBefore(f.end), isFalse,
            reason: '${e.ref.task.title} overlaps ${f.ref.task.title}');
      }
    }

    final changes = rescueChanges(plan, all);
    final byId = {for (final e in changes.entries) e.key.task.id: e.value};
    expect(byId['r']!.$1, DateTime(2026, 10, 15));
    expect(byId['q']!.$1, at(9, 30));
    expect(byId.containsKey('s'), isFalse);
  });

  test('a day that fits has no move suggestion', () {
    final plan = planDay(tasks().take(4).toList(), day, at(8));
    expect(plan.overloadMinutes, 0);
    expect(plan.suggestions.map((s) => s.kind), [RescueKind.timeBlock]);
  });

  test('today starts now; meetings already over are left out', () {
    final plan = planDay(tasks(), day, at(12, 5), workStart: 9 * 60, workEnd: 17 * 60);
    expect(plan.windowStart, at(12, 15));
    expect(plan.before.any((e) => e.ref.task.id == 's'), isFalse);
  });

  test('estimate survives toMap / fromMap', () {
    final t = flexible('x', 'X', Priority.low, 45);
    expect(TaskItem.fromMap(t.toMap()).estimateMinutes, 45);
    expect(
        TaskItem.fromMap(flexible('y', 'Y', Priority.low, null).toMap()).estimateMinutes, isNull);
  });

  for (final (name, size) in [
    ('laptop', const Size(1600, 1200)),
    ('phone', const Size(400, 860))
  ]) {
    testWidgets('planner on a $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      TeamStore.instance
        ..teams = []
        ..setForTest(uid: 'own');
      AppStore.instance
        ..workStart = 0
        ..workEnd = 23 * 60 + 59
        ..tasks = [
          for (var i = 0; i < 12; i++)
            TaskItem(
                id: 'p$i',
                title: 'Task number $i',
                priority: Priority.values[i % 3],
                startAt: today,
                endAt: today.add(const Duration(hours: 23, minutes: 59)),
                createdAt: today,
                updatedAt: today,
                estimateMinutes: i == 0 ? null : 180),
        ];
      await tester
          .pumpWidget(MaterialApp(theme: buildAppTheme(), home: const PlannerScreen(page: true)));
      await tester.pumpAndSettle();
      expect(find.textContaining("overloaded by"), findsOneWidget);
      expect(find.text('Set time'), findsWidgets);
      await tester.scrollUntilVisible(find.text('After rescue'), 400,
          scrollable: find.byType(Scrollable).first);
      await tester.scrollUntilVisible(find.text('Rescue suggestions'), 400,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Rescue suggestions'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
