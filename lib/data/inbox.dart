import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;

import '../core/utils.dart';
import 'app_store.dart';
import 'models.dart';
import 'team_models.dart';
import 'team_store.dart';

/// Where an inbox item came from.
class InboxSource {
  static const quick = 'quick';
  static const email = 'email';
  static const voice = 'voice';
  static const forwarded = 'forwarded';
  static const all = [quick, email, voice, forwarded];

  static String label(String s) => switch (s) {
        email => 'Email',
        voice => 'Voice',
        forwarded => 'Forwarded',
        _ => 'Quick add',
      };
}

/// Something captured quickly, to be organized later (date, priority, team,
/// person, label) and then moved to the task lists. Stored in
/// users/{uid}/inbox. Organized items stay a week for "Recently organized".
class InboxItem {
  final String id;
  String title;
  String notes;
  final String source;
  final DateTime createdAt;
  DateTime? dueAt;

  /// [dueAt] is a day without a time.
  bool allDay;
  Priority? priority;
  String? teamId;
  String? assigneeId;
  String? categoryId;
  List<TaskLink> links;

  /// Forwarded by a teammate.
  final String? fromId;
  final String? fromName;

  /// Set once moved to the task lists (or forwarded on).
  DateTime? organizedAt;
  String? organizedTo;
  String? taskId;
  String? taskTeamId;

  InboxItem({
    required this.id,
    required this.title,
    this.notes = '',
    this.source = InboxSource.quick,
    required this.createdAt,
    this.dueAt,
    this.allDay = false,
    this.priority,
    this.teamId,
    this.assigneeId,
    this.categoryId,
    List<TaskLink>? links,
    this.fromId,
    this.fromName,
    this.organizedAt,
    this.organizedTo,
    this.taskId,
    this.taskTeamId,
  }) : links = links ?? [];

  bool get isOrganized => organizedAt != null;

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'notes': notes,
        'source': source,
        'created_at': createdAt.millisecondsSinceEpoch,
        'due_at': dueAt?.millisecondsSinceEpoch,
        'all_day': allDay,
        'priority': priority?.index,
        'team_id': teamId,
        'assignee_id': assigneeId,
        'category_id': categoryId,
        'links': links.map((l) => l.toMap()).toList(),
        if (fromId != null) 'from_id': fromId,
        if (fromName != null) 'from_name': fromName,
        'organized_at': organizedAt?.millisecondsSinceEpoch,
        'organized_to': organizedTo,
        'task_id': taskId,
        'task_team': taskTeamId,
      };

  static DateTime? _dt(dynamic v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;

  factory InboxItem.fromMap(Map<String, dynamic> m) {
    final p = m['priority'];
    final src = m['source'];
    return InboxItem(
      id: m['id'] as String,
      title: (m['title'] as String?) ?? '',
      notes: (m['notes'] as String?) ?? '',
      source: InboxSource.all.contains(src) ? src as String : InboxSource.quick,
      createdAt: _dt(m['created_at']) ?? DateTime.now(),
      dueAt: _dt(m['due_at']),
      allDay: m['all_day'] == true,
      priority: p is int && p >= 0 && p < Priority.values.length ? Priority.values[p] : null,
      teamId: m['team_id'] as String?,
      assigneeId: m['assignee_id'] as String?,
      categoryId: m['category_id'] as String?,
      links:
          ((m['links'] as List?) ?? const []).map(TaskLink.tryFrom).whereType<TaskLink>().toList(),
      fromId: m['from_id'] as String?,
      fromName: m['from_name'] as String?,
      organizedAt: _dt(m['organized_at']),
      organizedTo: m['organized_to'] as String?,
      taskId: m['task_id'] as String?,
      taskTeamId: m['task_team'] as String?,
    );
  }
}

// ------------------------------------------------------------ quick capture

/// What [parseCapture] found in a typed line.
class CaptureResult {
  final String title;
  final DateTime? due;
  final bool allDay;
  final Priority? priority;

  /// "#word": a team or label name.
  final String? tag;

  const CaptureResult(
      {required this.title, this.due, this.allDay = false, this.priority, this.tag});
}

const _months = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec'
];
const _weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

/// Reads dates, times, priority and a tag out of a quick-capture line:
/// "Call Ali tomorrow 5pm !high #marketing" → title "Call Ali", tomorrow
/// 17:00, high, tag "marketing". Understands today / tonight / tomorrow /
/// weekday names / "next week" / "in 3 days" / "19 oct" / "oct 19", times
/// like 5pm, 5:30 pm, 14:00, and !high / !medium / !low.
CaptureResult parseCapture(String input, DateTime now) {
  var text = ' ${input.trim()} ';
  DateTime? day;
  int? hour;
  int? minute;
  Priority? priority;
  String? tag;
  var tonight = false;

  String cut(RegExp re, void Function(RegExpMatch m) use) {
    final m = re.firstMatch(text);
    if (m == null) return text;
    use(m);
    return text.replaceRange(m.start, m.end, ' ');
  }

  final today = dateOnly(now);
  text = cut(RegExp(r'\s!(high|urgent|h|medium|med|m|low|l)(?=\s)', caseSensitive: false), (m) {
    final p = m.group(1)!.toLowerCase();
    priority = p.startsWith('h') || p == 'urgent'
        ? Priority.high
        : (p.startsWith('m') ? Priority.medium : Priority.low);
  });
  text = cut(RegExp(r'\s#([\p{L}\p{N}_-]+)(?=\s)', unicode: true), (m) => tag = m.group(1));

  // Times first, so "5:30" is not read as a date.
  text = cut(RegExp(r'\s(?:at\s+)?(\d{1,2})(?::([0-5]\d))?\s?(am|pm)(?=\s)', caseSensitive: false),
      (m) {
    var h = int.parse(m.group(1)!);
    if (h < 1 || h > 12) return;
    final pm = m.group(3)!.toLowerCase() == 'pm';
    if (h == 12) h = 0;
    hour = pm ? h + 12 : h;
    minute = int.tryParse(m.group(2) ?? '') ?? 0;
  });
  if (hour == null) {
    text = cut(RegExp(r'\s(?:at\s+)?([01]?\d|2[0-3]):([0-5]\d)(?=\s)'), (m) {
      hour = int.parse(m.group(1)!);
      minute = int.parse(m.group(2)!);
    });
  }

  text = cut(RegExp(r'\s(today|tonight|tomorrow|tmrw|tmr)(?=\s)', caseSensitive: false), (m) {
    final w = m.group(1)!.toLowerCase();
    day = w.startsWith('to') && w != 'tomorrow' ? today : today.add(const Duration(days: 1));
    tonight = w == 'tonight';
  });
  if (day == null) {
    text = cut(RegExp(r'\snext\s+week(?=\s)', caseSensitive: false),
        (_) => day = today.add(const Duration(days: 7)));
  }
  if (day == null) {
    text = cut(RegExp(r'\sin\s+(\d{1,3})\s+days?(?=\s)', caseSensitive: false),
        (m) => day = today.add(Duration(days: int.parse(m.group(1)!))));
  }
  if (day == null) {
    text = cut(
        RegExp(
            r'\s(?:on\s+|next\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?=\s)',
            caseSensitive: false), (m) {
      final wd = _weekdays.indexOf(m.group(1)!.toLowerCase()) + 1;
      var ahead = (wd - now.weekday) % 7;
      if (ahead == 0) ahead = 7;
      day = today.add(Duration(days: ahead));
    });
  }
  if (day == null) {
    DateTime? dated(int d, String mon) {
      final mi = _months.indexOf(mon.substring(0, 3).toLowerCase()) + 1;
      if (mi == 0 || d < 1 || d > 31) return null;
      var r = DateTime(now.year, mi, d);
      if (r.month != mi) return null;
      if (r.isBefore(today)) r = DateTime(now.year + 1, mi, d);
      return r;
    }

    const mon = r'(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*';
    text = cut(RegExp('\\s(?:on\\s+)?(\\d{1,2})\\s+$mon(?=\\s)', caseSensitive: false),
        (m) => day = dated(int.parse(m.group(1)!), m.group(2)!));
    if (day == null) {
      text = cut(RegExp('\\s(?:on\\s+)?$mon\\s+(\\d{1,2})(?=\\s)', caseSensitive: false),
          (m) => day = dated(int.parse(m.group(2)!), m.group(1)!));
    }
  }

  if (tonight && hour == null) {
    hour = 20;
    minute = 0;
  }
  if (day == null && hour != null) {
    final at = DateTime(today.year, today.month, today.day, hour!, minute ?? 0);
    day = at.isAfter(now) ? today : today.add(const Duration(days: 1));
  }

  var title = text
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceFirst(RegExp(r'\s+(by|on|at|for|in|due)$', caseSensitive: false), '')
      .trim();
  if (title.isEmpty) title = input.trim();

  final d = day;
  return CaptureResult(
    title: title,
    due: d == null
        ? null
        : (hour == null ? d : DateTime(d.year, d.month, d.day, hour!, minute ?? 0)),
    allDay: d != null && hour == null,
    priority: priority,
    tag: tag,
  );
}

/// An email pasted into "Import from Email": the subject (or first line)
/// becomes the title, the rest the notes.
(String, String) parseEmail(String subject, String body) {
  var title = subject.trim().replaceFirst(RegExp(r'^((re|fw|fwd):\s*)+', caseSensitive: false), '');
  var notes = body.trim();
  if (title.isEmpty && notes.isNotEmpty) {
    final lines = notes.split('\n');
    title = lines.first.trim();
    notes = lines.skip(1).join('\n').trim();
  }
  if (title.length > 200) title = '${title.substring(0, 197)}...';
  return (title, notes);
}

// --------------------------------------------------------------- suggestions

enum SuggestionKind { team, label, dates }

class InboxSuggestion {
  final SuggestionKind kind;
  final String title;
  final String subtitle;
  final List<String> itemIds;
  final String? targetId;
  const InboxSuggestion(this.kind, this.title, this.subtitle, this.itemIds, {this.targetId});
}

bool _mentions(String title, String name) {
  final n = name.trim().toLowerCase();
  if (n.length < 3) return false;
  return RegExp('(^|[^\\p{L}\\p{N}])${RegExp.escape(n)}([^\\p{L}\\p{N}]|\$)', unicode: true)
      .hasMatch(title.toLowerCase());
}

/// Ways to organize the open [items]: tasks that name a team or a label,
/// and tasks without a date.
List<InboxSuggestion> inboxSuggestions(
    List<InboxItem> items, List<Team> teams, List<Category> categories) {
  final out = <InboxSuggestion>[];
  for (final t in teams) {
    final ids = [
      for (final i in items)
        if (i.teamId == null && _mentions(i.title, t.name)) i.id
    ];
    if (ids.isNotEmpty) {
      out.add(InboxSuggestion(
          SuggestionKind.team,
          'Add ${ids.length} ${ids.length == 1 ? 'task' : 'tasks'} to ${t.name}',
          'They mention ${t.name}',
          ids,
          targetId: t.id));
    }
  }
  for (final c in categories) {
    final ids = [
      for (final i in items)
        if (i.teamId == null && i.categoryId == null && _mentions(i.title, c.name)) i.id
    ];
    if (ids.isNotEmpty) {
      out.add(InboxSuggestion(
          SuggestionKind.label,
          'Label ${ids.length} ${ids.length == 1 ? 'task' : 'tasks'} "${c.name}"',
          'Related to ${c.name}',
          ids,
          targetId: c.id));
    }
  }
  final undated = [
    for (final i in items)
      if (i.dueAt == null) i.id
  ];
  if (undated.isNotEmpty) {
    out.add(InboxSuggestion(
        SuggestionKind.dates,
        'Add due dates to ${undated.length} ${undated.length == 1 ? 'task' : 'tasks'}',
        'Tasks without a due date',
        undated));
  }
  return out;
}

// --------------------------------------------------------------------- store

/// The signed-in user's inbox (users/{uid}/inbox), kept live.
class InboxStore extends ChangeNotifier {
  InboxStore._();
  static final InboxStore instance = InboxStore._();

  /// How long organized items stay for "Recently organized".
  static const keepOrganized = Duration(days: 7);

  String? _uid;
  List<InboxItem> _all = [];
  StreamSubscription<dynamic>? _sub;
  bool _testing = false;

  FirebaseFirestore get _fs => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _fs.collection('users').doc(uid).collection('inbox');

  /// Still to organize, newest first.
  List<InboxItem> get items => _all.where((i) => !i.isOrganized).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Moved on in the last week, newest first.
  List<InboxItem> get recentlyOrganized => _all.where((i) => i.isOrganized).toList()
    ..sort((a, b) => b.organizedAt!.compareTo(a.organizedAt!));

  int get count => _all.where((i) => !i.isOrganized).length;

  InboxItem? byId(String id) {
    for (final i in _all) {
      if (i.id == id) return i;
    }
    return null;
  }

  void start(String uid) {
    stop();
    _uid = uid;
    var cleaned = false;
    _sub = _col(uid).snapshots().listen((s) {
      final list = <InboxItem>[];
      for (final d in s.docs) {
        try {
          list.add(InboxItem.fromMap(d.data()));
        } catch (e) {
          debugPrint('Skipped bad inbox item: $e');
        }
      }
      _all = list;
      if (!cleaned && !s.metadata.isFromCache) {
        cleaned = true;
        final old = DateTime.now().subtract(keepOrganized);
        for (final i in list) {
          if (i.organizedAt != null && i.organizedAt!.isBefore(old)) {
            _write(_col(uid).doc(i.id).delete());
          }
        }
      }
      notifyListeners();
    }, onError: (Object e) => debugPrint('Inbox stream error: $e'));
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _uid = null;
    _all = [];
  }

  /// Tests only.
  void setForTest({String? uid, List<InboxItem> items = const []}) {
    _testing = true;
    _uid = uid;
    _all = [...items];
    notifyListeners();
  }

  void _write(Future<void> f) => f.catchError((Object e) => debugPrint('Inbox write failed: $e'));

  void _save(InboxItem item) {
    final i = _all.indexWhere((x) => x.id == item.id);
    if (i >= 0) {
      _all[i] = item;
    } else {
      _all.add(item);
    }
    notifyListeners();
    final uid = _uid;
    if (uid != null && !_testing) _write(_col(uid).doc(item.id).set(item.toMap()));
  }

  /// Adds a typed line: dates, times, !priority and #team / #label are read
  /// out of it ([parseCapture]).
  InboxItem? capture(String text,
      {String source = InboxSource.quick, String notes = '', List<TaskLink> links = const []}) {
    if (text.trim().isEmpty || _uid == null) return null;
    final r = parseCapture(text, DateTime.now());
    String? teamId;
    String? categoryId;
    final tag = r.tag?.toLowerCase();
    if (tag != null) {
      String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
      for (final t in TeamStore.instance.teams) {
        if (norm(t.name) == norm(tag)) teamId = t.id;
      }
      if (teamId == null) {
        for (final c in AppStore.instance.categories) {
          if (norm(c.name) == norm(tag)) categoryId = c.id;
        }
      }
    }
    final title =
        (tag != null && teamId == null && categoryId == null) ? '${r.title} #${r.tag}' : r.title;
    final item = InboxItem(
      id: newId(),
      title: title.length > 500 ? title.substring(0, 500) : title,
      notes: notes,
      source: source,
      createdAt: DateTime.now(),
      dueAt: r.due,
      allDay: r.allDay,
      priority: r.priority,
      teamId: teamId,
      categoryId: categoryId,
      links: [...links],
    );
    _save(item);
    return item;
  }

  void update(InboxItem item) => _save(item);

  void delete(Iterable<String> ids) {
    final set = ids.toSet();
    _all.removeWhere((i) => set.contains(i.id));
    notifyListeners();
    final uid = _uid;
    if (uid == null || _testing) return;
    final batch = _fs.batch();
    for (final id in set) {
      batch.delete(_col(uid).doc(id));
    }
    _write(batch.commit());
  }

  /// Why [item] cannot be moved to a team yet, or null.
  String? problem(InboxItem item) {
    final teamId = item.teamId;
    if (teamId == null) return null;
    final team = TeamStore.instance.teamById(teamId);
    if (team == null) return 'That team is no longer available.';
    final me = TeamStore.instance.uid;
    if (!TeamStore.instance.isAdmin(team) && item.assigneeId != null && item.assigneeId != me) {
      return 'Only an owner or manager can give tasks to others in ${team.name}.';
    }
    return null;
  }

  /// The task [item] becomes, on [day] when it has no date yet.
  TaskItem taskFor(InboxItem item, {DateTime? day}) {
    final now = DateTime.now();
    final due = item.dueAt ?? dateOnly(day ?? now);
    final allDay = item.dueAt == null || item.allDay;
    final start = allDay ? dateOnly(due) : due;
    var end = allDay
        ? DateTime(due.year, due.month, due.day, 23, 59)
        : start.add(const Duration(hours: 1));
    if (!isSameDay(end, start)) end = DateTime(start.year, start.month, start.day, 23, 59);
    final team = item.teamId == null ? null : TeamStore.instance.teamById(item.teamId!);
    final me = TeamStore.instance.uid;
    return TaskItem(
      id: newId(),
      title: item.title,
      description: item.notes,
      categoryId: team == null ? item.categoryId : null,
      assigneeId: team == null ? null : (TeamStore.instance.isAdmin(team) ? item.assigneeId : me),
      priority: item.priority ?? Priority.medium,
      startAt: start,
      endAt: end,
      createdAt: now,
      updatedAt: now,
    )..links = [...item.links];
  }

  /// Moves [item] to My Tasks or its team. Returns an error, or null.
  Future<String?> organize(InboxItem item, {DateTime? day}) async {
    final err = problem(item);
    if (err != null) return err;
    final task = taskFor(item, day: day);
    final team = item.teamId == null ? null : TeamStore.instance.teamById(item.teamId!);
    if (team == null) {
      await AppStore.instance.saveTask(task, const [], isNew: true);
    } else {
      TeamStore.instance.saveTask(team, task, [], isNew: true);
    }
    item
      ..organizedAt = DateTime.now()
      ..organizedTo = team == null ? 'My Tasks' : team.name
      ..taskId = task.id
      ..taskTeamId = team?.id;
    _save(item);
    return null;
  }

  /// Sends [item] to a teammate's inbox ([team] is the team you share).
  void forward(InboxItem item, Team team, String toUid) {
    final me = _uid;
    if (me == null) return;
    final copy = InboxItem(
      id: newId(),
      title: item.title,
      notes: item.notes,
      source: InboxSource.forwarded,
      createdAt: DateTime.now(),
      dueAt: item.dueAt,
      allDay: item.allDay,
      priority: item.priority,
      teamId: team.id,
      links: [...item.links],
      fromId: me,
      fromName: team.nameOf(me),
    );
    if (!_testing) _write(_col(toUid).doc(copy.id).set(copy.toMap()));
    item
      ..organizedAt = DateTime.now()
      ..organizedTo = 'Forwarded to ${team.nameOf(toUid)}';
    _save(item);
  }
}
