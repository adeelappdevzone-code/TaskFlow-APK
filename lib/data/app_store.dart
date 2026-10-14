import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/utils.dart';
import 'database.dart';
import 'models.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Simple non-reversible hash for the local password (FNV-1a, salted).
/// Good enough for an offline single-device app; the cloud version will use
/// proper server-side hashing (bcrypt) instead.
String hashPassword(String email, String password) {
  final input = utf8.encode('taskflow:${email.trim().toLowerCase()}:$password');
  var h1 = 0x811c9dc5;
  var h2 = 0x01000193;
  for (final b in input) {
    h1 = ((h1 ^ b) * 0x01000193) & 0xFFFFFFFF;
    h2 = ((h2 ^ (b + 31)) * 0x01000193) & 0xFFFFFFFF;
  }
  return h1.toRadixString(16).padLeft(8, '0') + h2.toRadixString(16).padLeft(8, '0');
}

/// Single source of truth for the app.
///
/// Screens listen to this object; every change is written to SQLite first and
/// then the in-memory lists are updated and listeners are notified.
/// This is the "repository layer": when cloud sync is added, only this class
/// needs to talk to the API — screens stay the same.
class AppStore extends ChangeNotifier {
  AppStore._();
  static final AppStore instance = AppStore._();

  static const _sessionKey = 'session_user_id';
  static const _seenOnboardingKey = 'seen_onboarding';

  AppUser? currentUser;
  bool seenOnboarding = false;

  List<Category> categories = [];
  List<Project> projects = [];
  List<Member> members = [];
  List<TaskItem> tasks = [];
  List<AppNotification> notifications = [];

  Timer? _reminderTimer;

  Future<Database> get _db => AppDatabase.instance.db;

  // ---------------------------------------------------------------- startup

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    seenOnboarding = prefs.getBool(_seenOnboardingKey) ?? false;
    final userId = prefs.getString(_sessionKey);
    if (userId != null) {
      final db = await _db;
      final rows = await db.query('users', where: 'id = ?', whereArgs: [userId]);
      if (rows.isNotEmpty) {
        currentUser = AppUser.fromMap(rows.first);
        await loadAll();
        _startReminderTimer();
      } else {
        await prefs.remove(_sessionKey);
      }
    }
  }

  Future<void> markOnboardingSeen() async {
    seenOnboarding = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenOnboardingKey, true);
  }

  Future<void> loadAll() async {
    final db = await _db;
    categories = (await db.query('categories',
            where: 'deleted_at IS NULL', orderBy: 'created_at'))
        .map(Category.fromMap)
        .toList();
    projects = (await db.query('projects',
            where: 'deleted_at IS NULL', orderBy: 'created_at'))
        .map(Project.fromMap)
        .toList();
    members = (await db.query('members',
            where: 'deleted_at IS NULL', orderBy: 'name COLLATE NOCASE'))
        .map(Member.fromMap)
        .toList();

    final items = (await db.query('checklist_items',
            where: 'deleted_at IS NULL', orderBy: 'sort_order'))
        .map(ChecklistItem.fromMap)
        .toList();
    final byTask = <String, List<ChecklistItem>>{};
    for (final c in items) {
      byTask.putIfAbsent(c.taskId, () => []).add(c);
    }
    tasks = (await db.query('tasks',
            where: 'deleted_at IS NULL', orderBy: 'start_at'))
        .map((m) {
      final t = TaskItem.fromMap(m);
      t.checklist = byTask[t.id] ?? [];
      return t;
    }).toList();

    notifications = (await db.query('notifications', orderBy: 'created_at DESC'))
        .map(AppNotification.fromMap)
        .toList();
    notifyListeners();
  }

  // ------------------------------------------------------------------- auth

  Future<bool> hasAccount() async {
    final db = await _db;
    final c = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM users'));
    return (c ?? 0) > 0;
  }

  /// Returns an error message, or null on success.
  Future<String?> register({
    required String name,
    required String email,
    required String password,
    required bool withSampleData,
  }) async {
    final db = await _db;
    if (await hasAccount()) {
      return 'An account already exists on this phone. Please log in, '
          'or reset the app data from Settings.';
    }
    final now = DateTime.now();
    final user = AppUser(
      id: newId(),
      name: name.trim(),
      email: email.trim().toLowerCase(),
      passwordHash: hashPassword(email, password),
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('users', user.toMap());
    currentUser = user;
    await _saveSession(user.id);
    await _seedDefaults(withSampleData);
    await loadAll();
    _startReminderTimer();
    return null;
  }

  Future<String?> login(String email, String password) async {
    final db = await _db;
    final rows = await db.query('users',
        where: 'email = ?', whereArgs: [email.trim().toLowerCase()]);
    if (rows.isEmpty) return 'No account found with this email.';
    final user = AppUser.fromMap(rows.first);
    if (user.passwordHash != hashPassword(email, password)) {
      return 'Incorrect password.';
    }
    currentUser = user;
    await _saveSession(user.id);
    await loadAll();
    _startReminderTimer();
    return null;
  }

  /// Offline password reset: the account is on this phone, so the user can
  /// set a new password after confirming their email.
  Future<String?> resetPassword(String email, String newPassword) async {
    final db = await _db;
    final rows = await db.query('users',
        where: 'email = ?', whereArgs: [email.trim().toLowerCase()]);
    if (rows.isEmpty) return 'No account found with this email on this phone.';
    await db.update(
      'users',
      {
        'password_hash': hashPassword(email, newPassword),
        'updated_at': nowMs(),
        'is_synced': 0,
      },
      where: 'id = ?',
      whereArgs: [rows.first['id']],
    );
    return null;
  }

  Future<String?> updateProfile(String name, String email) async {
    final user = currentUser;
    if (user == null) return 'Not logged in';
    final db = await _db;
    final newEmail = email.trim().toLowerCase();
    final emailChanged = newEmail != user.email;
    if (emailChanged) {
      // The password hash is salted with the email, so ask for a new one.
      return 'email_change_needs_password';
    }
    user.name = name.trim();
    user.updatedAt = DateTime.now();
    await db.update('users', user.toMap(), where: 'id = ?', whereArgs: [user.id]);
    notifyListeners();
    return null;
  }

  Future<String?> changeEmailAndPassword(
      String name, String email, String password) async {
    final user = currentUser;
    if (user == null) return 'Not logged in';
    final db = await _db;
    user.name = name.trim();
    user.email = email.trim().toLowerCase();
    user.passwordHash = hashPassword(email, password);
    user.updatedAt = DateTime.now();
    await db.update('users', user.toMap(), where: 'id = ?', whereArgs: [user.id]);
    notifyListeners();
    return null;
  }

  Future<void> logout() async {
    _reminderTimer?.cancel();
    currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    notifyListeners();
  }

  Future<void> _saveSession(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, userId);
  }

  // ---------------------------------------------------------------- lookups

  Category? categoryById(String? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Project? projectById(String? id) {
    if (id == null) return null;
    for (final p in projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  Member? memberById(String? id) {
    if (id == null) return null;
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  TaskItem? taskById(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  List<TaskItem> tasksOnDay(DateTime day) =>
      tasks.where((t) => isSameDay(t.startAt, day)).toList();

  List<TaskItem> get todayTasks => tasksOnDay(DateTime.now())
      .where((t) => !t.isCancelled)
      .toList();

  List<TaskItem> get activeTasks => tasks.where((t) => !t.isCancelled).toList();

  int get totalCount => activeTasks.length;
  int get doneCount => tasks.where((t) => t.isCompleted).length;
  int get pendingCount => totalCount - doneCount;

  List<TaskItem> tasksOfProject(String projectId) =>
      tasks.where((t) => t.projectId == projectId && !t.isCancelled).toList();

  /// 0.0 – 1.0
  double projectProgress(String projectId) {
    final list = tasksOfProject(projectId);
    if (list.isEmpty) return 0;
    return list.where((t) => t.isCompleted).length / list.length;
  }

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  // ------------------------------------------------------------------ tasks

  /// Creates or updates a task together with its checklist.
  Future<void> saveTask(TaskItem task, List<ChecklistItem> checklist,
      {required bool isNew}) async {
    final db = await _db;
    final now = DateTime.now();
    task.updatedAt = now;
    String? previousAssignee;
    if (!isNew) {
      final old = await db.query('tasks',
          columns: ['assignee_id'], where: 'id = ?', whereArgs: [task.id]);
      if (old.isNotEmpty) previousAssignee = old.first['assignee_id'] as String?;
    }

    await db.transaction((txn) async {
      await txn.insert('tasks', task.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

      // Soft-delete checklist items that were removed in the form.
      final keepIds = checklist.map((c) => c.id).toList();
      final existing = await txn.query('checklist_items',
          columns: ['id'],
          where: 'task_id = ? AND deleted_at IS NULL',
          whereArgs: [task.id]);
      for (final row in existing) {
        final id = row['id'] as String;
        if (!keepIds.contains(id)) {
          await txn.update(
              'checklist_items',
              {'deleted_at': now.millisecondsSinceEpoch, 'updated_at': now.millisecondsSinceEpoch, 'is_synced': 0},
              where: 'id = ?',
              whereArgs: [id]);
        }
      }
      for (var i = 0; i < checklist.length; i++) {
        final c = checklist[i];
        c.sortOrder = i;
        c.updatedAt = now;
        await txn.insert('checklist_items', c.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    if (task.assigneeId != null && task.assigneeId != previousAssignee) {
      final m = memberById(task.assigneeId);
      if (m != null) {
        await _notify('task', 'assigned', 'Task assigned',
            '"${task.title}" was assigned to ${m.name}', taskId: task.id);
      }
    }
    await loadAll();
  }

  Future<void> setCompleted(TaskItem task, bool done) async {
    final db = await _db;
    final now = DateTime.now();
    task.status = done ? TaskStatus.completed : TaskStatus.pending;
    task.completedAt = done ? now : null;
    task.updatedAt = now;
    await db.update('tasks', task.toMap(), where: 'id = ?', whereArgs: [task.id]);
    if (done) {
      await _notify('task', 'completed', 'Task completed',
          '"${task.title}" has been completed', taskId: task.id);
    }
    await loadAll();
  }

  Future<void> cancelTask(TaskItem task) async {
    final db = await _db;
    task.status = TaskStatus.cancelled;
    task.updatedAt = DateTime.now();
    await db.update('tasks', task.toMap(), where: 'id = ?', whereArgs: [task.id]);
    await _notify('task', 'cancelled', 'Task cancelled',
        '"${task.title}" was cancelled', taskId: task.id);
    await loadAll();
  }

  Future<void> restoreTask(TaskItem task) async {
    final db = await _db;
    task.status = TaskStatus.pending;
    task.updatedAt = DateTime.now();
    await db.update('tasks', task.toMap(), where: 'id = ?', whereArgs: [task.id]);
    await loadAll();
  }

  Future<void> deleteTask(TaskItem task) async {
    final db = await _db;
    final now = nowMs();
    await db.update('tasks', {'deleted_at': now, 'updated_at': now, 'is_synced': 0},
        where: 'id = ?', whereArgs: [task.id]);
    await db.update('checklist_items',
        {'deleted_at': now, 'updated_at': now, 'is_synced': 0},
        where: 'task_id = ?', whereArgs: [task.id]);
    await loadAll();
  }

  Future<void> toggleChecklistItem(ChecklistItem item) async {
    final db = await _db;
    item.isDone = !item.isDone;
    item.updatedAt = DateTime.now();
    await db.update('checklist_items', item.toMap(),
        where: 'id = ?', whereArgs: [item.id]);
    await loadAll();
  }

  // --------------------------------------------------------------- projects

  Future<Project> addProject(String name, int color) async {
    final db = await _db;
    final now = DateTime.now();
    final p = Project(
        id: newId(), name: name.trim(), color: color, createdAt: now, updatedAt: now);
    await db.insert('projects', p.toMap());
    await _notify('system', 'project', 'Project created',
        'Project "${p.name}" was created');
    await loadAll();
    return p;
  }

  Future<void> updateProject(Project p) async {
    final db = await _db;
    p.updatedAt = DateTime.now();
    await db.update('projects', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
    await _notify('system', 'project', 'Project updated',
        'Project "${p.name}" was updated');
    await loadAll();
  }

  /// Deletes the project; its tasks are kept but detached from it.
  Future<void> deleteProject(Project p) async {
    final db = await _db;
    final now = nowMs();
    await db.update('projects', {'deleted_at': now, 'updated_at': now, 'is_synced': 0},
        where: 'id = ?', whereArgs: [p.id]);
    await db.update('tasks', {'project_id': null, 'updated_at': now, 'is_synced': 0},
        where: 'project_id = ?', whereArgs: [p.id]);
    await loadAll();
  }

  // ------------------------------------------------------------- categories

  Future<Category> addCategory(String name, int color) async {
    final db = await _db;
    final now = DateTime.now();
    final c = Category(
        id: newId(), name: name.trim(), color: color, createdAt: now, updatedAt: now);
    await db.insert('categories', c.toMap());
    await loadAll();
    return c;
  }

  Future<void> updateCategory(Category c) async {
    final db = await _db;
    c.updatedAt = DateTime.now();
    await db.update('categories', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
    await loadAll();
  }

  Future<void> deleteCategory(Category c) async {
    final db = await _db;
    final now = nowMs();
    await db.update('categories', {'deleted_at': now, 'updated_at': now, 'is_synced': 0},
        where: 'id = ?', whereArgs: [c.id]);
    await db.update('tasks', {'category_id': null, 'updated_at': now, 'is_synced': 0},
        where: 'category_id = ?', whereArgs: [c.id]);
    await loadAll();
  }

  // ---------------------------------------------------------------- members

  Future<Member> addMember(String name) async {
    final db = await _db;
    final now = DateTime.now();
    final m = Member(id: newId(), name: name.trim(), createdAt: now, updatedAt: now);
    await db.insert('members', m.toMap());
    await loadAll();
    return m;
  }

  Future<void> deleteMember(Member m) async {
    final db = await _db;
    final now = nowMs();
    await db.update('members', {'deleted_at': now, 'updated_at': now, 'is_synced': 0},
        where: 'id = ?', whereArgs: [m.id]);
    await db.update('tasks', {'assignee_id': null, 'updated_at': now, 'is_synced': 0},
        where: 'assignee_id = ?', whereArgs: [m.id]);
    await loadAll();
  }

  // ---------------------------------------------------------- notifications

  Future<void> _notify(String type, String kind, String title, String body,
      {String? taskId}) async {
    final db = await _db;
    final n = AppNotification(
      id: newId(),
      type: type,
      kind: kind,
      title: title,
      body: body,
      taskId: taskId,
      createdAt: DateTime.now(),
    );
    await db.insert('notifications', n.toMap());
  }

  Future<void> markAllRead() async {
    if (unreadCount == 0) return;
    final db = await _db;
    await db.update('notifications', {'read_at': nowMs()}, where: 'read_at IS NULL');
    await loadAll();
  }

  Future<void> clearNotifications() async {
    final db = await _db;
    await db.delete('notifications');
    await loadAll();
  }

  /// In-app reminders: while the app is open, every minute we check for tasks
  /// starting in the next 15 minutes and add a reminder (once per task).
  /// Phone-level push reminders (when the app is closed) come in a later version.
  void _startReminderTimer() {
    _reminderTimer?.cancel();
    _checkReminders();
    _reminderTimer =
        Timer.periodic(const Duration(minutes: 1), (_) => _checkReminders());
  }

  Future<void> _checkReminders() async {
    if (currentUser == null) return;
    final now = DateTime.now();
    final soon = now.add(const Duration(minutes: 15));
    var added = false;
    for (final t in tasks) {
      if (t.status != TaskStatus.pending) continue;
      if (t.startAt.isBefore(now) || t.startAt.isAfter(soon)) continue;
      final already = notifications
          .any((n) => n.kind == 'reminder' && n.taskId == t.id);
      if (already) continue;
      final mins = t.startAt.difference(now).inMinutes;
      await _notify('task', 'reminder', 'Reminder',
          '"${t.title}" starts in ${mins <= 1 ? '1 minute' : '$mins minutes'}',
          taskId: t.id);
      added = true;
    }
    if (added) await loadAll();
  }

  // ------------------------------------------------------- backup / restore

  /// Whole database as JSON (copied to clipboard from Settings).
  Future<String> exportBackup() async {
    final db = await _db;
    final data = <String, dynamic>{
      'app': 'taskflow',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
    };
    for (final table in AppDatabase.dataTables) {
      data[table] = await db.query(table);
    }
    return jsonEncode(data);
  }

  /// Replaces all local data with the backup. Returns an error or null.
  Future<String?> importBackup(String json) async {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(json.trim()) as Map<String, dynamic>;
    } catch (_) {
      return 'This is not a valid TaskFlow backup.';
    }
    if (data['app'] != 'taskflow') return 'This is not a valid TaskFlow backup.';
    final db = await _db;
    try {
      await db.transaction((txn) async {
        for (final table in AppDatabase.dataTables) {
          await txn.delete(table);
          final rows = (data[table] as List?) ?? [];
          for (final r in rows) {
            await txn.insert(table, Map<String, dynamic>.from(r as Map));
          }
        }
      });
    } catch (e) {
      return 'Restore failed: $e';
    }
    final users = await db.query('users', limit: 1);
    if (users.isEmpty) {
      await logout();
      return null;
    }
    currentUser = AppUser.fromMap(users.first);
    await _saveSession(currentUser!.id);
    await loadAll();
    return null;
  }

  /// Wipes everything on this phone.
  Future<void> resetAllData() async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final table in AppDatabase.dataTables) {
        await txn.delete(table);
      }
    });
    categories = [];
    projects = [];
    members = [];
    tasks = [];
    notifications = [];
    await logout();
  }

  // ------------------------------------------------------------ seed data

  Future<void> _seedDefaults(bool withSample) async {
    final db = await _db;
    final now = DateTime.now();
    final ms = now.millisecondsSinceEpoch;

    Map<String, dynamic> cat(String id, String name, int color) => Category(
            id: id,
            name: name,
            color: color,
            createdAt: now,
            updatedAt: now)
        .toMap();

    final work = newId(), design = newId(), general = newId(), research = newId();
    final batch = db.batch();
    batch.insert('categories', cat(work, 'Work', 0xFF1F6FEB));
    batch.insert('categories', cat(design, 'Design', 0xFF7C3AED));
    batch.insert('categories', cat(general, 'General', 0xFF6B7280));
    batch.insert('categories', cat(research, 'Research', 0xFFF97316));

    batch.insert(
        'notifications',
        AppNotification(
          id: newId(),
          type: 'system',
          kind: 'info',
          title: 'Welcome to TaskFlow',
          body: 'Your data is saved on this phone. Cloud sync is coming soon.',
          createdAt: now,
        ).toMap());

    if (withSample) {
      final today = dateOnly(now);
      DateTime at(int dayOffset, int h, [int m = 0]) =>
          today.add(Duration(days: dayOffset, hours: h, minutes: m));

      final pApp = newId(), pDesign = newId(), pMkt = newId();
      Map<String, dynamic> proj(String id, String name, int color) => Project(
              id: id, name: name, color: color, createdAt: now, updatedAt: now)
          .toMap();
      batch.insert('projects', proj(pApp, 'App Development', 0xFF16A34A));
      batch.insert('projects', proj(pDesign, 'UI/UX Design', 0xFFF97316));
      batch.insert('projects', proj(pMkt, 'Marketing', 0xFF7C3AED));

      final budi = newId();
      batch.insert('members',
          Member(id: budi, name: 'Ali Raza', createdAt: now, updatedAt: now).toMap());

      void task(String title, String cat, int day, int h, int endH,
          {String? project,
          String? assignee,
          Priority pr = Priority.medium,
          bool done = false,
          String desc = '',
          List<List<Object>> checklist = const []}) {
        final id = newId();
        batch.insert(
            'tasks',
            TaskItem(
              id: id,
              title: title,
              description: desc,
              categoryId: cat,
              projectId: project,
              assigneeId: assignee,
              priority: pr,
              status: done ? TaskStatus.completed : TaskStatus.pending,
              startAt: at(day, h),
              endAt: at(day, endH),
              completedAt: done ? now : null,
              createdAt: now,
              updatedAt: now,
            ).toMap());
        for (var i = 0; i < checklist.length; i++) {
          batch.insert(
              'checklist_items',
              ChecklistItem(
                id: newId(),
                taskId: id,
                title: checklist[i][0] as String,
                isDone: checklist[i][1] as bool,
                sortOrder: i,
                createdAt: now,
                updatedAt: now,
              ).toMap());
        }
      }

      task('Prepare weekly report', work, 0, 9, 10, done: true, project: pMkt);
      task('Team meeting', work, 0, 11, 12, project: pApp);
      task('Design app UI', design, 0, 13, 15,
          project: pDesign,
          assignee: budi,
          pr: Priority.high,
          desc: 'Design the app screens based on the approved wireframes.',
          checklist: [
            ['Create wireframe', true],
            ['Design home screen', true],
            ['Design reports screen', false],
            ['Review with team', false],
          ]);
      task('Buy office supplies', general, 0, 16, 17, pr: Priority.low);
      task('Code review', work, 1, 10, 11, project: pApp, pr: Priority.high);
      task('Research new feature', research, 1, 14, 16, project: pApp);
      task('Social media plan', work, 3, 11, 12, project: pMkt);
    }
    await batch.commit(noResult: true);
    debugPrint('Seeded defaults at $ms');
  }
}
