import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../data/team_models.dart';
import '../data/team_stats.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import '../widgets/responsive.dart';
import '../widgets/task_board.dart';
import 'report_screen.dart';
import 'task_panel.dart';
import 'team_task_detail_screen.dart';
import 'teams_screen.dart';
import 'create_task_dialog.dart';

part 'team_wide.dart';

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
  bool _board = false;

  // Laptop layout (team_wide.dart).
  int _wideTab = 0;
  bool _wideBoard = true;
  String _search = '';

  void _update(VoidCallback change) => setState(change);

  Future<void> _onMenu(String action, Team team) async {
    final store = TeamStore.instance;
    switch (action) {
      case 'report':
        openWeeklyReport(context, team);
        break;
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
        if (MediaQuery.sizeOf(context).width >= kWideLayout) return _buildWide(context, team);
        final me = store.uid ?? '';
        final admin = team.isAdmin(me);
        final owner = team.ownerId == me;
        final tasks = store.tasksOf(team.id);
        final active = tasks.where((t) => !t.isCancelled).toList();
        final done = active.where((t) => t.isCompleted).length;

        return DefaultTabController(
          // Owner/managers get a third tab with the dashboard.
          key: ValueKey(admin),
          length: admin ? 3 : 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(team.name),
              actions: [
                IconButton(
                  tooltip: _board ? 'List view' : 'Board view',
                  icon: Icon(_board ? Icons.view_agenda_outlined : Icons.view_kanban_outlined),
                  onPressed: () => setState(() => _board = !_board),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (a) => _onMenu(a, team),
                  itemBuilder: (_) => [
                    if (admin) const PopupMenuItem(value: 'report', child: Text('Weekly report')),
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
                  if (admin) const Tab(text: 'Overview'),
                ],
              ),
            ),
            floatingActionButton: TeamStore.instance.canCreateTask(team)
                ? FloatingActionButton.extended(
                    onPressed: () => showCreateTask(context, team: team),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Task'),
                  )
                : null,
            body: DetailPanelHost(
                panelBuilder: buildTaskPanel,
                child: TabBarView(
                  children: [
                    // ------------------------------------------------- tasks
                    if (_board)
                      TaskBoard(team: team, tasks: tasks)
                    else
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
                                    style: TextStyle(
                                        color: Color(team.color), fontWeight: FontWeight.w700)),
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
                    if (admin) _OverviewTab(team: team, tasks: tasks),
                  ],
                )),
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

/// "Add person" dialog: invites an email address to [team].
Future<void> showInviteDialog(BuildContext context, Team team) async {
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

Future<void> _memberAction(BuildContext context, Team team, String action, String uid) async {
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

/// What the current user may do with [uid] in [team] (owner/manager menus).
List<PopupMenuEntry<String>> _memberMenu(Team team, String me, String uid) {
  final role = team.roleOf(uid) ?? TeamRole.member;
  final owner = team.ownerId == me;
  final admin = team.isAdmin(me);
  final isMe = uid == me;
  return [
    if (owner && !isMe && role == TeamRole.member)
      const PopupMenuItem(value: 'manager', child: Text('Make manager')),
    if (owner && !isMe && role == TeamRole.manager)
      const PopupMenuItem(value: 'member', child: Text('Make member')),
    if (!isMe && role != TeamRole.owner && (owner || (admin && role == TeamRole.member)))
      const PopupMenuItem(
          value: 'remove',
          child: Text('Remove from team', style: TextStyle(color: AppColors.danger))),
  ];
}

class _MembersTab extends StatelessWidget {
  final Team team;
  final String me;
  const _MembersTab({required this.team, required this.me});

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
            onPressed: () => showInviteDialog(context, team),
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

    final actions = _memberMenu(team, me, uid);

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
              onSelected: (a) => _memberAction(context, team, a, uid),
              itemBuilder: (_) => actions,
            ),
        ],
      ),
    );
  }
}

/// Dashboard for owner/managers: progress, who has how much work, what is late.
class _OverviewTab extends StatelessWidget {
  final Team team;
  final List<TaskItem> tasks;
  const _OverviewTab({required this.team, required this.tasks});

  @override
  Widget build(BuildContext context) {
    final st = TeamStats.compute(team, tasks, DateTime.now());
    final color = Color(team.color);
    if (st.total == 0) {
      return ListView(children: const [
        EmptyState(
          icon: Icons.insights_rounded,
          title: 'Nothing to show yet',
          subtitle: 'Create tasks and assign them; progress will appear here.',
        ),
      ]);
    }
    final summary = <Widget>[
      Row(
        children: [
          _StatTile(label: 'Pending', value: st.pending, color: AppColors.warning),
          const SizedBox(width: 10),
          _StatTile(label: 'Overdue', value: st.overdue, color: AppColors.danger),
          const SizedBox(width: 10),
          _StatTile(label: 'Done this week', value: st.doneThisWeek, color: AppColors.success),
        ],
      ),
      const SizedBox(height: 16),
      WhiteCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${st.done} of ${st.total} tasks done',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${(st.progress * 100).round()}%',
                    style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: st.progress,
                minHeight: 8,
                color: color,
                backgroundColor: color.withAlpha(30),
              ),
            ),
            if (st.unassigned > 0) ...[
              const SizedBox(height: 8),
              Text('${st.unassigned} task(s) not assigned to anyone',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      _DoneChart(doneByDay: st.doneByDay, color: color),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => openWeeklyReport(context, team),
        icon: const Icon(Icons.summarize_outlined),
        label: const Text('Weekly report (share on WhatsApp)'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
      ),
    ];
    final details = <Widget>[
      const SectionHeader(title: 'People'),
      const SizedBox(height: 10),
      for (final m in st.members) _MemberLoad(team: team, stats: m),
      if (st.overdueTasks.isNotEmpty) ...[
        const SizedBox(height: 20),
        const SectionHeader(title: 'Overdue'),
        const SizedBox(height: 10),
        for (final t in st.overdueTasks)
          TaskTile(
            task: t,
            teamTask: true,
            onTap: () => openTeamTask(context, team, t),
            trailing: AssigneeBadge(team: team, task: t),
          ),
      ],
    ];
    return LayoutBuilder(builder: (context, box) {
      // Big screen: numbers and chart on the left, people and late work on the right.
      if (box.maxWidth >= kWideLayout) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child:
                        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: summary)),
                const SizedBox(width: 24),
                Expanded(
                    child:
                        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: details)),
              ],
            ),
          ],
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: [...summary, const SizedBox(height: 20), ...details],
      );
    });
  }
}

/// Bars: tasks finished on each day of this week.
class _DoneChart extends StatelessWidget {
  final List<int> doneByDay;
  final Color color;

  /// Height of the bar area; [bare] = no card around it (already in one).
  final double height;
  final bool bare;
  const _DoneChart(
      {required this.doneByDay, required this.color, this.height = 140, this.bare = false});

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final most = doneByDay.fold<int>(0, (a, b) => b > a ? b : a);
    final today = DateTime.now().weekday - 1;
    final barMax = height - 73;
    final chart = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Done per day (this week)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: bare ? 18 : 14)),
        const SizedBox(height: 14),
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Tooltip(
                    message: '${_days[i]}: ${doneByDay[i]} done',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(doneByDay[i] == 0 ? '' : '${doneByDay[i]}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        const SizedBox(height: 4),
                        Container(
                          height: most == 0 ? 3 : 3 + barMax * doneByDay[i] / most,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: i > today ? color.withAlpha(40) : color,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(_days[i],
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: i == today ? FontWeight.w800 : FontWeight.w500,
                                color: i == today ? AppColors.text : AppColors.textMuted)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    return bare ? chart : WhiteCard(child: chart);
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(22),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _MemberLoad extends StatelessWidget {
  final Team team;
  final MemberStats stats;
  const _MemberLoad({required this.team, required this.stats});

  @override
  Widget build(BuildContext context) {
    final name = team.nameOf(stats.uid);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WhiteCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Avatar(name: name, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    [
                      '${stats.pending} pending',
                      if (stats.overdue > 0) '${stats.overdue} overdue',
                      '${stats.done} done',
                    ].join(' • '),
                    style: TextStyle(
                        fontSize: 12.5,
                        color: stats.overdue > 0 ? AppColors.danger : AppColors.textMuted),
                  ),
                  if (stats.total > 0) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: stats.progress,
                        minHeight: 5,
                        backgroundColor: AppColors.primaryLight,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (stats.doneThisWeek > 0) ...[
              const SizedBox(width: 10),
              Tooltip(
                message: 'Done this week',
                child: TagChip(label: '+${stats.doneThisWeek} wk', color: AppColors.success),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The team's Kanban board (see [KanbanBoard]): owner/managers can move any
/// card, members only their own.
class TaskBoard extends StatelessWidget {
  final Team team;
  final List<TaskItem> tasks;

  /// Space around the board on wide screens.
  final EdgeInsetsGeometry padding;

  const TaskBoard(
      {super.key,
      required this.team,
      required this.tasks,
      this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 90)});

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    return KanbanBoard(
      tasks: tasks,
      padding: padding,
      canMove: (t) => store.canComplete(team, t),
      onMove: (t, column) => store.moveTo(team, t, column),
      onOpen: (context, t) => openTeamTask(context, team, t),
      trailing: (t) => AssigneeBadge(team: team, task: t),
    );
  }
}
