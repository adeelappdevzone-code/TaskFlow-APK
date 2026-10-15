import 'models.dart';
import 'team_models.dart';

enum ActivityKind { completed, assigned, invited, teamCreated }

/// One line in "Recent activity": [actor] [verb] [object][suffix].
class ActivityItem {
  final ActivityKind kind;
  final DateTime at;
  final String actor;
  final String verb;
  final String object;
  final String suffix;
  final String teamId;

  const ActivityItem({
    required this.kind,
    required this.at,
    required this.actor,
    required this.verb,
    required this.object,
    this.suffix = '',
    required this.teamId,
  });

  String get text => [actor, verb, '$object$suffix'].where((s) => s.isNotEmpty).join(' ');
}

/// Recent things that happened in [teams], newest first, built from the data
/// the app already has (finished tasks, assignments, open invitations, new
/// teams). [me] is shown as "You".
List<ActivityItem> recentActivity({
  required List<Team> teams,
  required List<TaskItem> Function(String teamId) tasksOf,
  required List<TeamInvite> Function(String teamId) invitesOf,
  required String me,
  int limit = 8,
}) {
  final out = <ActivityItem>[];
  for (final team in teams) {
    String who(String? uid) => uid == null ? 'Someone' : (uid == me ? 'You' : team.nameOf(uid));
    for (final t in tasksOf(team.id)) {
      final done = t.completedAt;
      if (t.isCompleted && done != null) {
        out.add(ActivityItem(
          kind: ActivityKind.completed,
          at: done,
          actor: who(t.completedBy ?? t.assigneeId),
          verb: 'completed',
          object: t.title,
          teamId: team.id,
        ));
      }
      final assigned = t.assignedAt;
      if (assigned != null && t.assignedBy != null && t.assigneeId != null) {
        out.add(ActivityItem(
          kind: ActivityKind.assigned,
          at: assigned,
          actor: who(t.assignedBy),
          verb: 'assigned',
          object: t.title,
          suffix: ' to ${t.assigneeId == me ? 'you' : team.nameOf(t.assigneeId)}',
          teamId: team.id,
        ));
      }
    }
    for (final i in invitesOf(team.id)) {
      out.add(ActivityItem(
        kind: ActivityKind.invited,
        at: i.createdAt,
        actor: i.invitedBy == me ? 'You' : (i.invitedByName.isEmpty ? 'Someone' : i.invitedByName),
        verb: 'invited',
        object: i.email,
        suffix: ' to ${team.name}',
        teamId: team.id,
      ));
    }
    out.add(ActivityItem(
      kind: ActivityKind.teamCreated,
      at: team.createdAt,
      actor: '',
      verb: 'New team',
      object: team.name,
      suffix: ' was created',
      teamId: team.id,
    ));
  }
  out.sort((a, b) => b.at.compareTo(a.at));
  return out.length > limit ? out.sublist(0, limit) : out;
}
