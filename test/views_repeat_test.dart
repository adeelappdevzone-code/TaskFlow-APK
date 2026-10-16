import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/app_store.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/screens/tasks_screen.dart';

void main() {
  DateTime at(int y, int m, int d, [int h = 9]) => DateTime(y, m, d, h);
  // Wed 14 Oct 2026.
  final wed = at(2026, 10, 14);

  test('new repeats', () {
    expect(nextOccurrence(wed, Repeat.weekdays, wed), at(2026, 10, 15));
    expect(nextOccurrence(at(2026, 10, 16), Repeat.weekdays, wed), at(2026, 10, 19)); // Fri→Mon
    expect(nextOccurrence(wed, Repeat.biweekly, wed), at(2026, 10, 28));
    expect(nextOccurrence(at(2026, 10, 31), Repeat.monthEnd, wed), at(2026, 11, 30));
    expect(nextOccurrence(at(2027, 1, 31), Repeat.monthEnd, at(2027, 1, 31)), at(2027, 2, 28));
    expect(nextOccurrence(at(2024, 2, 29), Repeat.yearly, at(2024, 3, 1)), at(2025, 2, 28));
    final monThu = Repeat.onDays([4, 1]);
    expect(monThu, 'days:1,4');
    expect(Repeat.label(monThu), 'Every Mon, Thu');
    expect(nextOccurrence(wed, monThu, wed), at(2026, 10, 15)); // Thu
    expect(nextOccurrence(at(2026, 10, 15), monThu, wed), at(2026, 10, 19)); // Mon
    // Finished late: skips to the next one from today.
    expect(nextOccurrence(at(2026, 10, 1), monThu, wed), at(2026, 10, 15));
    expect(Repeat.isOn(monThu), isTrue);
    expect(Repeat.isValid('days:9'), isFalse);
    expect(Repeat.isOn('weird'), isFalse);
  });

  test('repeat survives toMap / fromMap', () {
    final t = TaskItem(
        id: 'x', title: 'X', startAt: wed, createdAt: wed, updatedAt: wed, repeat: 'days:2,5');
    expect(TaskItem.fromMap(t.toMap()).repeat, 'days:2,5');
    expect(TaskItem.fromMap({...t.toMap(), 'repeat': 'days:'}).repeat, Repeat.none);
  });

  test('saved view round trip', () {
    const v = SavedView(id: 'a', name: 'Urgent', tab: 'overdue', priority: 2, board: true);
    final b = SavedView.tryFrom(v.toMap())!;
    expect((b.tab, b.priority, b.board, b.byMe), ('overdue', 2, true, false));
  });

  for (final (name, size) in [
    ('laptop', const Size(1500, 1000)),
    ('phone', const Size(400, 860))
  ]) {
    testWidgets('saved views on $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      AppStore.instance
        ..currentUser = null
        ..savedViews = [
          const SavedView(id: 'v', name: 'High only', priority: 2),
        ]
        ..tasks = [
          TaskItem(
              id: 'h',
              title: 'Big one',
              priority: Priority.high,
              startAt: now,
              createdAt: now,
              updatedAt: now),
          TaskItem(
              id: 'l',
              title: 'Small one',
              priority: Priority.low,
              startAt: now,
              createdAt: now,
              updatedAt: now),
        ];
      TeamStore.instance
        ..teams = []
        ..setForTest(uid: 'own');
      await tester.pumpWidget(
          MaterialApp(theme: buildAppTheme(), home: const Scaffold(body: TasksScreen())));
      await tester.pumpAndSettle();
      final before = find.text('Small one').evaluate().length;
      expect(before, greaterThan(0));
      expect(find.text('Save view'), findsOneWidget);
      await tester.tap(find.text('High only'));
      await tester.pumpAndSettle();
      expect(find.text('Small one').evaluate().length, lessThan(before));
      expect(find.text('Big one'), findsWidgets);
      expect(find.text('Save view'), findsNothing); // this view is active
      expect(tester.takeException(), isNull);
    });
  }
}
