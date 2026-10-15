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

/// Where an unfinished task is on the board (stored as `stage`; finished
/// tasks use [TaskStatus.completed] instead).
class TaskStage {
  static const todo = 'todo';
  static const doing = 'doing';
  static const review = 'review';
  static const all = [todo, doing, review];

  /// Board column for finished tasks (not a stored stage).
  static const boardDone = 'done';

  static String label(String stage) => switch (stage) {
        doing => 'In progress',
        review => 'Review',
        _ => 'To do',
      };
}

/// How often a task comes back after it is done (stored as `repeat`).
class Repeat {
  static const none = 'none';
  static const daily = 'daily';
  static const weekly = 'weekly';
  static const monthly = 'monthly';
  static const all = [none, daily, weekly, monthly];

  static String label(String repeat) => switch (repeat) {
        daily => 'Every day',
        weekly => 'Every week',
        monthly => 'Every month',
        _ => 'Never',
      };

  static bool isOn(String? repeat) =>
      repeat == daily || repeat == weekly || repeat == monthly;
}

/// Start of the next copy of a repeating task: one step after [start], and
/// later steps if that day is already past (a task finished late does not
/// create copies for the days that were missed).
DateTime nextOccurrence(DateTime start, String repeat, DateTime now) {
  DateTime step(DateTime d) => switch (repeat) {
        Repeat.daily => DateTime(d.year, d.month, d.day + 1, d.hour, d.minute),
        Repeat.weekly => DateTime(d.year, d.month, d.day + 7, d.hour, d.minute),
        _ => _addMonth(d, start.day),
      };
  final today = DateTime(now.year, now.month, now.day);
  var next = step(start);
  while (next.isBefore(today)) {
    next = step(next);
  }
  return next;
}

/// Same day next month, or the month's last day (31 Jan -> 28/29 Feb -> 31 Mar).
DateTime _addMonth(DateTime d, int wantedDay) {
  final firstOfNext = DateTime(d.year, d.month + 1, 1);
  final lastDay = DateTime(firstOfNext.year, firstOfNext.month + 1, 0).day;
  final day = wantedDay > lastDay ? lastDay : wantedDay;
  return DateTime(firstOfNext.year, firstOfNext.month, day, d.hour, d.minute);
}

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

  /// Team tasks only: who created the task, who assigned it and when.
  String? createdBy;
  String? assignedBy;
  DateTime? assignedAt;

  /// Who marked it done (team tasks; null for older tasks).
  String? completedBy;

  /// Board column while not finished ([TaskStage]).
  String stage;

  /// [Repeat] setting, and for a repeated copy the id of the task it came from.
  String repeat;
  String? repeatFrom;

  /// Stored inside the task document.
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
    this.createdBy,
    this.assignedBy,
    this.assignedAt,
    this.completedBy,
    this.stage = TaskStage.todo,
    this.repeat = Repeat.none,
    this.repeatFrom,
    List<ChecklistItem>? checklist,
  }) : checklist = checklist ?? [];

  bool get isCompleted => status == TaskStatus.completed;
  bool get isCancelled => status == TaskStatus.cancelled;

  int get checklistDone => checklist.where((c) => c.isDone).length;

  DisplayStatus get displayStatus {
    if (status == TaskStatus.completed) return DisplayStatus.completed;
    if (status == TaskStatus.cancelled) return DisplayStatus.cancelled;
    if (stage != TaskStage.todo || checklistDone > 0) return DisplayStatus.inProgress;
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
        'created_by': createdBy,
        'assigned_by': assignedBy,
        'assigned_at': _ms(assignedAt),
        'completed_by': completedBy,
        'stage': stage,
        'repeat': repeat,
        'repeat_from': repeatFrom,
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
        createdBy: m['created_by'] as String?,
        assignedBy: m['assigned_by'] as String?,
        assignedAt: _dt(m['assigned_at']),
        completedBy: m['completed_by'] as String?,
        stage: TaskStage.all.contains(m['stage']) ? m['stage'] as String : TaskStage.todo,
        repeat: Repeat.all.contains(m['repeat']) ? m['repeat'] as String : Repeat.none,
        repeatFrom: m['repeat_from'] as String?,
      );

  /// The next copy of a repeating task: same details, new date, unchecked
  /// checklist, not done. [id] is given by the caller.
  TaskItem nextRepeat(String id, DateTime now) {
    final start = nextOccurrence(startAt, repeat, now);
    final shift = start.difference(startAt);
    return TaskItem(
      id: id,
      title: title,
      description: description,
      categoryId: categoryId,
      projectId: projectId,
      assigneeId: assigneeId,
      priority: priority,
      startAt: start,
      endAt: endAt?.add(shift),
      createdAt: now,
      updatedAt: now,
      createdBy: createdBy,
      assignedBy: assignedBy,
      assignedAt: assignedAt,
      repeat: repeat,
      repeatFrom: this.id,
      checklist: [
        for (final c in checklist)
          ChecklistItem(
            id: c.id,
            taskId: id,
            title: c.title,
            isDone: false,
            sortOrder: c.sortOrder,
            createdAt: now,
            updatedAt: now,
          ),
      ],
    );
  }
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

/// A saved task "recipe" (title, description, priority, checklist) to create
/// similar tasks quickly. Stored in users/{uid}/templates.
class TaskTemplate {
  final String id;
  String name;
  String title;
  String description;
  Priority priority;
  List<String> checklist;
  final DateTime createdAt;

  TaskTemplate({
    required this.id,
    required this.name,
    required this.title,
    this.description = '',
    this.priority = Priority.medium,
    List<String>? checklist,
    required this.createdAt,
  }) : checklist = checklist ?? [];

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'title': title,
        'description': description,
        'priority': priority.index,
        'checklist': checklist,
        'created_at': _ms(createdAt),
      };

  factory TaskTemplate.fromMap(Map<String, dynamic> m) => TaskTemplate(
        id: m['id'] as String,
        name: m['name'] as String,
        title: m['title'] as String,
        description: (m['description'] as String?) ?? '',
        priority: _priorityFrom((m['priority'] as int?) ?? 1),
        checklist: [
          for (final c in (m['checklist'] as List?) ?? const [])
            if (c is String) c,
        ],
        createdAt: _dt(m['created_at'])!,
      );
}
