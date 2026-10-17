// Data models.
//
// Every syncable table carries the same "sync-ready" columns so a cloud
// backend can be added later without changing the schema:
//   id          UUID string (never auto-increment, so two phones never clash)
//   created_at  / updated_at   epoch milliseconds
//   deleted_at  soft delete (null = alive)
//   is_synced   0 = changed locally and not yet pushed to the server

int nowMs() => DateTime.now().millisecondsSinceEpoch;

DateTime? _dt(dynamic v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);

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
/// How a task repeats. Simple ones are fixed words; on chosen weekdays it is
/// "days:1,4" (1 = Monday ... 7 = Sunday).
class Repeat {
  static const none = 'none';
  static const daily = 'daily';
  static const weekdays = 'weekdays'; // Monday to Friday
  static const weekly = 'weekly';
  static const biweekly = 'biweekly';
  static const monthly = 'monthly';
  static const monthEnd = 'month_end'; // last day of every month
  static const yearly = 'yearly';

  /// The fixed choices, in menu order.
  static const all = [none, daily, weekdays, weekly, biweekly, monthly, monthEnd, yearly];

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// "days:1,4" for [days] (1 = Monday), or [none] when empty.
  static String onDays(Iterable<int> days) {
    final list = days.where((d) => d >= 1 && d <= 7).toSet().toList()..sort();
    return list.isEmpty ? none : 'days:${list.join(',')}';
  }

  /// The weekdays of a "days:" repeat (empty for the others).
  static List<int> daysOf(String? repeat) {
    if (repeat == null || !repeat.startsWith('days:')) return const [];
    return [
      for (final p in repeat.substring(5).split(','))
        if (int.tryParse(p) case final d? when d >= 1 && d <= 7) d
    ];
  }

  static bool isValid(String? r) => r != null && (all.contains(r) || daysOf(r).isNotEmpty);

  static String label(String repeat) {
    final days = daysOf(repeat);
    if (days.isNotEmpty) return 'Every ${days.map((d) => _dayNames[d - 1]).join(', ')}';
    return switch (repeat) {
      daily => 'Every day',
      weekdays => 'Every weekday (Mon–Fri)',
      weekly => 'Every week',
      biweekly => 'Every 2 weeks',
      monthly => 'Every month',
      monthEnd => 'Last day of every month',
      yearly => 'Every year',
      _ => 'Never',
    };
  }

  static bool isOn(String? repeat) => repeat != null && repeat != none && isValid(repeat);
}

/// Start of the next copy of a repeating task: one step after [start], and
/// later steps if that day is already past (a task finished late does not
/// create copies for the days that were missed).
DateTime nextOccurrence(DateTime start, String repeat, DateTime now) {
  final days = Repeat.daysOf(repeat);
  DateTime plusDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n, d.hour, d.minute);
  DateTime nextOn(DateTime d, bool Function(int weekday) ok) {
    var n = plusDays(d, 1);
    while (!ok(n.weekday)) {
      n = plusDays(n, 1);
    }
    return n;
  }

  DateTime step(DateTime d) {
    if (days.isNotEmpty) return nextOn(d, days.contains);
    return switch (repeat) {
      Repeat.daily => plusDays(d, 1),
      Repeat.weekdays => nextOn(d, (w) => w <= 5),
      Repeat.weekly => plusDays(d, 7),
      Repeat.biweekly => plusDays(d, 14),
      Repeat.monthEnd => DateTime(d.year, d.month + 2, 0, d.hour, d.minute),
      Repeat.yearly => _addYear(d, start),
      _ => _addMonth(d, start.day),
    };
  }

  final today = DateTime(now.year, now.month, now.day);
  var next = step(start);
  while (next.isBefore(today)) {
    next = step(next);
  }
  return next;
}

/// Same date next year (29 Feb -> 28 Feb).
DateTime _addYear(DateTime d, DateTime start) {
  final y = d.year + 1;
  final last = DateTime(y, start.month + 1, 0).day;
  return DateTime(y, start.month, start.day > last ? last : start.day, d.hour, d.minute);
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

/// A web link on a task (Google Drive/Docs, a website...). Used instead of
/// file attachments, which would need a paid storage plan.
class TaskLink {
  final String title;
  final String url;
  const TaskLink({this.title = '', required this.url});

  /// The title, or the address without "https://" when there is no title.
  String get label {
    if (title.trim().isNotEmpty) return title.trim();
    return url.replaceFirst(RegExp(r'^https?://(www\.)?'), '');
  }

  Map<String, dynamic> toMap() => {'title': title, 'url': url};

  static TaskLink? tryFrom(dynamic m) {
    if (m is! Map || m['url'] is! String) return null;
    return TaskLink(title: (m['title'] as String?) ?? '', url: m['url'] as String);
  }

  /// Adds "https://" when the address has no scheme ("drive.google.com/..."),
  /// or returns null when it does not look like a web address.
  static String? normalizeUrl(String input) {
    var u = input.trim();
    if (u.isEmpty || u.contains(' ')) return null;
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(u)) u = 'https://$u';
    final uri = Uri.tryParse(u);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return null;
    if (!uri.host.contains('.')) return null;
    return u;
  }
}

/// What happened to a task (stored as `history`).
class HistoryKind {
  static const created = 'created';
  static const edited = 'edited';
  static const assigned = 'assigned';
  static const unassigned = 'unassigned';
  static const stage = 'stage';
  static const done = 'done';
  static const reopened = 'reopened';
  static const cancelled = 'cancelled';
  static const restored = 'restored';
  static const approved = 'approved';
  static const changes = 'changes';

  /// Sent for approval (moved to Review & Feedback, maybe with a note).
  static const submitted = 'submitted';

  /// The assignee asked to move the date ([TaskEvent.to] = new day in ms,
  /// note = why); the owner/manager agreed or said no.
  static const moveAsked = 'move_asked';
  static const moveOk = 'move_ok';
  static const moveNo = 'move_no';
}

/// One line in a task's history: who did what and when. [to] is the new
/// assignee (assigned) or the new board column (stage).
class TaskEvent {
  final String kind;
  final String? by;
  final DateTime at;
  final String? to;

  /// Approvals: the cover message or the feedback.
  final String? note;

  const TaskEvent({required this.kind, required this.by, required this.at, this.to, this.note});

  Map<String, dynamic> toMap() => {
        'kind': kind,
        'by': by,
        'at': at.millisecondsSinceEpoch,
        if (to != null) 'to': to,
        if (note != null && note!.isNotEmpty) 'note': note,
      };

  static TaskEvent? tryFrom(dynamic m) {
    if (m is! Map || m['kind'] is! String || m['at'] is! int) return null;
    return TaskEvent(
      kind: m['kind'] as String,
      by: m['by'] as String?,
      at: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
      to: m['to'] as String?,
      note: m['note'] is String ? m['note'] as String : null,
    );
  }
}

/// Time someone worked on a task (Start ... Stop), stored in `time_log`.
class TimeEntry {
  final String by;
  final DateTime start;
  final DateTime end;

  /// Can be charged to a client (default yes).
  final bool billable;
  final String note;

  const TimeEntry(
      {required this.by,
      required this.start,
      required this.end,
      this.billable = true,
      this.note = ''});

  Duration get duration => end.difference(start);

  TimeEntry copyWith({DateTime? start, DateTime? end, bool? billable, String? note}) => TimeEntry(
        by: by,
        start: start ?? this.start,
        end: end ?? this.end,
        billable: billable ?? this.billable,
        note: note ?? this.note,
      );

  Map<String, dynamic> toMap() => {
        'by': by,
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        if (!billable) 'billable': false,
        if (note.isNotEmpty) 'note': note,
      };

  static TimeEntry? tryFrom(dynamic m) {
    if (m is! Map || m['by'] is! String || m['start'] is! int || m['end'] is! int) return null;
    return TimeEntry(
      by: m['by'] as String,
      start: DateTime.fromMillisecondsSinceEpoch(m['start'] as int),
      end: DateTime.fromMillisecondsSinceEpoch(m['end'] as int),
      billable: m['billable'] != false,
      note: m['note'] is String ? m['note'] as String : '',
    );
  }
}

/// At most this many history lines are kept per task (the oldest after
/// "created" are dropped).
const kMaxHistory = 100;

List<T> _listOf<T>(dynamic raw, T? Function(dynamic) parse) => [
      if (raw is List)
        for (final x in raw)
          if (parse(x) case final T v) v,
    ];

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

  /// Web links (Drive, Docs, websites).
  List<TaskLink> links;

  /// Who did what, oldest first.
  List<TaskEvent> history;

  /// Finished work sessions.
  List<TimeEntry> timeLog;

  /// Running timer: who started it and when (null when stopped).
  String? timerBy;
  DateTime? timerAt;

  /// How long the work should take, in minutes (null: not estimated).
  int? estimateMinutes;

  /// Team task: the assignee asked to move it to this day (waiting for the
  /// owner/manager).
  DateTime? moveAskedTo;

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
    List<TaskLink>? links,
    List<TaskEvent>? history,
    List<TimeEntry>? timeLog,
    this.timerBy,
    this.timerAt,
    this.estimateMinutes,
    this.moveAskedTo,
  })  : checklist = checklist ?? [],
        links = links ?? [],
        history = history ?? [],
        timeLog = timeLog ?? [];

  bool get isCompleted => status == TaskStatus.completed;
  bool get isCancelled => status == TaskStatus.cancelled;

  int get checklistDone => checklist.where((c) => c.isDone).length;

  bool get timerRunning => timerAt != null;

  /// A task without a time runs the whole day (00:00 – 23:59).
  bool get isAllDay {
    final e = endAt;
    return startAt.hour == 0 &&
        startAt.minute == 0 &&
        e != null &&
        e.year == startAt.year &&
        e.month == startAt.month &&
        e.day == startAt.day &&
        e.hour == 23 &&
        e.minute == 59;
  }

  /// Total tracked time (finished sessions, plus the running one when
  /// [now] is given), optionally only for one person.
  Duration timeSpent({String? by, DateTime? now}) {
    var total = Duration.zero;
    for (final e in timeLog) {
      if (by == null || e.by == by) total += e.duration;
    }
    final at = timerAt;
    if (now != null && at != null && (by == null || timerBy == by) && now.isAfter(at)) {
      total += now.difference(at);
    }
    return total;
  }

  /// Tracked time per person (finished sessions only), most first.
  List<MapEntry<String, Duration>> get timeByPerson {
    final m = <String, Duration>{};
    for (final e in timeLog) {
      m[e.by] = (m[e.by] ?? Duration.zero) + e.duration;
    }
    return m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Adds a history line. Several edits by the same person within 30 minutes
  /// count as one; the list is kept to [kMaxHistory] lines.
  TaskEvent addHistory(String kind, String? by, {String? to, DateTime? at, String? note}) {
    final clean = note?.trim();
    final e = TaskEvent(
        kind: kind,
        by: by,
        at: at ?? DateTime.now(),
        to: to,
        note: clean == null || clean.isEmpty
            ? null
            : (clean.length > 1500 ? clean.substring(0, 1500) : clean));
    final last = history.isEmpty ? null : history.last;
    if (kind == HistoryKind.edited &&
        last != null &&
        last.kind == HistoryKind.edited &&
        last.by == by &&
        e.at.difference(last.at) < const Duration(minutes: 30)) {
      history[history.length - 1] = e;
    } else {
      history.add(e);
    }
    while (history.length > kMaxHistory) {
      history.removeAt(1);
    }
    return e;
  }

  /// History to show: the stored lines, or for tasks made before history
  /// existed, what can be read from the task itself.
  List<TaskEvent> get historyOrDerived {
    if (history.any((e) => e.kind == HistoryKind.created)) return history;
    final derived = <TaskEvent>[
      TaskEvent(kind: HistoryKind.created, by: createdBy, at: createdAt),
      if (assigneeId != null && assignedAt != null && !assignedAt!.isBefore(createdAt))
        TaskEvent(kind: HistoryKind.assigned, by: assignedBy, at: assignedAt!, to: assigneeId),
    ];
    if (history.isEmpty && isCompleted && completedAt != null) {
      derived.add(TaskEvent(kind: HistoryKind.done, by: completedBy, at: completedAt!));
    }
    return [...derived, ...history]..sort((a, b) => a.at.compareTo(b.at));
  }

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
        'links': links.map((l) => l.toMap()).toList(),
        'history': history.map((e) => e.toMap()).toList(),
        'time_log': timeLog.map((e) => e.toMap()).toList(),
        'timer_by': timerBy,
        'timer_at': _ms(timerAt),
        'estimate_min': estimateMinutes,
        'move_to': _ms(moveAskedTo),
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
        repeat: Repeat.isValid(m['repeat'] as String?) ? m['repeat'] as String : Repeat.none,
        repeatFrom: m['repeat_from'] as String?,
        links: _listOf(m['links'], TaskLink.tryFrom),
        history: _listOf(m['history'], TaskEvent.tryFrom),
        timeLog: _listOf(m['time_log'], TimeEntry.tryFrom),
        timerBy: m['timer_by'] as String?,
        timerAt: _dt(m['timer_at']),
        estimateMinutes: m['estimate_min'] is int && (m['estimate_min'] as int) > 0
            ? m['estimate_min'] as int
            : null,
        moveAskedTo: _dt(m['move_to']),
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
      links: [...links],
      estimateMinutes: estimateMinutes,
      history: [TaskEvent(kind: HistoryKind.created, by: createdBy, at: now)],
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

/// Notification kinds and the Notification Center tab each belongs to.
class NotifKind {
  static const mention = 'mention';
  static const comment = 'comment';
  static const assigned = 'assigned';
  static const reminder = 'reminder';
  static const approval = 'approval'; // waiting for my approval
  static const approved = 'approved';
  static const changes = 'changes'; // changes requested on my task
  static const invite = 'invite';
  static const report = 'report';
  static const moveAsked = 'move_asked'; // asked me to move a task's date
  static const moveAnswer = 'move_answer'; // my date change request answered

  /// Tabs: mentions | assignments | reminders | approvals.
  static String? tabOf(String kind) => switch (kind) {
        mention || comment => 'mentions',
        assigned => 'assignments',
        reminder => 'reminders',
        approval || approved || changes || moveAsked || moveAnswer => 'approvals',
        _ => null,
      };
}

class AppNotification {
  final String id;

  /// 'task' or 'system'.
  final String type;

  /// [NotifKind], or older ones: completed | cancelled | project | team | info
  final String kind;
  final String title;
  final String body;
  final String? taskId;

  /// Team tasks: the task's team. Shown as "task • team".
  final String? teamId;

  /// Who did it (for the picture), e.g. the commenter.
  final String? actorName;
  final DateTime createdAt;
  DateTime? readAt;

  /// Reminders: hidden until then, then shown again as unread.
  DateTime? snoozeUntil;

  AppNotification({
    required this.id,
    required this.type,
    required this.kind,
    required this.title,
    required this.body,
    this.taskId,
    this.teamId,
    this.actorName,
    required this.createdAt,
    this.readAt,
    this.snoozeUntil,
  });

  bool get isRead => readAt != null;

  bool snoozedAt(DateTime now) => snoozeUntil != null && snoozeUntil!.isAfter(now);

  /// When it shows in the list (a snoozed reminder comes back at the top).
  DateTime get shownAt => snoozeUntil ?? createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'kind': kind,
        'title': title,
        'body': body,
        'task_id': taskId,
        if (teamId != null) 'team_id': teamId,
        if (actorName != null) 'actor_name': actorName,
        'created_at': _ms(createdAt),
        'read_at': _ms(readAt),
        if (snoozeUntil != null) 'snooze_until': _ms(snoozeUntil),
      };

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        type: m['type'] as String,
        kind: m['kind'] as String,
        title: m['title'] as String,
        body: m['body'] as String,
        taskId: m['task_id'] as String?,
        teamId: m['team_id'] as String?,
        actorName: m['actor_name'] as String?,
        createdAt: _dt(m['created_at'])!,
        readAt: _dt(m['read_at']),
        snoozeUntil: _dt(m['snooze_until']),
      );
}

/// A saved task "recipe" (title, description, priority, checklist) to create
/// similar tasks quickly. Stored in users/{uid}/templates.
/// One task inside a workflow template: due [offsetDays] after the start.
class TemplateTask {
  String title;
  int offsetDays;
  Priority priority;
  int? estimateMinutes;
  List<String> checklist;

  TemplateTask({
    required this.title,
    this.offsetDays = 0,
    this.priority = Priority.medium,
    this.estimateMinutes,
    List<String>? checklist,
  }) : checklist = checklist ?? [];

  Map<String, dynamic> toMap() => {
        'title': title,
        'offset': offsetDays,
        'priority': priority.index,
        if (estimateMinutes != null) 'estimate': estimateMinutes,
        if (checklist.isNotEmpty) 'checklist': checklist,
      };

  static TemplateTask? tryFrom(dynamic m) {
    if (m is! Map || m['title'] is! String) return null;
    return TemplateTask(
      title: m['title'] as String,
      offsetDays: m['offset'] is int ? m['offset'] as int : 0,
      priority: _priorityFrom(m['priority'] is int ? m['priority'] as int : 1),
      estimateMinutes: m['estimate'] is int ? m['estimate'] as int : null,
      checklist: [
        for (final c in (m['checklist'] as List?) ?? const [])
          if (c is String) c,
      ],
    );
  }
}

/// A saved My Tasks filter: tab, where from, priority, sort, list / board.
class SavedView {
  final String id;
  final String name;
  final String tab;
  final String? source;
  final int? priority;
  final bool byMe;
  final String sort;
  final bool board;

  const SavedView({
    required this.id,
    required this.name,
    this.tab = 'all',
    this.source,
    this.priority,
    this.byMe = false,
    this.sort = 'Due date',
    this.board = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'tab': tab,
        if (source != null) 'source': source,
        if (priority != null) 'priority': priority,
        if (byMe) 'by_me': true,
        'sort': sort,
        if (board) 'board': true,
      };

  static SavedView? tryFrom(dynamic m) {
    if (m is! Map || m['id'] is! String || m['name'] is! String) return null;
    return SavedView(
      id: m['id'] as String,
      name: m['name'] as String,
      tab: m['tab'] is String ? m['tab'] as String : 'all',
      source: m['source'] as String?,
      priority: m['priority'] is int ? m['priority'] as int : null,
      byMe: m['by_me'] == true,
      sort: m['sort'] is String ? m['sort'] as String : 'Due date',
      board: m['board'] == true,
    );
  }
}

/// Template categories (tabs in the Templates Library).
const kTemplateCategories = ['Agency', 'Marketing', 'Development', 'Operations', 'Personal'];

/// A saved task "recipe": one task (title, description, priority, checklist)
/// or a whole workflow of [tasks]. Personal ones are stored in
/// users/{uid}/templates, team ones in teams/{teamId}/templates.
class TaskTemplate {
  final String id;
  String name;
  String title;
  String description;
  Priority priority;
  List<String> checklist;
  final DateTime createdAt;

  String category;
  int color;

  /// Icon key ([templateIcons] in the library screen).
  String icon;
  List<TemplateTask> tasks;
  String? createdBy;

  /// Set for team templates (not stored: it is the collection's team).
  String? teamId;

  /// Ready-made template that ships with the app.
  bool builtIn;

  TaskTemplate({
    required this.id,
    required this.name,
    required this.title,
    this.description = '',
    this.priority = Priority.medium,
    List<String>? checklist,
    required this.createdAt,
    this.category = 'Personal',
    this.color = 0xFF1F6FEB,
    this.icon = 'task',
    List<TemplateTask>? tasks,
    this.createdBy,
    this.teamId,
    this.builtIn = false,
  })  : checklist = checklist ?? [],
        tasks = tasks ?? [];

  /// The tasks it creates (a one-task template is its own single task).
  List<TemplateTask> get workflow => tasks.isNotEmpty
      ? tasks
      : [TemplateTask(title: title, priority: priority, checklist: checklist)];

  /// Days from the first to the last task.
  int get spanDays {
    final w = workflow;
    final offs = w.map((t) => t.offsetDays);
    return offs.reduce((a, b) => a > b ? a : b) - offs.reduce((a, b) => a < b ? a : b) + 1;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'title': title,
        'description': description,
        'priority': priority.index,
        'checklist': checklist,
        'created_at': _ms(createdAt),
        'category': category,
        'color': color,
        'icon': icon,
        'tasks': tasks.map((t) => t.toMap()).toList(),
        if (createdBy != null) 'created_by': createdBy,
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
        category:
            kTemplateCategories.contains(m['category']) ? m['category'] as String : 'Personal',
        color: m['color'] is int ? m['color'] as int : 0xFF1F6FEB,
        icon: m['icon'] is String ? m['icon'] as String : 'task',
        tasks: _listOf(m['tasks'], TemplateTask.tryFrom),
        createdBy: m['created_by'] as String?,
      );
}
