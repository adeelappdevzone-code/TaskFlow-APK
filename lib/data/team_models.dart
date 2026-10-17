// Teams: shared spaces where an owner (and managers) create tasks and assign
// them to members.
//
// Firestore layout:
//   teams/{teamId}               the team (who is in it and their roles)
//   teams/{teamId}/tasks/{id}    the team's tasks (same fields as personal tasks)
//   invites/{teamId}_{email}     an open invitation for that email address

int _ms(DateTime d) => d.millisecondsSinceEpoch;
DateTime _dt(dynamic v) => DateTime.fromMillisecondsSinceEpoch(v as int);

enum TeamRole { owner, manager, member }

extension TeamRoleX on TeamRole {
  String get label => switch (this) {
        TeamRole.owner => 'Owner',
        TeamRole.manager => 'Manager',
        TeamRole.member => 'Member',
      };
}

/// Name/email shown for a team member (copied into the team so everyone in
/// the team can see it).
class TeamMemberInfo {
  final String name;
  final String email;

  /// Minutes the person works in a week (their own work hours × work days).
  /// Null until they set their work hours: the team's [Team.weekHours] is used.
  final int? weekMinutes;
  const TeamMemberInfo({required this.name, required this.email, this.weekMinutes});

  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        if (weekMinutes != null) 'week_min': weekMinutes,
      };

  factory TeamMemberInfo.fromMap(Map<String, dynamic> m) => TeamMemberInfo(
        name: (m['name'] as String?) ?? '',
        email: (m['email'] as String?) ?? '',
        weekMinutes:
            m['week_min'] is int && (m['week_min'] as int) > 0 ? m['week_min'] as int : null,
      );
}

class Team {
  final String id;
  String name;
  int color;
  final String ownerId;

  /// Everyone in the team, owner included.
  List<String> memberIds;

  /// Members who can also create tasks and manage people (owner not included).
  List<String> managerIds;
  Map<String, TeamMemberInfo> members;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Work hours per person per week (Team Workload capacity).
  int weekHours;

  Team({
    required this.id,
    required this.name,
    required this.color,
    required this.ownerId,
    required this.memberIds,
    required this.managerIds,
    required this.members,
    required this.createdAt,
    required this.updatedAt,
    this.weekHours = 40,
  });

  TeamRole? roleOf(String uid) {
    if (uid == ownerId) return TeamRole.owner;
    if (managerIds.contains(uid)) return TeamRole.manager;
    if (memberIds.contains(uid)) return TeamRole.member;
    return null;
  }

  /// Owner or manager: can create/edit/assign tasks and manage people.
  bool isAdmin(String uid) => uid == ownerId || managerIds.contains(uid);

  String nameOf(String? uid) {
    if (uid == null) return '';
    final info = members[uid];
    if (info == null) return 'Former member';
    if (info.name.isNotEmpty) return info.name;
    return info.email.isEmpty ? 'Member' : info.email.split('@').first;
  }

  /// Owner first, then managers, then members, each by name.
  List<String> get sortedMemberIds {
    int rank(String uid) => switch (roleOf(uid)) {
          TeamRole.owner => 0,
          TeamRole.manager => 1,
          _ => 2,
        };
    return [...memberIds]..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        return nameOf(a).toLowerCase().compareTo(nameOf(b).toLowerCase());
      });
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'color': color,
        'owner_id': ownerId,
        'member_ids': memberIds,
        'manager_ids': managerIds,
        'members': {for (final e in members.entries) e.key: e.value.toMap()},
        'created_at': _ms(createdAt),
        'updated_at': _ms(updatedAt),
        'week_hours': weekHours,
      };

  factory Team.fromMap(Map<String, dynamic> m) {
    final rawMembers = (m['members'] as Map?) ?? const {};
    return Team(
      id: m['id'] as String,
      name: m['name'] as String,
      color: m['color'] as int,
      ownerId: m['owner_id'] as String,
      memberIds: List<String>.from(m['member_ids'] as List),
      managerIds: List<String>.from((m['manager_ids'] as List?) ?? const []),
      members: {
        for (final e in rawMembers.entries)
          if (e.value is Map)
            e.key as String: TeamMemberInfo.fromMap(Map<String, dynamic>.from(e.value as Map)),
      },
      createdAt: _dt(m['created_at']),
      updatedAt: _dt(m['updated_at'] ?? m['created_at']),
      weekHours:
          m['week_hours'] is int && (m['week_hours'] as int) > 0 ? m['week_hours'] as int : 40,
    );
  }
}

/// Invitations are stored under this id, so the security rules can check
/// "is there an invite for this team and my email?".
String inviteIdFor(String teamId, String email) => '${teamId}_${normalizeEmail(email)}';

String normalizeEmail(String email) => email.trim().toLowerCase();

bool looksLikeEmail(String email) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());

class TeamInvite {
  final String id;
  final String teamId;
  final String teamName;
  final String email;
  final String invitedBy;
  final String invitedByName;
  final DateTime createdAt;

  TeamInvite({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.email,
    required this.invitedBy,
    required this.invitedByName,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'team_id': teamId,
        'team_name': teamName,
        'email': email,
        'invited_by': invitedBy,
        'invited_by_name': invitedByName,
        'created_at': _ms(createdAt),
      };

  factory TeamInvite.fromMap(Map<String, dynamic> m) => TeamInvite(
        id: m['id'] as String,
        teamId: m['team_id'] as String,
        teamName: m['team_name'] as String,
        email: m['email'] as String,
        invitedBy: m['invited_by'] as String,
        invitedByName: (m['invited_by_name'] as String?) ?? '',
        createdAt: _dt(m['created_at']),
      );
}

/// A comment on a team task (stored in teams/{teamId}/comments).
class TaskComment {
  final String id;
  final String taskId;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime createdAt;

  /// Members tagged with "@Name" (only they get a notification).
  final List<String> mentions;

  TaskComment({
    required this.id,
    required this.taskId,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAt,
    this.mentions = const [],
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'task_id': taskId,
        'author_id': authorId,
        'author_name': authorName,
        'text': text,
        'created_at': _ms(createdAt),
        if (mentions.isNotEmpty) 'mentions': mentions,
      };

  factory TaskComment.fromMap(Map<String, dynamic> m) => TaskComment(
        id: m['id'] as String,
        taskId: m['task_id'] as String,
        authorId: m['author_id'] as String,
        authorName: (m['author_name'] as String?) ?? '',
        text: m['text'] as String,
        createdAt: _dt(m['created_at']),
        mentions: [
          for (final x in (m['mentions'] as List?) ?? const [])
            if (x is String) x,
        ],
      );
}

/// Name used after "@" for a member: their name, or the first part of
/// their email.
String mentionName(Team team, String uid) {
  final info = team.members[uid];
  if (info == null) return '';
  final n = info.name.trim();
  if (n.isNotEmpty) return n;
  return info.email.split('@').first;
}

/// Members tagged in [text] with "@Full Name" or "@FirstName" (not [except]).
/// A first name only counts when no other member has it.
List<String> findMentions(Team team, String text, {String? except}) {
  final lower = text.toLowerCase();
  bool tagged(String name) {
    if (name.isEmpty) return false;
    final pattern = RegExp(
        '(?<![\\p{L}\\p{N}_.])@${RegExp.escape(name.toLowerCase())}(?![\\p{L}\\p{N}_])',
        unicode: true);
    return pattern.hasMatch(lower);
  }

  final firstNames = <String, int>{};
  for (final uid in team.memberIds) {
    final first = mentionName(team, uid).split(RegExp(r'\s+')).first.toLowerCase();
    firstNames[first] = (firstNames[first] ?? 0) + 1;
  }
  final out = <String>[];
  for (final uid in team.memberIds) {
    if (uid == except) continue;
    final full = mentionName(team, uid);
    final first = full.split(RegExp(r'\s+')).first;
    if (tagged(full) || (firstNames[first.toLowerCase()] == 1 && tagged(first))) out.add(uid);
  }
  return out;
}
