import 'dart:async';
import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentReference, FieldValue, FirebaseFirestore, WriteBatch;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_store.dart';
import 'models.dart';
import 'reminders.dart';
import 'team_models.dart';

typedef _Json = Map<String, dynamic>;

/// Teams, their tasks and invitations for the logged-in user.
///
/// Like [AppStore], writes are not awaited (they work offline and sync later)
/// and screens update through live listeners. Who may do what is enforced by
/// the Firestore rules; the checks here only keep the buttons honest.
class TeamStore extends ChangeNotifier {
  TeamStore._();
  static final TeamStore instance = TeamStore._();

  String? _uid;
  String _email = '';
  String _name = '';

  List<Team> teams = [];

  /// Invitations sent to me.
  List<TeamInvite> invites = [];

  /// Open invitations per team (only for teams I manage).
  final Map<String, List<TeamInvite>> sentInvites = {};
  final Map<String, List<TaskItem>> _tasks = {};

  StreamSubscription<dynamic>? _teamsSub;
  StreamSubscription<dynamic>? _invitesSub;
  final Map<String, StreamSubscription<dynamic>> _taskSubs = {};
  final Map<String, StreamSubscription<dynamic>> _sentInviteSubs = {};
  final Map<String, StreamSubscription<dynamic>> _commentSubs = {};

  /// Members per team at the last update, to notice who joined.
  final Map<String, Set<String>> _knownMembers = {};
  bool _teamsLoaded = false;

  /// Only things newer than this (saved per user) produce a notification, so
  /// opening the app does not repeat old ones.
  int _seenUntil = 0;

  FirebaseFirestore get _fs => FirebaseFirestore.instance;
  CollectionReference<_Json> get _teamsCol => _fs.collection('teams');
  CollectionReference<_Json> get _invitesCol => _fs.collection('invites');
  CollectionReference<_Json> _tasksCol(String teamId) => _teamsCol.doc(teamId).collection('tasks');
  CollectionReference<_Json> _commentsCol(String teamId) =>
      _teamsCol.doc(teamId).collection('comments');
  DocumentReference<_Json> _teamDoc(String teamId) => _teamsCol.doc(teamId);

  String? get uid => _uid;

  /// Tests only: pretend to be logged in as [uid] with these team tasks.
  @visibleForTesting
  void setForTest({String? uid, Map<String, List<TaskItem>> tasks = const {}}) {
    _uid = uid;
    _tasks
      ..clear()
      ..addAll(tasks);
  }

  // ------------------------------------------------------------- session

  Future<void> start({required String uid, required String email, required String name}) async {
    stop();
    _uid = uid;
    _email = normalizeEmail(email);
    _name = name;

    final prefs = await SharedPreferences.getInstance();
    final key = 'team_seen_until_$uid';
    _seenUntil = prefs.getInt(key) ?? DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(key, _seenUntil);
    if (_uid != uid) return; // logged out meanwhile

    _teamsSub = _teamsCol
        .where('member_ids', arrayContains: uid)
        .snapshots()
        .listen((s) => _onTeams(s.docs.map((d) => d.data())), onError: _onError);

    if (_email.isNotEmpty) {
      _invitesSub = _invitesCol
          .where('email', isEqualTo: _email)
          .snapshots()
          .listen((s) => _onInvites(s.docs.map((d) => d.data())), onError: _onError);
    }
  }

  void stop() {
    _teamsSub?.cancel();
    _invitesSub?.cancel();
    for (final s in _taskSubs.values) {
      s.cancel();
    }
    for (final s in _sentInviteSubs.values) {
      s.cancel();
    }
    for (final s in _commentSubs.values) {
      s.cancel();
    }
    _commentSubs.clear();
    _teamsSub = null;
    _invitesSub = null;
    _taskSubs.clear();
    _sentInviteSubs.clear();
    _uid = null;
    teams = [];
    invites = [];
    sentInvites.clear();
    _tasks.clear();
    _knownMembers.clear();
    _teamsLoaded = false;
    notifyListeners();
  }

  /// Keeps my name in my teams up to date (shown to the other members).
  void updateMyName(String name) {
    _name = name;
    final me = _uid;
    if (me == null) return;
    for (final t in teams) {
      if (t.members[me]?.name != name) {
        _write(_teamDoc(t.id).update({
          'members.$me': TeamMemberInfo(name: name, email: _email).toMap(),
          'updated_at': nowMs(),
        }));
      }
    }
  }

  // ----------------------------------------------------------- listeners

  void _onTeams(Iterable<_Json> docs) {
    final me = _uid;
    if (me == null) return;
    final list = <Team>[];
    for (final m in docs) {
      try {
        list.add(Team.fromMap(m));
      } catch (e) {
        debugPrint('Skipped bad team: $e');
      }
    }
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Who joined my teams since last time?
    if (_teamsLoaded) {
      for (final t in list) {
        final before = _knownMembers[t.id];
        if (before == null || !t.isAdmin(me)) continue;
        for (final uid in t.memberIds) {
          if (!before.contains(uid) && uid != me) {
            _notify('${t.nameOf(uid)} joined ${t.name}',
                '${t.nameOf(uid)} accepted your invitation to the team.');
          }
        }
      }
    }
    _knownMembers
      ..clear()
      ..addEntries(list.map((t) => MapEntry(t.id, t.memberIds.toSet())));
    _teamsLoaded = true;
    teams = list;

    // Listen to the tasks of every team I am in (and open invites if I manage it).
    final ids = list.map((t) => t.id).toSet();
    for (final id in _taskSubs.keys.toList()) {
      if (!ids.contains(id)) {
        _taskSubs.remove(id)?.cancel();
        _commentSubs.remove(id)?.cancel();
        _tasks.remove(id);
      }
    }
    for (final id in ids) {
      _taskSubs[id] ??= _tasksCol(id)
          .snapshots()
          .listen((s) => _onTasks(id, s.docs.map((d) => d.data())), onError: _onError);
      // Only new comments matter here (for notifications); a task's full
      // comment list is loaded by its screen.
      _commentSubs[id] ??= _commentsCol(id)
          .where('created_at', isGreaterThan: _seenUntil)
          .snapshots()
          .listen((s) => _onNewComments(id, s.docs.map((d) => d.data())), onError: _onError);
    }
    for (final t in list) {
      final admin = t.isAdmin(me);
      if (admin && !_sentInviteSubs.containsKey(t.id)) {
        _sentInviteSubs[t.id] =
            _invitesCol.where('team_id', isEqualTo: t.id).snapshots().listen((s) {
          sentInvites[t.id] = _parseInvites(s.docs.map((d) => d.data()));
          notifyListeners();
        }, onError: _onError);
      } else if (!admin && _sentInviteSubs.containsKey(t.id)) {
        _sentInviteSubs.remove(t.id)?.cancel();
        sentInvites.remove(t.id);
      }
    }
    for (final id in _sentInviteSubs.keys.toList()) {
      if (!ids.contains(id)) {
        _sentInviteSubs.remove(id)?.cancel();
        sentInvites.remove(id);
      }
    }

    // Keep my name in the teams current.
    for (final t in list) {
      final info = t.members[me];
      if (info != null && _name.isNotEmpty && info.name != _name) {
        updateMyName(_name);
        break;
      }
    }
    AppStore.instance.schedulePhoneReminders();
    notifyListeners();
  }

  void _onTasks(String teamId, Iterable<_Json> docs) {
    final me = _uid;
    if (me == null) return;
    final list = <TaskItem>[];
    for (final m in docs) {
      try {
        list.add(AppStore.taskFromMap(m));
      } catch (e) {
        debugPrint('Skipped bad team task: $e');
      }
    }
    list.sort((a, b) => a.startAt.compareTo(b.startAt));
    _tasks[teamId] = list;

    // New tasks assigned to me by someone else.
    final team = teamById(teamId);
    var newest = _seenUntil;
    for (final t in list) {
      final at = t.assignedAt?.millisecondsSinceEpoch ?? 0;
      if (t.assigneeId == me && t.assignedBy != me && at > _seenUntil) {
        final by = team?.nameOf(t.assignedBy) ?? 'Your manager';
        _notify('New task: ${t.title}', '$by assigned you a task in ${team?.name ?? 'your team'}.');
        if (at > newest) newest = at;
      }
    }
    _markSeen(newest);
    AppStore.instance.schedulePhoneReminders();
    notifyListeners();
  }

  /// Someone else commented on a task that is mine (assigned to me, or one
  /// I created / assigned).
  void _onNewComments(String teamId, Iterable<_Json> docs) {
    final me = _uid;
    final team = teamById(teamId);
    if (me == null || team == null) return;
    var newest = _seenUntil;
    for (final m in docs) {
      final TaskComment c;
      try {
        c = TaskComment.fromMap(m);
      } catch (_) {
        continue;
      }
      final at = c.createdAt.millisecondsSinceEpoch;
      if (c.authorId == me || at <= _seenUntil) continue;
      final task = taskById(teamId, c.taskId);
      if (task == null) continue;
      final mine = task.assigneeId == me || task.assignedBy == me || task.createdBy == me;
      if (!mine) continue;
      final who = c.authorName.isEmpty ? team.nameOf(c.authorId) : c.authorName;
      _notify('$who on "${task.title}"', c.text);
      if (at > newest) newest = at;
    }
    _markSeen(newest);
  }

  void _onInvites(Iterable<_Json> docs) {
    invites = _parseInvites(docs);
    var newest = _seenUntil;
    for (final i in invites) {
      final at = i.createdAt.millisecondsSinceEpoch;
      if (at > _seenUntil) {
        _notify('Team invitation',
            '${i.invitedByName.isEmpty ? 'Someone' : i.invitedByName} invited you to join "${i.teamName}". Open Teams to accept.');
        if (at > newest) newest = at;
      }
    }
    _markSeen(newest);
    notifyListeners();
  }

  List<TeamInvite> _parseInvites(Iterable<_Json> docs) {
    final out = <TeamInvite>[];
    for (final m in docs) {
      try {
        out.add(TeamInvite.fromMap(m));
      } catch (e) {
        debugPrint('Skipped bad invite: $e');
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  void _markSeen(int until) {
    if (until <= _seenUntil || _uid == null) return;
    _seenUntil = until;
    final key = 'team_seen_until_$_uid';
    SharedPreferences.getInstance().then((p) => p.setInt(key, until));
  }

  /// In-app notification + a phone notification right away.
  void _notify(String title, String body) {
    AppStore.instance.addNotification('task', 'team', title, body);
    PhoneReminders.instance.showNow(title, body);
  }

  void _onError(Object e) => debugPrint('Team stream error: $e');

  void _write(Future<void> f) {
    f.then((_) {}, onError: (Object e) => debugPrint('Team write failed: $e'));
  }

  void _runBatched(List<void Function(WriteBatch b)> ops) {
    for (var i = 0; i < ops.length; i += 400) {
      final batch = _fs.batch();
      for (final op in ops.sublist(i, min(i + 400, ops.length))) {
        op(batch);
      }
      _write(batch.commit());
    }
  }

  // ------------------------------------------------------------- lookups

  Team? teamById(String id) {
    for (final t in teams) {
      if (t.id == id) return t;
    }
    return null;
  }

  List<TaskItem> tasksOf(String teamId) => _tasks[teamId] ?? const [];

  TaskItem? taskById(String teamId, String taskId) {
    for (final t in tasksOf(teamId)) {
      if (t.id == taskId) return t;
    }
    return null;
  }

  bool isAdmin(Team team) => _uid != null && team.isAdmin(_uid!);

  /// The assignee can mark done; owner/managers can too.
  bool canComplete(Team team, TaskItem task) =>
      _uid != null && (team.isAdmin(_uid!) || task.assigneeId == _uid);

  /// Pending (not cancelled) team tasks assigned to me, in all teams.
  List<TaskItem> get myTeamTasks => [
        for (final list in _tasks.values)
          for (final t in list)
            if (t.assigneeId == _uid && !t.isCancelled) t,
      ];

  /// My (not cancelled) team tasks together with their team, for My Day.
  List<(Team, TaskItem)> get myTeamTasksWithTeam => [
        for (final team in teams)
          for (final t in tasksOf(team.id))
            if (t.assigneeId == _uid && !t.isCancelled) (team, t),
      ];

  int pendingForMe(String teamId) =>
      tasksOf(teamId).where((t) => t.assigneeId == _uid && t.status == TaskStatus.pending).length;

  // --------------------------------------------------------------- teams

  Future<Team?> createTeam(String name, int color) async {
    final me = _uid;
    if (me == null) return null;
    final now = DateTime.now();
    final t = Team(
      id: newId(),
      name: name.trim(),
      color: color,
      ownerId: me,
      memberIds: [me],
      managerIds: [],
      members: {me: TeamMemberInfo(name: _name, email: _email)},
      createdAt: now,
      updatedAt: now,
    );
    teams = [...teams, t];
    _write(_teamDoc(t.id).set(t.toMap()));
    notifyListeners();
    return t;
  }

  void renameTeam(Team team, String name, int color) {
    team
      ..name = name.trim()
      ..color = color;
    _write(_teamDoc(team.id).update({'name': team.name, 'color': color, 'updated_at': nowMs()}));
    notifyListeners();
  }

  /// Owner only: deletes the team, its tasks, comments and open invitations.
  Future<void> deleteTeam(Team team) async {
    var commentIds = <String>[];
    try {
      final snap = await _commentsCol(team.id).get().timeout(const Duration(seconds: 10));
      commentIds = snap.docs.map((d) => d.id).toList();
    } catch (e) {
      debugPrint('Could not load comments to delete: $e');
    }
    final ops = <void Function(WriteBatch)>[
      for (final id in commentIds) (b) => b.delete(_commentsCol(team.id).doc(id)),
      for (final t in tasksOf(team.id)) (b) => b.delete(_tasksCol(team.id).doc(t.id)),
      for (final i in sentInvites[team.id] ?? const <TeamInvite>[])
        (b) => b.delete(_invitesCol.doc(i.id)),
      (b) => b.delete(_teamDoc(team.id)),
    ];
    teams = teams.where((t) => t.id != team.id).toList();
    _runBatched(ops);
    notifyListeners();
  }

  void setManager(Team team, String uid, bool manager) {
    final ids = {...team.managerIds};
    manager ? ids.add(uid) : ids.remove(uid);
    team.managerIds = ids.toList();
    _write(_teamDoc(team.id).update({'manager_ids': team.managerIds, 'updated_at': nowMs()}));
    notifyListeners();
  }

  /// Owner/manager removes someone; their open tasks become unassigned.
  void removeMember(Team team, String uid) {
    final ops = <void Function(WriteBatch)>[
      (b) => b.update(_teamDoc(team.id), {
            'member_ids': FieldValue.arrayRemove([uid]),
            if (team.managerIds.contains(uid)) 'manager_ids': FieldValue.arrayRemove([uid]),
            'members.$uid': FieldValue.delete(),
            'updated_at': nowMs(),
          }),
      for (final t in tasksOf(team.id))
        if (t.assigneeId == uid && t.status == TaskStatus.pending)
          (b) => b.update(_tasksCol(team.id).doc(t.id), {
                'assignee_id': null,
                'updated_at': nowMs(),
              }),
    ];
    _runBatched(ops);
  }

  void leaveTeam(Team team) {
    final me = _uid;
    if (me == null || me == team.ownerId) return;
    _write(_teamDoc(team.id).update({
      'member_ids': FieldValue.arrayRemove([me]),
      'manager_ids': FieldValue.arrayRemove([me]),
      'members.$me': FieldValue.delete(),
      'updated_at': nowMs(),
    }));
    teams = teams.where((t) => t.id != team.id).toList();
    notifyListeners();
  }

  // ------------------------------------------------------------- invites

  /// Returns an error message, or null when the invitation was sent.
  String? inviteByEmail(Team team, String email) {
    final me = _uid;
    if (me == null) return 'Please log in first.';
    final e = normalizeEmail(email);
    if (!looksLikeEmail(e)) return 'Please enter a valid email address.';
    if (e == _email) return 'That is your own email.';
    if (team.members.values.any((m) => normalizeEmail(m.email) == e)) {
      return 'This person is already in the team.';
    }
    if ((sentInvites[team.id] ?? const []).any((i) => i.email == e)) {
      return 'This email is already invited.';
    }
    final invite = TeamInvite(
      id: inviteIdFor(team.id, e),
      teamId: team.id,
      teamName: team.name,
      email: e,
      invitedBy: me,
      invitedByName: _name,
      createdAt: DateTime.now(),
    );
    sentInvites[team.id] = [invite, ...?sentInvites[team.id]];
    _write(_invitesCol.doc(invite.id).set(invite.toMap()));
    notifyListeners();
    return null;
  }

  void cancelInvite(TeamInvite invite) {
    sentInvites[invite.teamId]?.removeWhere((i) => i.id == invite.id);
    _write(_invitesCol.doc(invite.id).delete());
    notifyListeners();
  }

  void declineInvite(TeamInvite invite) {
    invites = invites.where((i) => i.id != invite.id).toList();
    _write(_invitesCol.doc(invite.id).delete());
    notifyListeners();
  }

  /// Sentinel returned by [acceptInvite] when the email must be verified first.
  static const needsVerification = '__verify__';

  /// Joins the team. The email must be verified (Google accounts always are),
  /// otherwise anyone could sign up with someone else's address.
  /// Needs internet. Returns null on success or an error message.
  Future<String?> acceptInvite(TeamInvite invite) async {
    final me = _uid;
    final user = fb.FirebaseAuth.instance.currentUser;
    if (me == null || user == null) return 'Please log in first.';
    try {
      await user.reload();
      final fresh = fb.FirebaseAuth.instance.currentUser;
      if (fresh == null) return 'Please log in again.';
      if (!fresh.emailVerified) return needsVerification;
      await fresh.getIdToken(true); // so the server sees "verified"

      final batch = _fs.batch();
      batch.update(_teamDoc(invite.teamId), {
        'member_ids': FieldValue.arrayUnion([me]),
        'members.$me': TeamMemberInfo(name: _name, email: _email).toMap(),
        'updated_at': nowMs(),
      });
      batch.delete(_invitesCol.doc(invite.id));
      await batch.commit().timeout(const Duration(seconds: 20));
      invites = invites.where((i) => i.id != invite.id).toList();
      notifyListeners();
      return null;
    } on TimeoutException {
      return 'No internet connection. Please connect and try again.';
    } on fb.FirebaseAuthException catch (e) {
      return e.code == 'network-request-failed'
          ? 'No internet connection. Please connect and try again.'
          : 'Could not join: ${e.message ?? e.code}';
    } catch (e) {
      debugPrint('Accept invite: $e');
      final text = '$e';
      if (text.contains('permission-denied') || text.contains('not-found')) {
        return 'This invitation is no longer valid (the team may have been deleted).';
      }
      return 'Could not join the team. Please try again.';
    }
  }

  /// Sends the "verify your email" link to the logged-in user.
  Future<String?> sendVerificationEmail() async {
    try {
      await fb.FirebaseAuth.instance.currentUser?.sendEmailVerification();
      return null;
    } on fb.FirebaseAuthException catch (e) {
      return e.code == 'too-many-requests'
          ? 'A link was sent recently. Please check your email (also spam).'
          : (e.message ?? 'Could not send the email.');
    } catch (e) {
      return 'Could not send the email.';
    }
  }

  // --------------------------------------------------------------- tasks

  /// Owner/manager: create or edit a team task.
  void saveTask(Team team, TaskItem task, List<ChecklistItem> checklist,
      {required bool isNew, String? previousAssigneeId}) {
    final me = _uid;
    if (me == null) return;
    final now = DateTime.now();
    for (var i = 0; i < checklist.length; i++) {
      checklist[i].sortOrder = i;
    }
    task
      ..checklist = checklist
      ..updatedAt = now;
    if (isNew) task.createdBy = me;
    if (task.assigneeId != previousAssigneeId || isNew) {
      task
        ..assignedBy = task.assigneeId == null ? null : me
        ..assignedAt = task.assigneeId == null ? null : now;
    }
    _upsertLocal(team.id, task);
    _write(_tasksCol(team.id).doc(task.id).set(AppStore.taskToMap(task)));
  }

  /// Assignee or owner/manager. Only status fields are written, which is all
  /// a member is allowed to change. Finishing a repeating task also creates
  /// its next copy (in the same write).
  void setCompleted(Team team, TaskItem task, bool done) {
    final me = _uid;
    if (me == null) return;
    task
      ..status = done ? TaskStatus.completed : TaskStatus.pending
      ..completedAt = done ? DateTime.now() : null
      ..updatedAt = DateTime.now();
    final batch = _fs.batch();
    batch.update(_tasksCol(team.id).doc(task.id), {
      'status': task.status,
      'completed_at': task.completedAt?.millisecondsSinceEpoch,
      'updated_at': nowMs(),
    });
    if (done && Repeat.isOn(task.repeat)) {
      final id = repeatIdFor(task.id);
      if (taskById(team.id, id) == null) {
        final next = task.nextRepeat(id, DateTime.now());
        // An owner/manager finishing someone else's task creates the copy
        // as themselves (that is what the rules allow).
        if (task.assigneeId != me) next.createdBy = me;
        _upsertLocal(team.id, next);
        batch.set(_tasksCol(team.id).doc(id), AppStore.taskToMap(next));
      }
    }
    notifyListeners();
    _write(batch.commit());
  }

  /// Moves a task to a board column: a [TaskStage] or "done".
  void moveTo(Team team, TaskItem task, String column) {
    if (column == boardDone) {
      if (!task.isCompleted) setCompleted(team, task, true);
      return;
    }
    final reopen = task.isCompleted;
    task
      ..stage = column
      ..updatedAt = DateTime.now();
    if (reopen) {
      task
        ..status = TaskStatus.pending
        ..completedAt = null;
    }
    notifyListeners();
    _write(_tasksCol(team.id).doc(task.id).update({
      'stage': column,
      if (reopen) 'status': TaskStatus.pending,
      if (reopen) 'completed_at': null,
      'updated_at': nowMs(),
    }));
  }

  /// Board column id for finished tasks.
  static const boardDone = 'done';

  void toggleChecklistItem(Team team, TaskItem task, ChecklistItem item) {
    item
      ..isDone = !item.isDone
      ..updatedAt = DateTime.now();
    notifyListeners();
    _write(_tasksCol(team.id).doc(task.id).update({
      'checklist': task.checklist.map((c) => c.toMap()).toList(),
      'updated_at': nowMs(),
    }));
  }

  void cancelTask(Team team, TaskItem task, {bool restore = false}) {
    task.status = restore ? TaskStatus.pending : TaskStatus.cancelled;
    notifyListeners();
    _write(_tasksCol(team.id).doc(task.id).update({'status': task.status, 'updated_at': nowMs()}));
  }

  void deleteTask(Team team, TaskItem task) {
    _tasks[team.id]?.removeWhere((t) => t.id == task.id);
    notifyListeners();
    _write(_tasksCol(team.id).doc(task.id).delete());
    // Its comments too (best effort; needs internet to find them).
    _commentsCol(team.id).where('task_id', isEqualTo: task.id).get().then((snap) {
      _runBatched([for (final d in snap.docs) (b) => b.delete(d.reference)]);
    }, onError: (Object e) => debugPrint('Delete comments: $e'));
  }

  // ------------------------------------------------------------ comments

  /// Live comments of one task, oldest first.
  Stream<List<TaskComment>> commentsOf(String teamId, String taskId) =>
      _commentsCol(teamId).where('task_id', isEqualTo: taskId).snapshots().map((s) {
        final list = <TaskComment>[];
        for (final d in s.docs) {
          try {
            list.add(TaskComment.fromMap(d.data()));
          } catch (_) {}
        }
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return list;
      });

  void addComment(Team team, TaskItem task, String text) {
    final me = _uid;
    final clean = text.trim();
    if (me == null || clean.isEmpty) return;
    final c = TaskComment(
      id: newId(),
      taskId: task.id,
      authorId: me,
      authorName: _name,
      text: clean,
      createdAt: DateTime.now(),
    );
    _write(_commentsCol(team.id).doc(c.id).set(c.toMap()));
  }

  bool canDeleteComment(Team team, TaskComment c) =>
      _uid != null && (c.authorId == _uid || team.isAdmin(_uid!));

  void deleteComment(Team team, TaskComment c) {
    _write(_commentsCol(team.id).doc(c.id).delete());
  }

  void _upsertLocal(String teamId, TaskItem task) {
    final list = [...tasksOf(teamId)]..removeWhere((t) => t.id == task.id);
    list
      ..add(task)
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    _tasks[teamId] = list;
    notifyListeners();
  }
}
