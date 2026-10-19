import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart'
    show
        CollectionReference,
        DocumentReference,
        FirebaseFirestore,
        SetOptions,
        Settings,
        WriteBatch;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart'
    show GoogleSignIn, GoogleSignInException, GoogleSignInExceptionCode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/utils.dart';
import 'capacity.dart';
import 'chat_store.dart';
import 'inbox.dart';
import 'models.dart';
import 'reminders.dart';
import 'task_repository.dart';
import 'team_store.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Id of the next copy of a repeating task. Always the same for the same
/// task, so finishing it twice (or on two phones) never makes two copies.
String repeatIdFor(String taskId) => _uuid.v5(Namespace.url.value, 'taskflow:repeat:$taskId');

typedef _Json = Map<String, dynamic>;

/// Single source of truth for the app.
///
/// Login: Firebase Authentication (email + password).
/// Data:  Cloud Firestore under /users/{uid}/... (categories, projects,
///        members, tasks, notifications).
///
/// Firestore keeps a local copy on the phone, so the app works offline:
/// changes are shown immediately and uploaded when internet comes back.
/// Because of that, writes are NOT awaited (an offline write would only
/// complete once the phone is online again). Screens update through the
/// live listeners below.
class AppStore extends ChangeNotifier {
  AppStore._();
  static final AppStore instance = AppStore._();

  static const _seenOnboardingKey = 'seen_onboarding';

  AppUser? currentUser;
  bool seenOnboarding = false;

  List<Category> categories = [];
  List<Project> projects = [];
  List<Member> members = [];
  List<TaskItem> tasks = [];
  List<AppNotification> notifications = [];
  List<TaskTemplate> templates = [];

  // Profile extras and preferences, saved in users/{uid} so they are the
  // same on every phone / browser.
  String jobTitle = '';
  int reminderMinutes = 15; // 0 = no reminders
  bool teamAlerts = true; // phone notifications for team events
  DateTime? lastBackupAt;

  // Notification Center switches (what gets a notification at all).
  bool notifAssign = true;
  bool notifApprovals = true;
  bool notifComments = true;

  /// My Tasks filters saved by name (in users/{uid}, at most 20).
  List<SavedView> savedViews = [];

  /// Work day for the planner, minutes after midnight.
  int workStart = 9 * 60;
  int workEnd = 17 * 60 + 30;

  /// Work days (DateTime.monday..DateTime.sunday).
  List<int> workDays = defaultWorkDays;

  /// True once I saved my own work hours (Team Workload then uses them).
  bool workHoursSet = false;

  static const defaultWorkDays = [1, 2, 3, 4, 5];

  bool isWorkDay(DateTime d) => workDays.contains(d.weekday);

  /// Minutes I work in a week.
  int get weekMinutes => (workEnd - workStart).clamp(0, 24 * 60) * workDays.length;

  Timer? _reminderTimer;
  Timer? _phoneReminderSync;
  final List<StreamSubscription<dynamic>> _subs = [];

  FirebaseFirestore get _fs => FirebaseFirestore.instance;
  fb.FirebaseAuth get _auth => fb.FirebaseAuth.instance;

  DocumentReference<_Json> get _userDoc => _fs.collection('users').doc(currentUser!.id);

  CollectionReference<_Json> _col(String name) => _userDoc.collection(name);

  // ---------------------------------------------------------------- startup

  /// Call after Firebase.initializeApp().
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    seenOnboarding = prefs.getBool(_seenOnboardingKey) ?? false;
    try {
      _fs.settings = const Settings(persistenceEnabled: true);
    } catch (e) {
      debugPrint('Firestore settings: $e');
    }
    await PhoneReminders.instance.init();

    // If Firebase ends the login by itself (account disabled or deleted,
    // password changed on another phone...), go back to the login screen.
    // AppStore lives as long as the app, so this listener is never cancelled.
    _auth.authStateChanges().listen((u) {
      if (u == null && currentUser != null) {
        _endSession();
        notifyListeners();
      }
    });

    final u = _auth.currentUser;
    if (u != null) {
      _startSession(u);
      _checkAccountStillValid(u);
    }
  }

  /// The saved login is used without internet, so the app does not know if
  /// the account was disabled or deleted meanwhile. Ask Firebase once at
  /// startup; network errors are ignored (offline use keeps working).
  Future<void> _checkAccountStillValid(fb.User u) async {
    try {
      await u.reload();
    } on fb.FirebaseAuthException catch (e) {
      const gone = {'user-disabled', 'user-not-found', 'user-token-expired', 'invalid-user-token'};
      if (gone.contains(e.code)) {
        debugPrint('Account no longer valid (${e.code}), logging out');
        await logout();
      }
    } catch (e) {
      debugPrint('Account check: $e');
    }
  }

  Future<void> markOnboardingSeen() async {
    seenOnboarding = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenOnboardingKey, true);
  }

  void _startSession(fb.User u, {String? name}) {
    final email = u.email ?? '';
    currentUser = AppUser(
      id: u.uid,
      name: (name != null && name.isNotEmpty)
          ? name
          : ((u.displayName != null && u.displayName!.isNotEmpty)
              ? u.displayName!
              : (email.isEmpty ? 'User' : email.split('@').first)),
      email: email,
      passwordHash: '',
      createdAt: u.metadata.creationTime ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _listen();
    _startReminderTimer();
    PhoneReminders.instance.askPermission();
    TeamStore.instance.start(uid: u.uid, email: email, name: currentUser!.name);
    InboxStore.instance.start(u.uid);
    ChatStore.instance.start(uid: u.uid, email: email, name: currentUser!.name);
    BusySync.instance.start();
    notifyListeners();
  }

  void _endSession() {
    _reminderTimer?.cancel();
    _phoneReminderSync?.cancel();
    PhoneReminders.instance.clear();
    TeamStore.instance.stop();
    InboxStore.instance.stop();
    ChatStore.instance.stop();
    BusySync.instance.stop();
    _cancelSubs();
    currentUser = null;
    categories = [];
    projects = [];
    members = [];
    tasks = [];
    notifications = [];
    templates = [];
    jobTitle = '';
    reminderMinutes = 15;
    teamAlerts = true;
    notifAssign = true;
    notifApprovals = true;
    notifComments = true;
    workStart = 9 * 60;
    workEnd = 17 * 60 + 30;
    workDays = defaultWorkDays;
    workHoursSet = false;
    savedViews = [];
    lastBackupAt = null;
  }

  // ------------------------------------------------------- live listeners

  void _cancelSubs() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  void _listen() {
    _cancelSubs();

    _subs.add(_userDoc.snapshots().listen((s) {
      final d = s.data() ?? const {};
      jobTitle = (d['title'] as String?) ?? '';
      reminderMinutes = (d['reminder_minutes'] as int?) ?? 15;
      teamAlerts = (d['team_alerts'] as bool?) ?? true;
      notifAssign = (d['notif_assign'] as bool?) ?? true;
      notifApprovals = (d['notif_approvals'] as bool?) ?? true;
      notifComments = (d['notif_comments'] as bool?) ?? true;
      savedViews = [
        ...((d['saved_views'] as List?) ?? const []).map(SavedView.tryFrom).whereType<SavedView>(),
      ];
      workStart = (d['work_start'] as int?) ?? 9 * 60;
      workEnd = (d['work_end'] as int?) ?? 17 * 60 + 30;
      final days = {
        for (final x in (d['work_days'] as List?) ?? const [])
          if (x is int && x >= 1 && x <= 7) x
      }.toList()
        ..sort();
      workDays = days.isEmpty ? defaultWorkDays : days;
      workHoursSet = d['work_start'] is int;
      _shareWorkHours();
      final backup = d['last_backup_at'];
      lastBackupAt = backup is int ? DateTime.fromMillisecondsSinceEpoch(backup) : null;
      schedulePhoneReminders();
      notifyListeners();
    }, onError: _onStreamError));

    _subs.add(_col('categories').snapshots().listen((s) {
      categories = _parse(s.docs.map((d) => d.data()), Category.fromMap)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      notifyListeners();
    }, onError: _onStreamError));

    _subs.add(_col('projects').snapshots().listen((s) {
      projects = _parse(s.docs.map((d) => d.data()), Project.fromMap)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      notifyListeners();
    }, onError: _onStreamError));

    _subs.add(_col('members').snapshots().listen((s) {
      members = _parse(s.docs.map((d) => d.data()), Member.fromMap)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      notifyListeners();
    }, onError: _onStreamError));

    _subs.add(_col('tasks').snapshots().listen((s) {
      tasks = _parse(s.docs.map((d) => d.data()), _taskFromMap)
        ..sort((a, b) => a.startAt.compareTo(b.startAt));
      schedulePhoneReminders();
      notifyListeners();
    }, onError: _onStreamError));

    _subs.add(_col('templates').snapshots().listen((s) {
      templates = _parse(s.docs.map((d) => d.data()), TaskTemplate.fromMap)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      notifyListeners();
    }, onError: _onStreamError));

    _subs.add(_col('notifications').snapshots().listen((s) {
      notifications = _parse(s.docs.map((d) => d.data()), AppNotification.fromMap)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }, onError: _onStreamError));
  }

  /// Parses documents one by one; a single bad document is skipped instead of
  /// breaking the whole list.
  List<T> _parse<T>(Iterable<_Json> docs, T Function(_Json) fromMap) {
    final out = <T>[];
    for (final m in docs) {
      try {
        out.add(fromMap(m));
      } catch (e) {
        debugPrint('Skipped bad document: $e');
      }
    }
    return out;
  }

  /// Tasks can change many times in a row (e.g. a batch write), so the phone
  /// reminders are re-scheduled once things settle. Covers personal tasks and
  /// team tasks assigned to me.
  void schedulePhoneReminders() {
    _phoneReminderSync?.cancel();
    _phoneReminderSync = Timer(const Duration(seconds: 2), () {
      if (currentUser != null) {
        PhoneReminders.instance.sync([...tasks, ...TeamStore.instance.myTeamTasks],
            lead: Duration(minutes: reminderMinutes));
      }
    });
  }

  void _onStreamError(Object e) {
    debugPrint('Firestore stream error: $e');
  }

  /// Fire-and-forget write (see class comment).
  void _write(Future<void> f) {
    f.then((_) {}, onError: (Object e) {
      debugPrint('Write failed: $e');
    });
  }

  _Json _taskToMap(TaskItem t) => taskToMap(t);
  TaskItem _taskFromMap(_Json m) => taskFromMap(m);

  /// Task document = task fields + its checklist (personal and team tasks).
  static Map<String, dynamic> taskToMap(TaskItem t) => {
        ...t.toMap(),
        'checklist': t.checklist.map((c) => c.toMap()).toList(),
      };

  static TaskItem taskFromMap(Map<String, dynamic> m) {
    final t = TaskItem.fromMap(m);
    final raw = m['checklist'];
    if (raw is List) {
      final items = <ChecklistItem>[];
      for (final c in raw) {
        if (c is Map) {
          try {
            items.add(ChecklistItem.fromMap(Map<String, dynamic>.from(c)));
          } catch (_) {}
        }
      }
      items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      t.checklist = items;
    }
    return t;
  }

  /// Runs many writes in batches of max 400 (Firestore limit is 500).
  void _runBatched(List<void Function(WriteBatch b)> ops) {
    for (var i = 0; i < ops.length; i += 400) {
      final batch = _fs.batch();
      for (final op in ops.sublist(i, min(i + 400, ops.length))) {
        op(batch);
      }
      _write(batch.commit());
    }
  }

  // ------------------------------------------------------------------- auth

  String _authError(fb.FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account with this email already exists. Please log in.';
      case 'invalid-email':
        return 'This email address is not valid.';
      case 'weak-password':
        return 'Password is too weak (use at least 6 characters).';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Email or password is incorrect.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'network-request-failed':
        return 'No internet connection. Please connect and try again.';
      case 'requires-recent-login':
        return 'For security, please log out, log in again, and then retry.';
      case 'operation-not-allowed':
        return 'Email/password login is not enabled in Firebase yet.';
      default:
        return e.message ?? 'Something went wrong (${e.code}).';
    }
  }

  /// Returns an error message, or null on success.
  Future<String?> register({
    required String name,
    required String email,
    required String password,
    required bool withSampleData,
  }) async {
    try {
      final cred =
          await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
      final u = cred.user;
      if (u == null) return 'Could not create the account. Please try again.';
      final cleanName = name.trim();
      try {
        await u.updateDisplayName(cleanName);
      } catch (_) {}
      // Needed later to accept team invitations (proves the email is theirs).
      u.sendEmailVerification().catchError((Object e) => debugPrint('Verify email: $e'));
      _startSession(u, name: cleanName);
      _write(_userDoc.set({
        'name': cleanName,
        'email': u.email ?? email.trim(),
        'created_at': nowMs(),
      }, SetOptions(merge: true)));
      _seedDefaults(withSampleData);
      return null;
    } on fb.FirebaseAuthException catch (e) {
      return _authError(e);
    } catch (e) {
      return 'Something went wrong: $e';
    }
  }

  Future<String?> login(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
      final u = cred.user;
      if (u == null) return 'Login failed. Please try again.';
      _startSession(u);
      return null;
    } on fb.FirebaseAuthException catch (e) {
      return _authError(e);
    } catch (e) {
      return 'Something went wrong: $e';
    }
  }

  // ------------------------------------------------------------ Google

  /// OAuth "Web client ID" of the Firebase project (Authentication → Google →
  /// Web SDK configuration). Needed so Google returns a token Firebase accepts.
  static const _googleServerClientId =
      '791768449553-0mvkrt16ogepku39do8thcs7tpaidg5t.apps.googleusercontent.com';

  /// Returned by [signInWithGoogle] when the user closes the account picker.
  static const googleCancelled = '__cancelled__';

  bool _googleReady = false;

  Future<void> _ensureGoogle() async {
    if (_googleReady) return;
    await GoogleSignIn.instance.initialize(serverClientId: _googleServerClientId);
    _googleReady = true;
  }

  /// Returns null on success, [googleCancelled] if the user backed out,
  /// otherwise an error message.
  Future<String?> signInWithGoogle() async {
    if (kIsWeb) return _signInWithGooglePopup();
    try {
      await _ensureGoogle();
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        return 'Google did not return a login token. Please try again.';
      }
      final result =
          await _auth.signInWithCredential(fb.GoogleAuthProvider.credential(idToken: idToken));
      final u = result.user;
      if (u == null) return 'Google login failed. Please try again.';
      final isNew = result.additionalUserInfo?.isNewUser ?? false;
      _startSession(u, name: u.displayName ?? account.displayName);
      if (isNew) {
        _write(_userDoc.set({
          'name': currentUser!.name,
          'email': u.email ?? account.email,
          'created_at': nowMs(),
        }, SetOptions(merge: true)));
        _seedDefaults(false);
      }
      return null;
    } on GoogleSignInException catch (e) {
      final desc = e.description ?? '';
      debugPrint('Google sign-in: ${e.code.name} $desc');
      if (e.code == GoogleSignInExceptionCode.canceled) {
        // Android's Credential Manager also reports a wrong Firebase setup
        // (app SHA-1 not added) as "canceled", e.g. "[16] Account reauth
        // failed". Only stay silent when the user really closed the picker.
        final lower = desc.toLowerCase();
        final byUser = desc.isEmpty ||
            lower.contains('cancelled by the user') ||
            lower.contains('canceled by the user');
        if (byUser) return googleCancelled;
        return 'Google sign-in failed: $desc\n'
            'Make sure the app\'s SHA-1 fingerprint is added in Firebase '
            '(Project settings → Your apps → Android).';
      }
      return 'Google sign-in failed (${e.code.name}). $desc'.trim();
    } on fb.FirebaseAuthException catch (e) {
      return _authError(e);
    } catch (e) {
      return 'Google sign-in failed: $e';
    }
  }

  /// Web: Firebase's own Google popup (the google_sign_in plugin works
  /// differently in browsers).
  Future<String?> _signInWithGooglePopup() async {
    try {
      final result = await _auth.signInWithPopup(fb.GoogleAuthProvider());
      final u = result.user;
      if (u == null) return 'Google login failed. Please try again.';
      _startSession(u, name: u.displayName);
      if (result.additionalUserInfo?.isNewUser ?? false) {
        _write(_userDoc.set({
          'name': currentUser!.name,
          'email': u.email ?? '',
          'created_at': nowMs(),
        }, SetOptions(merge: true)));
        _seedDefaults(false);
      }
      return null;
    } on fb.FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' || e.code == 'cancelled-popup-request') {
        return googleCancelled;
      }
      return _authError(e);
    } catch (e) {
      return 'Google sign-in failed: $e';
    }
  }

  /// Sends Firebase's password-reset email.
  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on fb.FirebaseAuthException catch (e) {
      return _authError(e);
    } catch (e) {
      return 'Something went wrong: $e';
    }
  }

  Future<String?> updateName(String name) async {
    final u = _auth.currentUser;
    final user = currentUser;
    if (u == null || user == null) return 'Not logged in';
    final clean = name.trim();
    try {
      await u.updateDisplayName(clean);
    } catch (_) {}
    user.name = clean;
    user.updatedAt = DateTime.now();
    TeamStore.instance.updateMyName(clean);
    _write(_userDoc.set({'name': clean}, SetOptions(merge: true)));
    notifyListeners();
    return null;
  }

  // ------------------------------------------------- profile & preferences

  void _savePrefs(Map<String, dynamic> data) {
    if (currentUser == null) {
      notifyListeners();
      return;
    }
    _write(_userDoc.set(data, SetOptions(merge: true)));
    notifyListeners();
  }

  void updateJobTitle(String title) {
    jobTitle = title.trim();
    _savePrefs({'title': jobTitle});
  }

  void setReminderMinutes(int minutes) {
    reminderMinutes = minutes;
    _savePrefs({'reminder_minutes': minutes});
    schedulePhoneReminders();
  }

  void setTeamAlerts(bool on) {
    teamAlerts = on;
    _savePrefs({'team_alerts': on});
  }

  /// Notification Center switches: 'assign' | 'due' | 'approvals' | 'comments'.
  bool notifOn(String which) => switch (which) {
        'assign' => notifAssign,
        'due' => reminderMinutes > 0,
        'approvals' => notifApprovals,
        'comments' => notifComments,
        _ => true,
      };

  void saveView(SavedView v) {
    savedViews = [...savedViews.where((x) => x.id != v.id), v];
    if (savedViews.length > 20) savedViews = savedViews.sublist(savedViews.length - 20);
    _savePrefs({'saved_views': savedViews.map((x) => x.toMap()).toList()});
  }

  void deleteView(SavedView v) {
    savedViews = savedViews.where((x) => x.id != v.id).toList();
    _savePrefs({'saved_views': savedViews.map((x) => x.toMap()).toList()});
  }

  void setWorkHours(int start, int end, [List<int>? days]) {
    workStart = start;
    workEnd = end;
    if (days != null && days.isNotEmpty) workDays = ([...days.toSet()]..sort());
    workHoursSet = true;
    _savePrefs({'work_start': start, 'work_end': end, 'work_days': workDays});
    _shareWorkHours();
  }

  /// My teams see my work week (Team Workload, assign warnings).
  void _shareWorkHours() => workHoursSet
      ? TeamStore.instance.setMyWork(
          weekMinutes: weekMinutes,
          dayMinutes: (workEnd - workStart).clamp(1, 24 * 60),
          workDays: workDays)
      : TeamStore.instance.setMyWork();

  void setNotif(String which, bool on) {
    switch (which) {
      case 'assign':
        notifAssign = on;
        _savePrefs({'notif_assign': on});
      case 'due':
        setReminderMinutes(on ? 15 : 0);
      case 'approvals':
        notifApprovals = on;
        _savePrefs({'notif_approvals': on});
      case 'comments':
        notifComments = on;
        _savePrefs({'notif_comments': on});
    }
  }

  void markBackupCopied() {
    lastBackupAt = DateTime.now();
    _savePrefs({'last_backup_at': nowMs()});
  }

  /// "google.com" / "password" for the logged-in account.
  List<String> get signInMethods {
    try {
      return _auth.currentUser?.providerData.map((p) => p.providerId).toList() ?? const [];
    } catch (_) {
      return const []; // Firebase not started (tests)
    }
  }

  bool get emailVerified {
    try {
      return _auth.currentUser?.emailVerified ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Asks Firebase again (e.g. after the user opened the verify link).
  Future<void> refreshAccount() async {
    try {
      await _auth.currentUser?.reload();
      notifyListeners();
    } catch (e) {
      debugPrint('Refresh account: $e');
    }
  }

  Future<String?> changePassword(String newPassword) async {
    final u = _auth.currentUser;
    if (u == null) return 'Not logged in';
    try {
      await u.updatePassword(newPassword);
      return null;
    } on fb.FirebaseAuthException catch (e) {
      return _authError(e);
    } catch (e) {
      return 'Something went wrong: $e';
    }
  }

  /// Firebase sends a link to the NEW email; the email changes after the
  /// user clicks it.
  Future<String?> changeEmail(String newEmail) async {
    final u = _auth.currentUser;
    if (u == null) return 'Not logged in';
    try {
      await u.verifyBeforeUpdateEmail(newEmail.trim());
      return null;
    } on fb.FirebaseAuthException catch (e) {
      return _authError(e);
    } catch (e) {
      return 'Something went wrong: $e';
    }
  }

  Future<void> logout() async {
    _endSession();
    notifyListeners();
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Sign out: $e');
    }
    // So next time the user can pick a different Google account.
    if (_googleReady) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
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

  List<TaskItem> tasksOnDay(DateTime day) => tasks.where((t) => isSameDay(t.startAt, day)).toList();

  List<TaskItem> get todayTasks => tasksOnDay(DateTime.now()).where((t) => !t.isCancelled).toList();

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

  int get unreadCount => visibleNotifications().where((n) => !n.isRead).length;

  // ------------------------------------------------------------------ tasks

  /// Creates or updates a personal task together with its checklist.
  /// (Personal tasks are not assigned to anyone; [previousAssigneeId] is
  /// unused and kept for the shared form.)
  Future<void> saveTask(TaskItem task, List<ChecklistItem> checklist,
      {required bool isNew, String? previousAssigneeId}) async {
    final me = currentUser?.id;
    if (me == null) return;
    final now = DateTime.now();
    task.updatedAt = now;
    for (var i = 0; i < checklist.length; i++) {
      checklist[i].sortOrder = i;
    }
    task.checklist = checklist;
    task.addHistory(isNew ? HistoryKind.created : HistoryKind.edited, me, at: now);
    _write(_col('tasks').doc(task.id).set(_taskToMap(task)));
  }

  void _saveTaskDoc(TaskItem task) {
    task.updatedAt = DateTime.now();
    _write(_col('tasks').doc(task.id).set(_taskToMap(task)));
  }

  Future<void> setCompleted(TaskItem task, bool done) async {
    if (currentUser == null) return;
    final now = DateTime.now();
    task.status = done ? TaskStatus.completed : TaskStatus.pending;
    task.completedAt = done ? now : null;
    task.addHistory(done ? HistoryKind.done : HistoryKind.reopened, currentUser!.id, at: now);
    if (done) _endTimer(task, now);
    _saveTaskDoc(task);
    if (done) {
      _notify('task', 'completed', 'Task completed', '"${task.title}" has been completed',
          taskId: task.id);
      _createNextRepeat(task);
    }
    notifyListeners();
  }

  /// Moves a personal task to a board column ([TaskStage] or "done").
  Future<void> moveTo(TaskItem task, String column) async {
    if (column == TaskStage.boardDone) {
      if (!task.isCompleted) await setCompleted(task, true);
      return;
    }
    if (task.stage == column && !task.isCompleted) return;
    task.stage = column;
    if (task.isCompleted) {
      task
        ..status = TaskStatus.pending
        ..completedAt = null;
    }
    task.addHistory(HistoryKind.stage, currentUser?.id, to: column);
    _saveTaskDoc(task);
    notifyListeners();
  }

  /// Replaces the checklist (subtasks).
  void setChecklist(TaskItem task, List<ChecklistItem> items) {
    if (currentUser == null) return;
    for (var i = 0; i < items.length; i++) {
      items[i].sortOrder = i;
    }
    task.checklist = items;
    _saveTaskDoc(task);
    notifyListeners();
  }

  void setLinks(TaskItem task, List<TaskLink> links) {
    if (currentUser == null) return;
    task.links = links;
    task.addHistory(HistoryKind.edited, currentUser!.id);
    _saveTaskDoc(task);
    notifyListeners();
  }

  void setCategory(TaskItem task, String? categoryId) {
    if (currentUser == null) return;
    task.categoryId = categoryId;
    _saveTaskDoc(task);
    notifyListeners();
  }

  // ------------------------------------------------------------ time

  /// Personal tasks with a running timer (always mine).
  List<TaskItem> get runningTimers => tasks.where((t) => t.timerRunning).toList();

  /// Starts the work timer; a task still in "To do" moves to "In progress".
  /// Use [TimeTracker.start] so my other running timers stop first.
  void startTimer(TaskItem task) {
    final me = currentUser?.id;
    if (me == null || task.timerRunning) return;
    final now = DateTime.now();
    task
      ..timerBy = me
      ..timerAt = now;
    if (task.status == TaskStatus.pending && task.stage == TaskStage.todo) {
      task.stage = TaskStage.doing;
      task.addHistory(HistoryKind.stage, me, to: TaskStage.doing, at: now);
    }
    _saveTaskDoc(task);
    notifyListeners();
  }

  /// Stops the timer and saves the session ([end] fixes a forgotten timer).
  void stopTimer(TaskItem task, {DateTime? end, String note = ''}) {
    if (currentUser == null || !task.timerRunning) return;
    _endTimer(task, end ?? DateTime.now(), note: note);
    _saveTaskDoc(task);
    notifyListeners();
  }

  /// Sessions under a minute are not saved.
  void _endTimer(TaskItem task, DateTime end, {String note = ''}) {
    final at = task.timerAt;
    final by = task.timerBy ?? currentUser?.id;
    if (at == null) return;
    if (by != null && end.difference(at) >= const Duration(minutes: 1)) {
      task.timeLog.add(TimeEntry(by: by, start: at, end: end, note: note.trim()));
    }
    task
      ..timerAt = null
      ..timerBy = null;
  }

  /// Replaces the time log (edit / delete / add an entry by hand).
  void setTimeLog(TaskItem task, List<TimeEntry> log) {
    if (currentUser == null) return;
    task.timeLog = [...log];
    _saveTaskDoc(task);
    notifyListeners();
  }

  /// Finishing a repeating task adds its next copy (once).
  void _createNextRepeat(TaskItem task) {
    if (!Repeat.isOn(task.repeat)) return;
    final id = repeatIdFor(task.id);
    if (taskById(id) != null) return;
    final next = task.nextRepeat(id, DateTime.now());
    tasks = [...tasks, next]..sort((a, b) => a.startAt.compareTo(b.startAt));
    _write(_col('tasks').doc(id).set(_taskToMap(next)));
  }

  // --------------------------------------------------------------- templates

  void saveTemplate(TaskTemplate t) {
    if (currentUser == null) return;
    templates = [...templates.where((x) => x.id != t.id), t];
    _write(_col('templates').doc(t.id).set(t.toMap()));
    notifyListeners();
  }

  void deleteTemplate(TaskTemplate t) {
    if (currentUser == null) return;
    templates = templates.where((x) => x.id != t.id).toList();
    _write(_col('templates').doc(t.id).delete());
    notifyListeners();
  }

  Future<void> cancelTask(TaskItem task) async {
    if (currentUser == null) return;
    final now = DateTime.now();
    task.status = TaskStatus.cancelled;
    task.addHistory(HistoryKind.cancelled, currentUser!.id, at: now);
    _endTimer(task, now);
    _saveTaskDoc(task);
    _notify('task', 'cancelled', 'Task cancelled', '"${task.title}" was cancelled',
        taskId: task.id);
    notifyListeners();
  }

  Future<void> restoreTask(TaskItem task) async {
    if (currentUser == null) return;
    task.status = TaskStatus.pending;
    task.addHistory(HistoryKind.restored, currentUser!.id);
    _saveTaskDoc(task);
    notifyListeners();
  }

  Future<void> deleteTask(TaskItem task) async {
    if (currentUser == null) return;
    _write(_col('tasks').doc(task.id).delete());
  }

  Future<void> toggleChecklistItem(ChecklistItem item) async {
    final task = taskById(item.taskId);
    if (task == null) return;
    item.isDone = !item.isDone;
    item.updatedAt = DateTime.now();
    _saveTaskDoc(task);
    notifyListeners();
  }

  // --------------------------------------------------------------- projects

  Future<Project> addProject(String name, int color) async {
    final now = DateTime.now();
    final p = Project(id: newId(), name: name.trim(), color: color, createdAt: now, updatedAt: now);
    if (currentUser != null) {
      projects = [...projects, p];
      _write(_col('projects').doc(p.id).set(p.toMap()));
      _notify('system', 'project', 'Project created', 'Project "${p.name}" was created');
      notifyListeners();
    }
    return p;
  }

  Future<void> updateProject(Project p) async {
    if (currentUser == null) return;
    p.updatedAt = DateTime.now();
    _write(_col('projects').doc(p.id).set(p.toMap()));
    _notify('system', 'project', 'Project updated', 'Project "${p.name}" was updated');
    notifyListeners();
  }

  /// Deletes the project; its tasks are kept but detached from it.
  Future<void> deleteProject(Project p) async {
    if (currentUser == null) return;
    final ops = <void Function(WriteBatch)>[
      (b) => b.delete(_col('projects').doc(p.id)),
    ];
    for (final t in tasks.where((t) => t.projectId == p.id)) {
      t.projectId = null;
      t.updatedAt = DateTime.now();
      final map = _taskToMap(t);
      ops.add((b) => b.set(_col('tasks').doc(t.id), map));
    }
    _runBatched(ops);
  }

  // ------------------------------------------------------------- categories

  Future<Category> addCategory(String name, int color) async {
    final now = DateTime.now();
    final c =
        Category(id: newId(), name: name.trim(), color: color, createdAt: now, updatedAt: now);
    if (currentUser != null) {
      categories = [...categories, c];
      _write(_col('categories').doc(c.id).set(c.toMap()));
      notifyListeners();
    }
    return c;
  }

  Future<void> updateCategory(Category c) async {
    if (currentUser == null) return;
    c.updatedAt = DateTime.now();
    _write(_col('categories').doc(c.id).set(c.toMap()));
    notifyListeners();
  }

  Future<void> deleteCategory(Category c) async {
    if (currentUser == null) return;
    final ops = <void Function(WriteBatch)>[
      (b) => b.delete(_col('categories').doc(c.id)),
    ];
    for (final t in tasks.where((t) => t.categoryId == c.id)) {
      t.categoryId = null;
      t.updatedAt = DateTime.now();
      final map = _taskToMap(t);
      ops.add((b) => b.set(_col('tasks').doc(t.id), map));
    }
    _runBatched(ops);
  }

  // ---------------------------------------------------------------- members

  Future<Member> addMember(String name) async {
    final now = DateTime.now();
    final m = Member(id: newId(), name: name.trim(), createdAt: now, updatedAt: now);
    if (currentUser != null) {
      members = [...members, m];
      _write(_col('members').doc(m.id).set(m.toMap()));
      notifyListeners();
    }
    return m;
  }

  Future<void> deleteMember(Member m) async {
    if (currentUser == null) return;
    final ops = <void Function(WriteBatch)>[
      (b) => b.delete(_col('members').doc(m.id)),
    ];
    for (final t in tasks.where((t) => t.assigneeId == m.id)) {
      t.assigneeId = null;
      t.updatedAt = DateTime.now();
      final map = _taskToMap(t);
      ops.add((b) => b.set(_col('tasks').doc(t.id), map));
    }
    _runBatched(ops);
  }

  // ---------------------------------------------------------- notifications

  /// Adds an entry to the Notification Center, unless its kind is switched
  /// off ([notifOn]). Returns whether it was added.
  bool addNotification(String type, String kind, String title, String body,
      {String? taskId, String? teamId, String? actorName}) {
    final allowed = switch (kind) {
      NotifKind.assigned => notifAssign,
      NotifKind.approval || NotifKind.approved || NotifKind.changes => notifApprovals,
      NotifKind.mention || NotifKind.comment => notifComments,
      NotifKind.reminder => reminderMinutes > 0,
      _ => true,
    };
    if (!allowed) return false;
    _notify(type, kind, title, body, taskId: taskId, teamId: teamId, actorName: actorName);
    return true;
  }

  void _notify(String type, String kind, String title, String body,
      {String? taskId, String? teamId, String? actorName}) {
    if (currentUser == null) return;
    final n = AppNotification(
      id: newId(),
      type: type,
      kind: kind,
      title: title.length > 300 ? '${title.substring(0, 297)}...' : title,
      body: body.length > 2000 ? body.substring(0, 2000) : body,
      taskId: taskId,
      teamId: teamId,
      actorName: actorName,
      createdAt: DateTime.now(),
    );
    notifications.insert(0, n);
    _write(_col('notifications').doc(n.id).set(n.toMap()));
  }

  /// Notifications to show now (snoozed reminders wait), newest first.
  List<AppNotification> visibleNotifications([DateTime? at]) {
    final now = at ?? DateTime.now();
    return notifications.where((n) => !n.snoozedAt(now)).toList()
      ..sort((a, b) => b.shownAt.compareTo(a.shownAt));
  }

  void setRead(AppNotification n, bool read) {
    if (currentUser == null) return;
    n.readAt = read ? DateTime.now() : null;
    notifyListeners();
    _write(_col('notifications')
        .doc(n.id)
        .set({'read_at': read ? nowMs() : null}, SetOptions(merge: true)));
  }

  void deleteNotification(AppNotification n) {
    if (currentUser == null) return;
    notifications.removeWhere((x) => x.id == n.id);
    notifyListeners();
    _write(_col('notifications').doc(n.id).delete());
  }

  /// Hides a reminder for [d]; it then comes back as unread.
  void snooze(AppNotification n, Duration d) {
    if (currentUser == null) return;
    n
      ..snoozeUntil = DateTime.now().add(d)
      ..readAt = null;
    notifyListeners();
    _write(_col('notifications').doc(n.id).set(
        {'snooze_until': n.snoozeUntil!.millisecondsSinceEpoch, 'read_at': null},
        SetOptions(merge: true)));
  }

  Future<void> markAllRead() async {
    if (currentUser == null || unreadCount == 0) return;
    final now = nowMs();
    final ops = <void Function(WriteBatch)>[];
    for (final n in visibleNotifications().where((n) => !n.isRead)) {
      n.readAt = DateTime.fromMillisecondsSinceEpoch(now);
      ops.add((b) => b.set(_col('notifications').doc(n.id), <String, dynamic>{'read_at': now},
          SetOptions(merge: true)));
    }
    notifyListeners();
    _runBatched(ops);
  }

  Future<void> clearNotifications() async {
    if (currentUser == null) return;
    final ops = <void Function(WriteBatch)>[];
    for (final n in notifications) {
      ops.add((b) => b.delete(_col('notifications').doc(n.id)));
    }
    _runBatched(ops);
  }

  /// In-app reminders: while the app is open, every minute we check for tasks
  /// starting within [reminderMinutes] and add a reminder (once per task).
  void _startReminderTimer() {
    _reminderTimer?.cancel();
    _reminderTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkReminders());
  }

  void _checkReminders() {
    if (currentUser == null) return;
    if (reminderMinutes <= 0) return;
    final now = DateTime.now();
    final soon = now.add(Duration(minutes: reminderMinutes));
    for (final r in TaskRepository.myTasks()) {
      final t = r.task;
      if (t.status != TaskStatus.pending || t.isAllDay) continue;
      if (t.startAt.isBefore(now) || t.startAt.isAfter(soon)) continue;
      final already = notifications.any((n) => n.kind == NotifKind.reminder && n.taskId == t.id);
      if (already) continue;
      final mins = t.startAt.difference(now).inMinutes;
      _notify(
          'task',
          NotifKind.reminder,
          'Reminder: ${t.title} starts in ${mins <= 1 ? '1 minute' : '$mins minutes'}',
          r.sourceLabel,
          taskId: t.id,
          teamId: r.team?.id);
    }
  }

  // ------------------------------------------------------- backup / restore

  /// All of this user's data as JSON text.
  Future<String> exportBackup() async {
    return jsonEncode({
      'app': 'taskflow',
      'version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      'categories': categories.map((c) => c.toMap()).toList(),
      'projects': projects.map((p) => p.toMap()).toList(),
      'members': members.map((m) => m.toMap()).toList(),
      'tasks': tasks.map(_taskToMap).toList(),
      'notifications': notifications.map((n) => n.toMap()).toList(),
    });
  }

  /// Adds the backup's data to this account (same ids are overwritten).
  /// Accepts backups from the old offline version too.
  Future<String?> importBackup(String json) async {
    if (currentUser == null) return 'Please log in first.';
    Map<String, dynamic> data;
    try {
      data = jsonDecode(json.trim()) as Map<String, dynamic>;
    } catch (_) {
      return 'This is not a valid TaskFlow backup.';
    }
    if (data['app'] != 'taskflow') return 'This is not a valid TaskFlow backup.';

    List<_Json> rows(String key) {
      final list = data[key];
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .where((r) => r['deleted_at'] == null)
          .toList();
    }

    // Old offline backups kept checklist items in their own table.
    final oldChecklist = <String, List<_Json>>{};
    for (final c in rows('checklist_items')) {
      final tid = c['task_id'];
      if (tid is String) oldChecklist.putIfAbsent(tid, () => []).add(c);
    }

    final ops = <void Function(WriteBatch)>[];
    void addAll(String collection, List<_Json> items) {
      for (final r in items) {
        final id = r['id'];
        if (id is! String) continue;
        ops.add((b) => b.set(_col(collection).doc(id), r));
      }
    }

    addAll('categories', rows('categories'));
    addAll('projects', rows('projects'));
    addAll('members', rows('members'));
    addAll('notifications', rows('notifications'));
    final taskRows = <_Json>[];
    var skipped = 0;
    for (final t in rows('tasks')) {
      final id = t['id'];
      if (id is String && t['checklist'] == null) {
        t['checklist'] = oldChecklist[id] ?? <_Json>[];
      }
      final fixed = fixTaskRow(t);
      if (fixed == null) {
        skipped++;
      } else {
        taskRows.add(fixed);
      }
    }
    addAll('tasks', taskRows);

    if (ops.isEmpty) return 'The backup is empty.';
    _runBatched(ops);
    return skipped == 0
        ? null
        : 'Added ${taskRows.length} tasks. $skipped could not be read and were skipped.';
  }

  /// Fills in what a task from a hand-made or older backup may lack (no
  /// date: an all-day task today), so one bad row can't make the whole
  /// import fail. Null when it can't be used.
  static _Json? fixTaskRow(_Json t) {
    if (t['id'] is! String || (t['title'] is! String) || (t['title'] as String).trim().isEmpty) {
      return null;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (t['created_at'] is! int) t['created_at'] = now;
    if (t['updated_at'] is! int) t['updated_at'] = t['created_at'];
    if (t['priority'] is! int) t['priority'] = 2;
    if (!const ['pending', 'completed', 'cancelled'].contains(t['status'])) t['status'] = 'pending';
    if (t['start_at'] is! int) {
      final n = DateTime.now();
      t['start_at'] = DateTime(n.year, n.month, n.day).millisecondsSinceEpoch;
      t['end_at'] = DateTime(n.year, n.month, n.day, 23, 59).millisecondsSinceEpoch;
    }
    if (t['end_at'] != null && t['end_at'] is! int) t['end_at'] = null;
    try {
      taskFromMap(t);
    } catch (_) {
      return null;
    }
    return t;
  }

  /// Deletes all tasks, projects, categories, members and notifications of
  /// this account (the account itself stays).
  Future<void> resetAllData() async {
    if (currentUser == null) return;
    final ops = <void Function(WriteBatch)>[];
    for (final c in categories) {
      ops.add((b) => b.delete(_col('categories').doc(c.id)));
    }
    for (final p in projects) {
      ops.add((b) => b.delete(_col('projects').doc(p.id)));
    }
    for (final m in members) {
      ops.add((b) => b.delete(_col('members').doc(m.id)));
    }
    for (final t in tasks) {
      ops.add((b) => b.delete(_col('tasks').doc(t.id)));
    }
    for (final n in notifications) {
      ops.add((b) => b.delete(_col('notifications').doc(n.id)));
    }
    for (final t in templates) {
      ops.add((b) => b.delete(_col('templates').doc(t.id)));
    }
    _runBatched(ops);
    final inbox = InboxStore.instance;
    inbox.delete([...inbox.items, ...inbox.recentlyOrganized].map((i) => i.id));
  }

  // ------------------------------------------------------------ seed data

  void _seedDefaults(bool withSample) {
    final now = DateTime.now();
    final ops = <void Function(WriteBatch)>[];

    void put(String collection, String id, _Json map) {
      ops.add((b) => b.set(_col(collection).doc(id), map));
    }

    void cat(String id, String name, int color) => put('categories', id,
        Category(id: id, name: name, color: color, createdAt: now, updatedAt: now).toMap());

    final work = newId(), design = newId(), general = newId(), research = newId();
    cat(work, 'Work', 0xFF1F6FEB);
    cat(design, 'Design', 0xFF7C3AED);
    cat(general, 'General', 0xFF6B7280);
    cat(research, 'Research', 0xFFF97316);

    final welcome = AppNotification(
      id: newId(),
      type: 'system',
      kind: 'info',
      title: 'Welcome to TaskFlow',
      body: 'Your tasks are saved to your account and work offline too.',
      createdAt: now,
    );
    put('notifications', welcome.id, welcome.toMap());

    if (withSample) {
      final today = dateOnly(now);
      DateTime at(int dayOffset, int h) => today.add(Duration(days: dayOffset, hours: h));

      void proj(String id, String name, int color) => put('projects', id,
          Project(id: id, name: name, color: color, createdAt: now, updatedAt: now).toMap());

      final pApp = newId(), pDesign = newId(), pMkt = newId();
      proj(pApp, 'App Development', 0xFF16A34A);
      proj(pDesign, 'UI/UX Design', 0xFFF97316);
      proj(pMkt, 'Marketing', 0xFF7C3AED);

      final ali = newId();
      put('members', ali,
          Member(id: ali, name: 'Ali Raza', createdAt: now, updatedAt: now).toMap());

      void task(String title, String category, int day, int h, int endH,
          {String? project,
          String? assignee,
          Priority pr = Priority.medium,
          bool done = false,
          String desc = '',
          List<List<Object>> checklist = const []}) {
        final id = newId();
        final t = TaskItem(
          id: id,
          title: title,
          description: desc,
          categoryId: category,
          projectId: project,
          assigneeId: assignee,
          priority: pr,
          status: done ? TaskStatus.completed : TaskStatus.pending,
          startAt: at(day, h),
          endAt: at(day, endH),
          completedAt: done ? now : null,
          createdAt: now,
          updatedAt: now,
        );
        for (var i = 0; i < checklist.length; i++) {
          t.checklist.add(ChecklistItem(
            id: newId(),
            taskId: id,
            title: checklist[i][0] as String,
            isDone: checklist[i][1] as bool,
            sortOrder: i,
            createdAt: now,
            updatedAt: now,
          ));
        }
        put('tasks', id, _taskToMap(t));
      }

      task('Prepare weekly report', work, 0, 9, 10, done: true, project: pMkt);
      task('Team meeting', work, 0, 11, 12, project: pApp);
      task('Design app UI', design, 0, 13, 15,
          project: pDesign,
          assignee: ali,
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
    _runBatched(ops);
  }
}
