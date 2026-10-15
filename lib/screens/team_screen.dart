import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import 'task_form_screen.dart';
import 'team_task_detail_screen.dart';
import 'teams_screen.dart';

enum _Filter { all, mine, pending, done }

/// One team: its tasks and its people.
class TeamScreen extends StatefulWidget {
  final String teamId;
  const TeamScreen({super.key, required this.teamId});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  _Filter _filter = _Filter.all;

  Future<void> _onMenu(String action, Team team) async {
    final store = TeamStore.instance;
    switch (action) {
      case 'edit':
        final r = await showTeamDialog(context, team: team);
        if (r != null) store.renameTeam(team, r.$1, r.$2);
        break;
      case 'leave':
        final ok = await confirmDialog(context,
            title: 'Leave ${team.name}?',
            message: 'You will no longer see this team or its tasks.',
            confirmLabel: 'Leave',
            danger: true);
        if (ok) {
          store.leaveTeam(team);
          if (mounted) Navigator.pop(context);
        }
        break;
      case 'delete':
        final ok = await confirmDialog(context,
            title: 'Delete ${team.name}?',
            message: 'The team and ALL its tasks will be deleted for everyone. '
                'This cannot be undone.',
            confirmLabel: 'Delete team',
            danger: true);
        if (ok) {
          store.deleteTeam(team);
          if (mounted) Navigator.pop(context);
        }
        break;
    }
  }

  List<TaskItem> _filtered(List<TaskItem> all, String me) {
    final list = all.where((t) {
      switch (_filter) {
        case _Filter.all:
          return true;
        case _Filter.mine:
          return t.assigneeId == me;
        case _Filter.pending:
          return t.status == TaskStatus.pending;
        case _Filter.done:
          return t.isCompleted;
      }
    }).toList();
    int rank(TaskItem t) => t.status == TaskStatus.pending ? 0 : (t.isCompleted ? 1 : 2);
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.startAt.compareTo(b.startAt);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final team = store.teamById(widget.teamId);
        if (team == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.groups_rounded,
              title: 'Team not found',
              subtitle: 'It may have been deleted, or you are no longer a member.',
            ),
          );
        }
        final me = store.uid ?? '';
        final admin = team.isAdmin(me);
        final owner = team.ownerId == me;
        final tasks = store.tasksOf(team.id);
        final active = tasks.where((t) => !t.isCancelled).toList();
        final done = active.where((t) => t.isCompleted).length;

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(team.name),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (a) => _onMenu(a, team),
                  itemBuilder: (_) => [
                    if (owner) const PopupMenuItem(value: 'edit', child: Text('Edit team')),
                    if (!owner) const PopupMenuItem(value: 'leave', child: Text('Leave team')),
                    if (owner)
                      const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete team', style: TextStyle(color: AppColors.danger))),
                  ],
                ),
              ],
              bottom: TabBar(
                tabs: [
                  Tab(text: 'Tasks (${active.length})'),
                  Tab(text: 'Members (${team.memberIds.length})'),
                ],
              ),
            ),
            floatingActionButton: admin
                ? FloatingActionButton.extended(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TaskFormScreen(team: team)),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Task'),
                  )
                : null,
            body: TabBarView(
              children: [
                // ------------------------------------------------- tasks
                ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                  children: [
                    if (active.isNotEmpty) ...[
                      Row(
                        children: [
                          Text('$done of ${active.length} done',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text('${(done * 100 / active.length).round()}%',
                              style:
                                  TextStyle(color: Color(team.color), fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: done / active.length,
                          minHeight: 8,
                          color: Color(team.color),
                          backgroundColor: Color(team.color).withAlpha(30),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      children: [
                        for (final f in _Filter.values) ...[
                          if (f != _Filter.all) const SizedBox(width: 6),
                          TabPill(
                            label: switch (f) {
                              _Filter.all => 'All',
                              _Filter.mine => 'Mine',
                              _Filter.pending => 'Pending',
                              _Filter.done => 'Done',
                            },
                            active: _filter == f,
                            onTap: () => setState(() => _filter = f),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    ..._taskList(team, tasks, me, admin),
                  ],
                ),
                // ----------------------------------------------- members
                _MembersTab(team: team, me: me),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _taskList(Team team, List<TaskItem> tasks, String me, bool admin) {
    final list = _filtered(tasks, me);
    if (list.isEmpty) {
      return [
        EmptyState(
          icon: Icons.inbox_outlined,
          title: tasks.isEmpty ? 'No tasks yet' : 'Nothing here',
          subtitle: tasks.isEmpty
              ? (admin
                  ? 'Tap "+ Task" to create one and assign it to someone.'
                  : 'Your manager has not added tasks yet.')
              : 'Try another filter.',
        ),
      ];
    }
    final store = TeamStore.instance;
    return [
      for (final t in list)
        TaskTile(
          task: t,
          teamTask: true,
          onTap: () => openTeamTask(context, team, t),
          onToggle:
              store.canComplete(team, t) ? () => store.setCompleted(team, t, !t.isCompleted) : null,
          trailing: AssigneeBadge(team: team, task: t),
        ),
    ];
  }
}

class _MembersTab extends StatelessWidget {
  final Team team;
  final String me;
  const _MembersTab({required this.team, required this.me});

  Future<void> _invite(BuildContext context) async {
    final email = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add person'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the email they use to log in to TaskFlow. They will see the '
              'invitation in their Teams tab (they can install the app later too).',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: fieldDecoration('name@example.com', icon: Icons.mail_outline_rounded),
              inputFormatters: [LengthLimitingTextInputFormatter(200)],
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, email.text), child: const Text('Invite')),
        ],
      ),
    );
    if (result == null || !context.mounted) return;
    final err = TeamStore.instance.inviteByEmail(team, result);
    showSnack(context, err ?? 'Invitation sent to ${normalizeEmail(result)}');
  }

  Future<void> _memberAction(BuildContext context, String action, String uid) async {
    final store = TeamStore.instance;
    final name = team.nameOf(uid);
    switch (action) {
      case 'manager':
        store.setManager(team, uid, true);
        showSnack(context, '$name is now a manager');
        break;
      case 'member':
        store.setManager(team, uid, false);
        showSnack(context, '$name is now a member');
        break;
      case 'remove':
        final ok = await confirmDialog(context,
            title: 'Remove $name?',
            message: '$name will no longer see this team. Their pending tasks become unassigned.',
            confirmLabel: 'Remove',
            danger: true);
        if (ok) store.removeMember(team, uid);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    final admin = team.isAdmin(me);
    final owner = team.ownerId == me;
    final invites = store.sentInvites[team.id] ?? const <TeamInvite>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        if (admin) ...[
          PrimaryButton(
            label: 'Add person by email',
            icon: Icons.person_add_alt_1_rounded,
            onPressed: () => _invite(context),
          ),
          const SizedBox(height: 18),
        ],
        for (final uid in team.sortedMemberIds) _memberRow(context, uid, owner, admin),
        if (admin && invites.isNotEmpty) ...[
          const SizedBox(height: 18),
          const SectionHeader(title: 'Waiting to accept'),
          const SizedBox(height: 8),
          for (final i in invites)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: AppColors.warningLight,
                child: Icon(Icons.hourglass_top_rounded, color: AppColors.warning, size: 20),
              ),
              title: Text(i.email),
              subtitle:
                  Text('Invited by ${i.invitedByName.isEmpty ? 'a manager' : i.invitedByName}'),
              trailing: IconButton(
                tooltip: 'Cancel invitation',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => store.cancelInvite(i),
              ),
            ),
        ],
        const SizedBox(height: 18),
        const Text(
          'Owner: everything. Managers: add people and create/assign tasks. '
          'Members: see the team and mark their own tasks done.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
        ),
      ],
    );
  }

  Widget _memberRow(BuildContext context, String uid, bool owner, bool admin) {
    final role = team.roleOf(uid) ?? TeamRole.member;
    final info = team.members[uid];
    final isMe = uid == me;
    final pending = TeamStore.instance
        .tasksOf(team.id)
        .where((t) => t.assigneeId == uid && t.status == TaskStatus.pending)
        .length;

    final actions = <PopupMenuEntry<String>>[
      if (owner && !isMe && role == TeamRole.member)
        const PopupMenuItem(value: 'manager', child: Text('Make manager')),
      if (owner && !isMe && role == TeamRole.manager)
        const PopupMenuItem(value: 'member', child: Text('Make member')),
      if (!isMe && role != TeamRole.owner && (owner || (admin && role == TeamRole.member)))
        const PopupMenuItem(
            value: 'remove',
            child: Text('Remove from team', style: TextStyle(color: AppColors.danger))),
    ];

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Avatar(name: team.nameOf(uid), size: 42),
      title: Text(isMe ? '${team.nameOf(uid)} (you)' : team.nameOf(uid),
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          if (info != null && info.email.isNotEmpty) info.email,
          if (pending > 0) '$pending pending',
        ].join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RoleChip(role: role),
          if (actions.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (a) => _memberAction(context, a, uid),
              itemBuilder: (_) => actions,
            ),
        ],
      ),
    );
  }
}
