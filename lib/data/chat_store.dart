import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;

import 'app_store.dart';
import 'models.dart';
import 'reminders.dart';
import 'team_models.dart';
import 'team_store.dart';

// Messages: direct chats between two people and one group chat per team.
//
// chats/{id}:
//   direct (two people in a team together): id "<uidA>_<uidB>" (sorted),
//     member_ids [a, b], via_team = a team both are in. Starts "pending":
//     the other person approves (status "active") or blocks (status
//     "blocked", blocked_by = them; only they can unblock).
//   request (someone outside my teams): id "req_<me>_<email>", member_ids
//     [me], invite_email, status "pending"; they accept by adding themselves.
//   team: id "team_<teamId>", team_id; every team member is in it.
//   last_text / last_at / last_from for the list, read {uid: ms} for unread.
// chats/{id}/messages/{id}: from, from_name, text, at, links, task.

class ChatType {
  static const direct = 'direct';
  static const team = 'team';
}

class Chat {
  final String id;
  final String type;
  final List<String> memberIds;

  /// uid -> name (direct chats).
  final Map<String, String> names;
  final String? teamId;
  final String? inviteEmail;
  final String status;
  final String lastText;
  final DateTime? lastAt;
  final String? lastFrom;
  final Map<String, int> read;
  final String? createdBy;

  /// Who blocked the other person (status "blocked").
  final String? blockedBy;

  const Chat({
    required this.id,
    required this.type,
    this.memberIds = const [],
    this.names = const {},
    this.teamId,
    this.inviteEmail,
    this.status = 'active',
    this.lastText = '',
    this.lastAt,
    this.lastFrom,
    this.read = const {},
    this.createdBy,
    this.blockedBy,
  });

  bool get isTeam => type == ChatType.team;
  bool get isPending => status == 'pending';
  bool get isBlocked => status == 'blocked';

  /// A request from a teammate (both are members; they can read it).
  bool get isTeammateRequest => isPending && inviteEmail == null;

  Chat copyWith({String? status, String? blockedBy, bool clearBlock = false}) => Chat(
        id: id,
        type: type,
        memberIds: memberIds,
        names: names,
        teamId: teamId,
        inviteEmail: inviteEmail,
        status: status ?? this.status,
        lastText: lastText,
        lastAt: lastAt,
        lastFrom: lastFrom,
        read: read,
        createdBy: createdBy,
        blockedBy: clearBlock ? null : (blockedBy ?? this.blockedBy),
      );

  /// The other person in a direct chat.
  String? otherOf(String me) {
    for (final m in memberIds) {
      if (m != me) return m;
    }
    return null;
  }

  bool unreadFor(String me) {
    final at = lastAt;
    if (at == null || lastFrom == null || lastFrom == me) return false;
    return at.millisecondsSinceEpoch > (read[me] ?? 0);
  }

  static Chat fromMap(Map<String, dynamic> m) {
    int? ms(dynamic v) => v is int ? v : null;
    final la = ms(m['last_at']);
    return Chat(
      id: m['id'] as String,
      type: m['type'] == ChatType.team ? ChatType.team : ChatType.direct,
      memberIds: [
        for (final x in (m['member_ids'] as List?) ?? const [])
          if (x is String) x
      ],
      names: {
        for (final e in ((m['names'] as Map?) ?? const {}).entries)
          if (e.key is String && e.value is String) e.key as String: e.value as String,
      },
      teamId: m['team_id'] as String?,
      inviteEmail: m['invite_email'] as String?,
      status: switch (m['status']) {
        'pending' => 'pending',
        'blocked' => 'blocked',
        _ => 'active',
      },
      lastText: (m['last_text'] as String?) ?? '',
      lastAt: la == null ? null : DateTime.fromMillisecondsSinceEpoch(la),
      lastFrom: m['last_from'] as String?,
      read: {
        for (final e in ((m['read'] as Map?) ?? const {}).entries)
          if (e.key is String && e.value is int) e.key as String: e.value as int,
      },
      createdBy: m['created_by'] as String?,
      blockedBy: m['blocked_by'] as String?,
    );
  }
}

class ChatMessage {
  final String id;
  final String from;
  final String fromName;
  final String text;
  final DateTime at;
  final List<TaskLink> links;

  /// A task shared in the chat.
  final String? taskId;
  final String? taskTeamId;
  final String? taskTitle;

  const ChatMessage({
    required this.id,
    required this.from,
    required this.fromName,
    required this.text,
    required this.at,
    this.links = const [],
    this.taskId,
    this.taskTeamId,
    this.taskTitle,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'from': from,
        'from_name': fromName,
        'text': text,
        'at': at.millisecondsSinceEpoch,
        if (links.isNotEmpty) 'links': links.map((l) => l.toMap()).toList(),
        if (taskId != null) 'task_id': taskId,
        if (taskTeamId != null) 'task_team': taskTeamId,
        if (taskTitle != null) 'task_title': taskTitle,
      };

  static ChatMessage? tryFrom(Map<String, dynamic> m) {
    if (m['id'] is! String || m['from'] is! String || m['at'] is! int) return null;
    return ChatMessage(
      id: m['id'] as String,
      from: m['from'] as String,
      fromName: (m['from_name'] as String?) ?? '',
      text: (m['text'] as String?) ?? '',
      at: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
      links:
          ((m['links'] as List?) ?? const []).map(TaskLink.tryFrom).whereType<TaskLink>().toList(),
      taskId: m['task_id'] as String?,
      taskTeamId: m['task_team'] as String?,
      taskTitle: m['task_title'] as String?,
    );
  }
}

/// Someone I can message: in one of my teams.
class Contact {
  final String uid;
  final String name;
  final String email;
  final List<String> teamIds;
  const Contact(this.uid, this.name, this.email, this.teamIds);
}

/// Direct chat id for two people (same whoever starts it).
String directChatId(String a, String b) => a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

class ChatStore extends ChangeNotifier {
  ChatStore._();
  static final ChatStore instance = ChatStore._();

  String? _uid;
  String _email = '';
  String _name = '';
  bool _testing = false;
  final _testMessages = <String, List<ChatMessage>>{};

  final Map<String, Chat> _direct = {};
  final Map<String, Chat> _teamChats = {};
  List<Chat> requests = [];
  final List<StreamSubscription<dynamic>> _subs = [];
  final Map<String, StreamSubscription<dynamic>> _teamSubs = {};

  /// The chat on screen: no phone alert for it.
  String? openChatId;

  FirebaseFirestore get _fs => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _chats => _fs.collection('chats');

  String? get uid => _uid;

  void start({required String uid, required String email, required String name}) {
    stop();
    _uid = uid;
    _email = email.trim().toLowerCase();
    _name = name;
    _subs.add(_chats.where('member_ids', arrayContains: uid).snapshots().listen((s) {
      final before = Map.of(_direct);
      _direct.clear();
      for (final d in s.docs) {
        try {
          final c = Chat.fromMap(d.data());
          _direct[c.id] = c;
          _maybeAlert(before[c.id], c);
        } catch (e) {
          debugPrint('Skipped bad chat: $e');
        }
      }
      notifyListeners();
    }, onError: (Object e) => debugPrint('Chats error: $e')));
    if (_email.isNotEmpty) {
      _subs.add(_chats
          .where('invite_email', isEqualTo: _email)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .listen((s) {
        requests = [
          for (final d in s.docs)
            if (d.data()['id'] is String) Chat.fromMap(d.data())
        ];
        notifyListeners();
      }, onError: (Object e) => debugPrint('Chat requests error: $e')));
    }
    TeamStore.instance.addListener(_syncTeams);
    _syncTeams();
  }

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    for (final s in _teamSubs.values) {
      s.cancel();
    }
    _teamSubs.clear();
    TeamStore.instance.removeListener(_syncTeams);
    _direct.clear();
    _teamChats.clear();
    requests = [];
    _uid = null;
    openChatId = null;
  }

  /// One listener per team chat document.
  void _syncTeams() {
    if (_testing) return;
    final ids = TeamStore.instance.teams.map((t) => t.id).toSet();
    for (final id in _teamSubs.keys.toList()) {
      if (!ids.contains(id)) {
        _teamSubs.remove(id)?.cancel();
        _teamChats.remove(id);
      }
    }
    for (final id in ids) {
      _teamSubs[id] ??= _chats.doc('team_$id').snapshots().listen((d) {
        final data = d.data();
        final before = _teamChats[id];
        if (data == null) {
          _teamChats.remove(id);
        } else {
          final c = Chat.fromMap(data);
          _teamChats[id] = c;
          _maybeAlert(before, c);
        }
        notifyListeners();
      }, onError: (Object e) => debugPrint('Team chat error: $e'));
    }
  }

  /// A new message from someone else, not on screen: phone alert.
  void _maybeAlert(Chat? before, Chat now) {
    final me = _uid;
    if (me == null || before == null || now.lastFrom == null || now.lastFrom == me) return;
    if (now.lastAt == null || now.lastAt == before.lastAt || openChatId == now.id) return;
    if (!AppStore.instance.teamAlerts) return;
    PhoneReminders.instance.showNow(titleOf(now), now.lastText);
  }

  /// Tests only.
  void setForTest(
      {String? uid,
      List<Chat> direct = const [],
      List<Chat> teams = const [],
      List<Chat> requests = const [],
      Map<String, List<ChatMessage>> messages = const {}}) {
    _testing = true;
    _uid = uid;
    _testMessages
      ..clear()
      ..addAll({
        for (final e in messages.entries) e.key: [...e.value]
      });
    _direct
      ..clear()
      ..addEntries(direct.map((c) => MapEntry(c.id, c)));
    _teamChats
      ..clear()
      ..addEntries(teams.map((c) => MapEntry(c.teamId!, c)));
    this.requests = [...requests];
    notifyListeners();
  }

  // ------------------------------------------------------------------ lists

  /// Direct chats (mine and the ones waiting for the other person), newest
  /// first.
  List<Chat> get directChats =>
      _direct.values.where((c) => !c.isTeam && !(c.isPending && c.createdBy != _uid)).toList()
        ..sort((a, b) => (b.lastAt ?? DateTime(2000)).compareTo(a.lastAt ?? DateTime(2000)));

  /// A chat for every team I am in (an empty one until the first message).
  List<Chat> get teamChats {
    final out = [
      for (final t in TeamStore.instance.teams)
        _teamChats[t.id] ?? Chat(id: 'team_${t.id}', type: ChatType.team, teamId: t.id)
    ]..sort((a, b) => (b.lastAt ?? DateTime(2000)).compareTo(a.lastAt ?? DateTime(2000)));
    return out;
  }

  Chat? byId(String id) {
    if (id.startsWith('team_')) {
      final teamId = id.substring(5);
      return _teamChats[teamId] ??
          (TeamStore.instance.teamById(teamId) == null
              ? null
              : Chat(id: id, type: ChatType.team, teamId: teamId));
    }
    return _direct[id] ?? requests.where((c) => c.id == id).firstOrNull;
  }

  int get unreadCount {
    final me = _uid;
    if (me == null) return 0;
    return [...directChats, ...teamChats].where((c) => c.unreadFor(me)).length +
        incomingRequests.length;
  }

  /// People asking to message me: teammates (pending chats they started)
  /// and email requests from outside my teams.
  List<Chat> get incomingRequests {
    final me = _uid;
    return [
      ..._direct.values.where((c) => !c.isTeam && c.isPending && c.createdBy != me),
      ...requests.where((r) => !_direct.containsKey(r.id)),
    ];
  }

  /// Name shown for a chat.
  String titleOf(Chat c) {
    final me = _uid ?? '';
    if (c.isTeam) return TeamStore.instance.teamById(c.teamId ?? '')?.name ?? 'Team';
    if (c.isPending && c.createdBy == me && c.inviteEmail != null) return c.inviteEmail!;
    final other = c.otherOf(me);
    if (other == null) return c.names[c.createdBy] ?? c.inviteEmail ?? 'Chat';
    return c.names[other] ?? _nameFromTeams(other) ?? 'Member';
  }

  String? _nameFromTeams(String uid) {
    for (final t in TeamStore.instance.teams) {
      if (t.memberIds.contains(uid)) return t.nameOf(uid);
    }
    return null;
  }

  /// "Developer • UI UX": role and a team we share, for the chat header.
  String subtitleOf(Chat c) {
    final me = _uid ?? '';
    if (c.isTeam) {
      final t = TeamStore.instance.teamById(c.teamId ?? '');
      return t == null ? '' : '${t.memberIds.length} members';
    }
    if (c.isPending) {
      return c.createdBy == me
          ? 'Waiting for ${c.inviteEmail == null ? titleOf(c) : 'them'} to accept'
          : 'Wants to send you messages';
    }
    if (c.isBlocked) return c.blockedBy == me ? 'You blocked them' : 'Not accepting messages';
    final other = c.otherOf(me);
    final shared = TeamStore.instance.teams.where((t) => t.memberIds.contains(other)).toList();
    return shared.isEmpty ? '' : shared.map((t) => t.name).join(', ');
  }

  /// Everyone in my teams (except me), by name.
  List<Contact> contacts() {
    final me = _uid;
    final by = <String, Contact>{};
    for (final t in TeamStore.instance.teams) {
      for (final uid in t.memberIds) {
        if (uid == me) continue;
        final old = by[uid];
        by[uid] =
            Contact(uid, t.nameOf(uid), t.members[uid]?.email ?? '', [...?old?.teamIds, t.id]);
      }
    }
    return by.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  // ---------------------------------------------------------------- actions

  void _write(Future<void> f) => f.catchError((Object e) => debugPrint('Chat write failed: $e'));

  /// The direct chat with a teammate (made when missing). Returns its id.
  String openDirect(Contact c) {
    final me = _uid!;
    final id = directChatId(me, c.uid);
    if (_direct.containsKey(id)) return id;
    final ids = [me, c.uid]..sort();
    final now = DateTime.now().millisecondsSinceEpoch;
    final chat = {
      'id': id,
      'type': ChatType.direct,
      'member_ids': ids,
      'names': {me: _name, c.uid: c.name},
      'via_team': c.teamIds.first,
      'status': 'pending',
      'created_by': me,
      'created_at': now,
      'read': {me: now},
    };
    _direct[id] = Chat.fromMap(chat);
    notifyListeners();
    if (!_testing) _write(_chats.doc(id).set(chat));
    return id;
  }

  /// Ask someone outside my teams to chat (by their login email).
  String? requestByEmail(String email) {
    final me = _uid;
    final mail = email.trim().toLowerCase();
    if (me == null) return 'Not logged in';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail)) return 'Enter a valid email';
    if (mail == _email) return 'That is your own email';
    final known = contacts().where((c) => c.email.toLowerCase() == mail).firstOrNull;
    if (known != null) {
      openDirect(known);
      return null;
    }
    final id = 'req_${me}_$mail';
    final now = DateTime.now().millisecondsSinceEpoch;
    final chat = {
      'id': id,
      'type': ChatType.direct,
      'member_ids': [me],
      'names': {me: _name},
      'invite_email': mail,
      'status': 'pending',
      'created_by': me,
      'created_at': now,
      'read': {me: now},
    };
    _direct[id] = Chat.fromMap(chat);
    notifyListeners();
    if (!_testing) _write(_chats.doc(id).set(chat));
    return null;
  }

  /// May I write in [c] now? Team chats and accepted chats: yes. My own
  /// request: just the first message. Blocked, or their request: no.
  bool canSend(Chat c) {
    if (c.isTeam || c.status == 'active') return true;
    if (c.isPending) return c.createdBy == _uid && c.lastAt == null;
    return false;
  }

  void accept(Chat c) {
    final me = _uid;
    if (me == null) return;
    requests = requests.where((r) => r.id != c.id).toList();
    if (c.isTeammateRequest) {
      _direct[c.id] = c.copyWith(status: 'active');
      notifyListeners();
      if (!_testing) {
        _write(_chats.doc(c.id).update({
          'status': 'active',
          'read.$me': DateTime.now().millisecondsSinceEpoch,
        }));
      }
      return;
    }
    notifyListeners();
    if (_testing) return;
    _write(_chats.doc(c.id).update({
      'member_ids': FieldValue.arrayUnion([me]),
      'names.$me': _name,
      'status': 'active',
      'read.$me': DateTime.now().millisecondsSinceEpoch,
    }));
  }

  /// Stop [c]'s other person from messaging me (a request or a chat).
  void block(Chat c) {
    final me = _uid;
    if (me == null || c.isTeam || c.inviteEmail != null) return;
    _direct[c.id] = c.copyWith(status: 'blocked', blockedBy: me);
    notifyListeners();
    if (!_testing) _write(_chats.doc(c.id).update({'status': 'blocked', 'blocked_by': me}));
  }

  /// Undo my block.
  void unblock(Chat c) {
    if (!c.isBlocked || c.blockedBy != _uid) return;
    _direct[c.id] = c.copyWith(status: 'active', clearBlock: true);
    notifyListeners();
    if (!_testing) _write(_chats.doc(c.id).update({'status': 'active', 'blocked_by': null}));
  }

  /// Decline a request, or take back my own.
  void decline(Chat c) {
    requests = requests.where((r) => r.id != c.id).toList();
    _direct.remove(c.id);
    notifyListeners();
    if (!_testing) _write(_chats.doc(c.id).delete());
  }

  /// Last 300 messages, oldest first. A chat I just started may not be on
  /// the server yet (reading it is refused until it is), so on an error it
  /// tries again a moment later instead of staying empty.
  Stream<List<ChatMessage>> messagesOf(String chatId) {
    if (_testing) return Stream.value([...?_testMessages[chatId]]);
    late StreamController<List<ChatMessage>> out;
    StreamSubscription<dynamic>? sub;
    Timer? retry;
    var wait = 1;
    void listen() {
      sub?.cancel();
      sub = _chats
          .doc(chatId)
          .collection('messages')
          .orderBy('at', descending: true)
          .limit(300)
          .snapshots()
          .listen((s) {
        wait = 1;
        out.add(s.docs
            .map((d) => ChatMessage.tryFrom(d.data()))
            .whereType<ChatMessage>()
            .toList()
            .reversed
            .toList());
      }, onError: (Object e) {
        debugPrint('Messages error ($chatId), retrying: $e');
        retry?.cancel();
        retry = Timer(Duration(seconds: wait), listen);
        if (wait < 30) wait *= 2;
      });
    }

    out = StreamController<List<ChatMessage>>(
      onListen: listen,
      onCancel: () {
        retry?.cancel();
        sub?.cancel();
      },
    );
    return out.stream;
  }

  /// Sends a message (text, links and/or a task).
  void send(Chat c, String text,
      {List<TaskLink> links = const [], TaskItem? task, String? taskTeamId}) {
    final me = _uid;
    final clean = text.trim();
    if (me == null || (clean.isEmpty && links.isEmpty && task == null) || !canSend(c)) return;
    final now = DateTime.now();
    final ms = now.millisecondsSinceEpoch;
    final msg = ChatMessage(
      id: '${ms}_${me.substring(0, me.length < 6 ? me.length : 6)}',
      from: me,
      fromName: _name,
      text: clean.length > 4000 ? clean.substring(0, 4000) : clean,
      at: now,
      links: links,
      taskId: task?.id,
      taskTeamId: taskTeamId,
      taskTitle: task?.title,
    );
    final preview = clean.isNotEmpty
        ? clean
        : (task != null
            ? 'Shared a task: ${task.title}'
            : (links.any((l) => l.title == 'Photo') ? '📷 Photo' : 'Shared a link'));
    final last = {
      'last_text': preview.length > 200 ? '${preview.substring(0, 197)}...' : preview,
      'last_at': ms,
      'last_from': me,
      'read.$me': ms,
    };
    if (_testing) {
      (_testMessages[c.id] ??= []).add(msg);
      final updated = Chat(
          id: c.id,
          type: c.type,
          memberIds: c.memberIds,
          names: c.names,
          teamId: c.teamId,
          inviteEmail: c.inviteEmail,
          status: c.status,
          blockedBy: c.blockedBy,
          lastText: last['last_text'] as String,
          lastAt: now,
          lastFrom: me,
          read: {...c.read, me: ms},
          createdBy: c.createdBy);
      if (c.isTeam) {
        _teamChats[c.teamId!] = updated;
      } else {
        _direct[c.id] = updated;
      }
      notifyListeners();
      return;
    }
    final doc = _chats.doc(c.id);
    if (c.isTeam && !_teamChats.containsKey(c.teamId)) {
      // First message in the team chat: make its document first.
      _write(doc.set({
        'id': c.id,
        'type': ChatType.team,
        'team_id': c.teamId,
        'member_ids': <String>[],
        'created_by': me,
        'created_at': ms,
      }));
    }
    _write(doc.collection('messages').doc(msg.id).set(msg.toMap()));
    _write(doc.update(last));
  }

  /// I have seen everything in [c].
  void markRead(Chat c) {
    final me = _uid;
    final at = c.lastAt;
    if (me == null || at == null || _testing) return;
    if ((c.read[me] ?? 0) >= at.millisecondsSinceEpoch) return;
    if (c.isTeam && !_teamChats.containsKey(c.teamId)) return;
    _write(_chats.doc(c.id).update({'read.$me': DateTime.now().millisecondsSinceEpoch}));
  }

  void deleteMessage(Chat c, ChatMessage m) {
    if (_testing || m.from != _uid) return;
    _write(_chats.doc(c.id).collection('messages').doc(m.id).delete());
  }
}

/// The team for a team chat.
Team? teamOfChat(Chat c) => c.teamId == null ? null : TeamStore.instance.teamById(c.teamId!);
