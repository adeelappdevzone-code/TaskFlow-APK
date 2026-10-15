import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/models.dart';

void main() {
  final mon = DateTime(2026, 4, 13, 9, 30); // Monday

  test('next occurrence: daily / weekly / monthly', () {
    expect(nextOccurrence(mon, Repeat.daily, mon), DateTime(2026, 4, 14, 9, 30));
    expect(nextOccurrence(mon, Repeat.weekly, mon), DateTime(2026, 4, 20, 9, 30));
    expect(nextOccurrence(mon, Repeat.monthly, mon), DateTime(2026, 5, 13, 9, 30));
  });

  test('monthly keeps the day, or uses the last day of short months', () {
    final jan31 = DateTime(2026, 1, 31, 10);
    final feb = nextOccurrence(jan31, Repeat.monthly, jan31);
    expect(feb, DateTime(2026, 2, 28, 10));
    // Next step goes back to the 31st where the month has one.
    expect(nextOccurrence(feb, Repeat.monthly, feb), DateTime(2026, 3, 28, 10));
  });

  test('finished late: skips the days already past', () {
    // Daily task from Monday, finished on Thursday -> next is Thursday.
    final thu = DateTime(2026, 4, 16, 18);
    expect(nextOccurrence(mon, Repeat.daily, thu), DateTime(2026, 4, 16, 9, 30));
    // Weekly task finished 2 weeks late -> the coming Monday.
    expect(nextOccurrence(mon, Repeat.weekly, DateTime(2026, 4, 29)), DateTime(2026, 5, 4, 9, 30));
  });

  test('nextRepeat copies details, resets status and checklist', () {
    final t = TaskItem(
      id: 'a',
      title: 'Weekly report',
      description: 'Send to CEO',
      assigneeId: 'adl',
      createdBy: 'own',
      priority: Priority.high,
      status: TaskStatus.completed,
      stage: TaskStage.review,
      startAt: mon,
      endAt: mon.add(const Duration(hours: 1)),
      completedAt: mon,
      createdAt: mon,
      updatedAt: mon,
      repeat: Repeat.weekly,
      checklist: [
        ChecklistItem(
          id: 'c1',
          taskId: 'a',
          title: 'Numbers',
          isDone: true,
          sortOrder: 0,
          createdAt: mon,
          updatedAt: mon,
        ),
      ],
    );
    final n = t.nextRepeat('b', mon);
    expect(n.id, 'b');
    expect(n.repeatFrom, 'a');
    expect(n.title, 'Weekly report');
    expect(n.assigneeId, 'adl');
    expect(n.createdBy, 'own');
    expect(n.priority, Priority.high);
    expect(n.repeat, Repeat.weekly);
    expect(n.status, TaskStatus.pending);
    expect(n.stage, TaskStage.todo);
    expect(n.completedAt, isNull);
    expect(n.startAt, DateTime(2026, 4, 20, 9, 30));
    expect(n.endAt, DateTime(2026, 4, 20, 10, 30));
    expect(n.checklist.single.isDone, isFalse);
    expect(n.checklist.single.taskId, 'b');
  });

  test('stage and repeat survive toMap / fromMap; bad values fall back', () {
    final t = TaskItem(
      id: 'x',
      title: 'x',
      startAt: mon,
      createdAt: mon,
      updatedAt: mon,
      stage: TaskStage.doing,
      repeat: Repeat.daily,
      repeatFrom: 'w',
    );
    final back = TaskItem.fromMap(t.toMap());
    expect(back.stage, TaskStage.doing);
    expect(back.repeat, Repeat.daily);
    expect(back.repeatFrom, 'w');
    expect(back.displayStatus, DisplayStatus.inProgress);

    final old = TaskItem.fromMap({...t.toMap(), 'stage': 'weird', 'repeat': null});
    expect(old.stage, TaskStage.todo);
    expect(old.repeat, Repeat.none);
  });

  test('templates survive toMap / fromMap', () {
    final tp = TaskTemplate(
      id: 't',
      name: 'SEO audit',
      title: 'SEO audit for client',
      priority: Priority.high,
      checklist: ['Keywords', 'Meta tags'],
      createdAt: mon,
    );
    final back = TaskTemplate.fromMap(tp.toMap());
    expect(back.name, 'SEO audit');
    expect(back.priority, Priority.high);
    expect(back.checklist, ['Keywords', 'Meta tags']);
  });
}
