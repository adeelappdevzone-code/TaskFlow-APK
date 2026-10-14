import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite database. Lives only on this phone.
///
/// Schema mirrors what the future cloud database (e.g. Laravel + MySQL) will
/// use, so sync can be added later by reading rows where is_synced = 0.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'taskflow.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, _dbName),
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        final batch = db.batch();
        for (final sql in _schema) {
          batch.execute(sql);
        }
        await batch.commit(noResult: true);
      },
      // Future schema changes go here, e.g.
      // onUpgrade: (db, oldV, newV) async { if (oldV < 2) {...} },
    );
  }

  static const _sync = '''
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER,
      is_synced INTEGER NOT NULL DEFAULT 0''';

  static const List<String> _schema = [
    '''
    CREATE TABLE users (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      is_synced INTEGER NOT NULL DEFAULT 0
    )''',
    '''
    CREATE TABLE categories (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      color INTEGER NOT NULL,
      $_sync
    )''',
    '''
    CREATE TABLE projects (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      color INTEGER NOT NULL,
      $_sync
    )''',
    '''
    CREATE TABLE members (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      $_sync
    )''',
    '''
    CREATE TABLE tasks (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      category_id TEXT,
      project_id TEXT,
      assignee_id TEXT,
      priority INTEGER NOT NULL DEFAULT 1,
      status TEXT NOT NULL DEFAULT 'pending',
      start_at INTEGER NOT NULL,
      end_at INTEGER,
      completed_at INTEGER,
      $_sync
    )''',
    'CREATE INDEX idx_tasks_start ON tasks(start_at)',
    'CREATE INDEX idx_tasks_project ON tasks(project_id)',
    '''
    CREATE TABLE checklist_items (
      id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL,
      title TEXT NOT NULL,
      is_done INTEGER NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0,
      $_sync
    )''',
    'CREATE INDEX idx_checklist_task ON checklist_items(task_id)',
    '''
    CREATE TABLE notifications (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      kind TEXT NOT NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      task_id TEXT,
      created_at INTEGER NOT NULL,
      read_at INTEGER
    )''',
  ];

  /// Tables that are included in backups / future sync.
  static const dataTables = [
    'users',
    'categories',
    'projects',
    'members',
    'tasks',
    'checklist_items',
    'notifications',
  ];
}
