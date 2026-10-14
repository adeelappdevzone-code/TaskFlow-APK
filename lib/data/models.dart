// Data models.
//
// Every syncable table carries the same "sync-ready" columns so a cloud
// backend can be added later without changing the schema:
//   id          UUID string (never auto-increment, so two phones never clash)
//   created_at  / updated_at   epoch milliseconds
//   deleted_at  soft delete (null = alive)
//   is_synced   0 = changed locally and not yet pushed to the server

int nowMs() => DateTime.now().millisecondsSinceEpoch;

DateTime? _dt(dynamic v) =>
    v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);

int? _ms(DateTime? d) => d?.millisecondsSinceEpoch;

enum Priority { low, medium, high }

Priority _priorityFrom(int i) {
  if (i <= 0) return Priority.low;
  if (i >= 2) return Priority.high;
  return Priority.medium;
}

extension PriorityX on Priority {
  String get label => switch (this) {
        Priority.low => 'Low',
        Priority.medium => 'Medium',
        Priority.high => 'High',
      };
}

/// Stored status. "In progress" is derived (see [TaskItem.displayStatus]).
class TaskStatus {
  static const pending = 'pending';
  static const completed = 'completed';
  static const cancelled = 'cancelled';
}

enum DisplayStatus { pending, inProgress, completed, cancelled }

class AppUser {
  final String id;
  String name;
  String email;
  String passwordHash;
  final DateTime createdAt;
  DateTime updatedAt;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.passwordHash,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'email': email,
        'password_hash': passwordHash,
        'created_at': _ms(createdAt),
        'updated_at': _ms(updatedAt),
        'is_synced': 0,
      };

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        id: m['id'] as String,
        name: m['name'] as String,
        email: m['email'] as String,
        passwordHash: m['password_hash'] as String,
        createdAt: _dt(m['created_at'])!,
        updatedAt: _dt(m['updated_at'])!,
      );
}

class Category {
  final String id;
  String name;
  int color;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? deletedAt;

  Category({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'color': color,
        'created_at': _ms(createdAt),
        'updated_at': _ms(updatedAt),
        'deleted_at': _ms(deletedAt),
        'is_synced': 0,
      };

  factory Category.fromMap(Map<String, dynamic> m) => Category(
        id: m['id'] as String,
        name: m['name'] as String,
        color: m['color'] as int,
        createdAt: _dt(m['created_at'])!,
        updatedAt: _dt(m['updated_at'])!,
        deletedAt: _dt(m['deleted_at']),
      );
}

class Project {
  final String id;
  String name;
  int color;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? deletedAt;

  Project({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'color': color,
        'created_at': _ms(createdAt),
        'updated_at': _ms(updatedAt),
        'deleted_at': _ms(deletedAt),
        'is_synced': 0,
      };

  factory Project.fromMap(Map<String, dynamic> m) => Project(
        id: m['id'] as String,
        name: m['name'] as String,
        color: m['color'] as int,
        createdAt: _dt(m['created_at'])!,
        updatedAt: _dt(m['updated_at'])!,
        deletedAt: _dt(m['deleted_at']),
      );
}

/// Team member a task can be assigned to. Local-only for now; in the cloud
/// version this becomes a real user account.
class Member {
  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? deletedAt;

  Member({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'created_at': _ms(createdAt),
        'updated_at': _ms(updatedAt),
        'deleted_at': _ms(deletedAt),
        'is_synced': 0,
      };

  factory Member.fromMap(Map<String, dynamic> m) => Member(
        id: m['id'] as String,
        name: m['name'] as String,
        createdAt: _dt(m['created_at'])!,
        updatedAt: _dt(m['updated_at'])!,
        deletedAt: _dt(m['deleted_at']),
      );
}

class ChecklistItem {
  final String id;
  final String taskId;
  String title;
  bool isDone;
  int sortOrder;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? deletedAt;

  ChecklistItem({
    required this.id,
    required this.taskId,
    required this.title,
    required this.isDone,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'task_id': taskId,
        'title': title,
        'is_done': isDone ? 1 : 0,
        'sort_order': sortOrder,
        'created_at': _ms(createdAt),
        'updated_at': _ms(updatedAt),
        'deleted_at': _ms(deletedAt),
        'is_synced': 0,
      };

  factory ChecklistItem.fromMap(Map<String, dynamic> m) => ChecklistItem(
        id: m['id'] as String,
        taskId: m['task_id'] as String,
        title: m['title'] as String,
        isDone: (m['is_done'] as int) == 1,
        sortOrder: m['sort_order'] as int,
        createdAt: _dt(m['created_at'])!,
        updatedAt: _dt(m['updated_at'])!,
        deletedAt: _dt(m['deleted_at']),
      );
}

class TaskItem {
  final String id;
  String title;
  String description;
  String? categoryId;
  String? projectId;
  String? assigneeId;
  Priority priority;
  String status;
  DateTime startAt;
  DateTime? endAt;
  DateTime? completedAt;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? deletedAt;

  /// Loaded separately from the checklist_items table.
  List<ChecklistItem> checklist;

  TaskItem({
    required this.id,
    required this.title,
    this.description = '',
    this.categoryId,
    this.projectId,
    this.assigneeId,
    this.priority = Priority.medium,
    this.status = TaskStatus.pending,
    required this.startAt,
    this.endAt,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    List<ChecklistItem>? checklist,
  }) : checklist = checklist ?? [];

  bool get isCompleted => status == TaskStatus.completed;
  bool get isCancelled => status == TaskStatus.cancelled;

  int get checklistDone => checklist.where((c) => c.isDone).length;

  DisplayStatus get displayStatus {
    if (status == TaskStatus.completed) return DisplayStatus.completed;
    if (status == TaskStatus.cancelled) return DisplayStatus.cancelled;
    if (checklistDone > 0) return DisplayStatus.inProgress;
    return DisplayStatus.pending;
  }

  /// Overdue = not finished and its end (or start) time has passed.
  bool get isOverdue {
    if (status != TaskStatus.pending) return false;
    final due = endAt ?? startAt;
    return due.isBefore(DateTime.now());
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'category_id': categoryId,
        'project_id': projectId,
        'assignee_id': assigneeId,
        'priority': priority.index,
        'status': status,
        'start_at': _ms(startAt),
        'end_at': _ms(endAt),
        'completed_at': _ms(completedAt),
        'created_at': _ms(createdAt),
        'updated_at': _ms(updatedAt),
        'deleted_at': _ms(deletedAt),
        'is_synced': 0,
      };

  factory TaskItem.fromMap(Map<String, dynamic> m) => TaskItem(
        id: m['id'] as String,
        title: m['title'] as String,
        description: (m['description'] as String?) ?? '',
        categoryId: m['category_id'] as String?,
        projectId: m['project_id'] as String?,
        assigneeId: m['assignee_id'] as String?,
        priority: _priorityFrom(m['priority'] as int),
        status: m['status'] as String,
        startAt: _dt(m['start_at'])!,
        endAt: _dt(m['end_at']),
        completedAt: _dt(m['completed_at']),
        createdAt: _dt(m['created_at'])!,
        updatedAt: _dt(m['updated_at'])!,
        deletedAt: _dt(m['deleted_at']),
      );
}

class AppNotification {
  final String id;

  /// 'task' or 'system' (matches the tabs on the Notifications screen).
  final String type;

  /// completed | assigned | reminder | cancelled | project | info
  final String kind;
  final String title;
  final String body;
  final String? taskId;
  final DateTime createdAt;
  DateTime? readAt;

  AppNotification({
    required this.id,
    required this.type,
    required this.kind,
    required this.title,
    required this.body,
    this.taskId,
    required this.createdAt,
    this.readAt,
  });

  bool get isRead => readAt != null;

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'kind': kind,
        'title': title,
        'body': body,
        'task_id': taskId,
        'created_at': _ms(createdAt),
        'read_at': _ms(readAt),
      };

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        type: m['type'] as String,
        kind: m['kind'] as String,
        title: m['title'] as String,
        body: m['body'] as String,
        taskId: m['task_id'] as String?,
        createdAt: _dt(m['created_at'])!,
        readAt: _dt(m['read_at']),
      );
}
