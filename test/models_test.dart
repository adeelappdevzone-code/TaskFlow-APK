import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/models.dart';

void main() {
  final created = DateTime(2026, 1, 2, 9, 30);
  final updated = DateTime(2026, 1, 3, 10, 0);

  test('TaskItem survives toMap / fromMap', () {
    final t = TaskItem(
      id: 't1',
      title: 'Design app UI',
      description: 'Screens',
      categoryId: 'c1',
      projectId: 'p1',
      assigneeId: 'm1',
      priority: Priority.high,
      status: TaskStatus.completed,
      startAt: DateTime(2026, 1, 5, 13),
      endAt: DateTime(2026, 1, 5, 15),
      completedAt: DateTime(2026, 1, 5, 14),
      createdAt: created,
      updatedAt: updated,
    );
    final back = TaskItem.fromMap(t.toMap());
    expect(back.id, 't1');
    expect(back.title, 'Design app UI');
    expect(back.description, 'Screens');
    expect(back.categoryId, 'c1');
    expect(back.projectId, 'p1');
    expect(back.assigneeId, 'm1');
    expect(back.priority, Priority.high);
    expect(back.status, TaskStatus.completed);
    expect(back.startAt, t.startAt);
    expect(back.endAt, t.endAt);
    expect(back.completedAt, t.completedAt);
    expect(back.createdAt, created);
    expect(back.updatedAt, updated);
  });

  test('TaskItem.fromMap handles missing optional fields', () {
    final t = TaskItem.fromMap({
      'id': 't2',
      'title': 'Old task',
      'priority': 7, // out of range -> high
      'status': TaskStatus.pending,
      'start_at': created.millisecondsSinceEpoch,
      'created_at': created.millisecondsSinceEpoch,
      'updated_at': created.millisecondsSinceEpoch,
    });
    expect(t.description, '');
    expect(t.endAt, isNull);
    expect(t.priority, Priority.high);
    expect(t.checklist, isEmpty);
  });

  test('TaskItem status helpers', () {
    TaskItem make(String status, {DateTime? end}) => TaskItem(
          id: 'x',
          title: 'x',
          status: status,
          startAt: DateTime(2000),
          endAt: end,
          createdAt: created,
          updatedAt: created,
        );

    expect(make(TaskStatus.pending).isOverdue, isTrue);
    expect(make(TaskStatus.completed).isOverdue, isFalse);
    expect(make(TaskStatus.pending, end: DateTime(2999)).isOverdue, isFalse);
    expect(make(TaskStatus.cancelled).displayStatus, DisplayStatus.cancelled);

    final t = make(TaskStatus.pending);
    expect(t.displayStatus, DisplayStatus.pending);
    t.checklist.add(ChecklistItem(
      id: 'c',
      taskId: 'x',
      title: 'step',
      isDone: true,
      sortOrder: 0,
      createdAt: created,
      updatedAt: created,
    ));
    expect(t.checklistDone, 1);
    expect(t.displayStatus, DisplayStatus.inProgress);
  });

  test('ChecklistItem survives toMap / fromMap', () {
    final c = ChecklistItem(
      id: 'c1',
      taskId: 't1',
      title: 'Wireframe',
      isDone: true,
      sortOrder: 2,
      createdAt: created,
      updatedAt: updated,
    );
    final back = ChecklistItem.fromMap(c.toMap());
    expect(back.title, 'Wireframe');
    expect(back.isDone, isTrue);
    expect(back.sortOrder, 2);
    expect(back.taskId, 't1');
  });

  test('Category, Project, Member survive toMap / fromMap', () {
    final cat = Category.fromMap(Category(
            id: 'c', name: 'Work', color: 0xFF1F6FEB, createdAt: created, updatedAt: updated)
        .toMap());
    expect(cat.name, 'Work');
    expect(cat.color, 0xFF1F6FEB);

    final p = Project.fromMap(Project(
            id: 'p', name: 'App', color: 0xFF16A34A, createdAt: created, updatedAt: updated)
        .toMap());
    expect(p.name, 'App');
    expect(p.color, 0xFF16A34A);

    final m = Member.fromMap(
        Member(id: 'm', name: 'Ali Raza', createdAt: created, updatedAt: updated).toMap());
    expect(m.name, 'Ali Raza');
  });

  test('AppNotification read state survives toMap / fromMap', () {
    final n = AppNotification(
      id: 'n',
      type: 'task',
      kind: 'reminder',
      title: 'Reminder',
      body: 'Soon',
      taskId: 't1',
      createdAt: created,
    );
    expect(AppNotification.fromMap(n.toMap()).isRead, isFalse);
    n.readAt = updated;
    final back = AppNotification.fromMap(n.toMap());
    expect(back.isRead, isTrue);
    expect(back.taskId, 't1');
  });
}
