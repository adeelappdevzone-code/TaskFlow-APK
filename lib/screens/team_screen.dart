import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../data/team_models.dart';
import '../data/team_stats.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import '../widgets/responsive.dart';
import 'report_screen.dart';
import 'task_panel.dart';
import 'task_page.dart';
import 'teams_screen.dart';
import 'create_task_dialog.dart';
import 'task_open.dart';
import 'task_ui.dart';
import 'team_board.dart';
import 'messages_screen.dart';
import '../data/chat_store.dart';
import '../data/task_repository.dart';

part 'team_wide.dart';

enum _Filter { all, mine, pending, done }

/// One team: its tasks and its people.
class TeamScreen extends StatefulWidget {
  final String teamId;
  const TeamScreen({super.key, required this.teamId});

  /// The team whose page is open (laptop side menu highlights it).
  static final open = ValueNotifier<String?>(null);

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  _Filter _filter = _Filter.all;
  bool _board = false;

  // Laptop layout (team_wide.dart).
  int _wideTab = 0;
  int _overviewDays = 7;
  String _search = '';

  void _update(VoidCallback change) => setState(change);

  @override
  void initState() {
    super.initState();
    final id = widget.teamId;
    // After the frame: the side menu listens and may not rebuild mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) => TeamScreen.open.value = id);
  }

  @override
  void dispose() {
    final id = widget.teamId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (TeamScreen.open.value == id) TeamScreen.open.value = null;
    });
    super.dispose();
  }

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
                    label: const Text('New Task'),
                  )
                : null,
            body: DetailPanelHost(
                panelBuilder: buildTaskPanel,
                child: TabBarView(
                  children: [
                    // ------------------------------------------------- tasks
                    if (_board)
                      TeamBoard(team: team, tasks: tasks)
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
                              TabPill(
                                label: 'All (${active.length})',
                                active: _filter != _Filter.mine,
                                onTap: () => setState(() => _filter = _Filter.all),
                              ),
                              const SizedBox(width: 6),
                              TabPill(
                                label:
                                    'Assigned to me (${active.where((t) => t.assigneeId == me).length})',
                                active: _filter == _Filter.mine,
                                onTap: () => setState(() => _filter = _Filter.mine),
                              ),
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
        if (t.assigneeId != null && t.assigneeId == me)
          // My tasks: a blue bar on the left and "Assigned to you".
          Container(
            margin: const EdgeInsets.only(bottom: 2),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: AppColors.primary, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 10, top: 4),
                  child: AssignedToYouChip(),
                ),
                TaskTile(
                  task: t,
                  teamTask: true,
                  onTap: () => openTeamTask(context, team, t),
                  onToggle: store.canComplete(team, t)
                      ? () => tickTask(context, TaskRef(t, team), !t.isCompleted)
                      : null,
                  trailing: AssigneeBadge(team: team, task: t),
                ),
              ],
            ),
          )
        else
          TaskTile(
            task: t,
            teamTask: true,
            onTap: () => openTeamTask(context, team, t),
            onToggle: store.canComplete(team, t)
                ? () => tickTask(context, TaskRef(t, team), !t.isCompleted)
                : null,
            trailing: AssigneeBadge(team: team, task: t),
          ),
    ];
  }
}

/// "Add person" dialog: invites an email address to [team].
/// "Add person": pick people you already work with (in your other teams),
/// or type an email. Each gets an invitation to accept, as before.
Future<void> showInviteDialog(BuildContext context, Team team) async {
  final store = TeamStore.instance;
  final me = store.uid;
  final invited = {
    for (final i in store.sentInvites[team.id] ?? const <TeamInvite>[]) normalizeEmail(i.email)
  };
  // People from my other teams who are not in this one yet.
  final contacts = <String, (String, String)>{};
  for (final t in store.teams) {
    if (t.id == team.id) continue;
    for (final uid in t.memberIds) {
      if (uid == me || team.memberIds.contains(uid)) continue;
      final info = t.members[uid];
      if (info == null || info.email.isEmpty) continue;
      contacts.putIfAbsent(uid, () => (t.nameOf(uid), normalizeEmail(info.email)));
    }
  }
  final list = contacts.values.toList()..sort((a, b) => a.$1.compareTo(b.$1));
  final picked = <String>{};
  final email = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Add people to ${team.name}'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (list.isNotEmpty) ...[
                  const Text('People you work with', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  for (final (name, mail) in list)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: picked.contains(mail) || invited.contains(mail),
                      onChanged: invited.contains(mail)
                          ? null
                          : (v) =>
                              setState(() => v == true ? picked.add(mail) : picked.remove(mail)),
                      secondary: Avatar(name: name, size: 34),
                      title: Text(name),
                      subtitle: Text(invited.contains(mail) ? '$mail • already invited' : mail),
                    ),
                  const Divider(height: 24),
                ],
                const Text('Or invite by email', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: fieldDecoration('name@example.com', icon: Icons.mail_outline_rounded),
                  inputFormatters: [LengthLimitingTextInputFormatter(200)],
                  onSubmitted: (_) => Navigator.pop(ctx, true),
                ),
                const SizedBox(height: 8),
                const Text(
                  'They get an invitation (in the app and their Teams tab) and join when '
                  'they accept.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(picked.isEmpty
                ? 'Invite'
                : 'Invite (${picked.length + (email.text.trim().isEmpty ? 0 : 1)})'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final emails = {...picked, if (email.text.trim().isNotEmpty) email.text.trim()};
  if (emails.isEmpty) return;
  final errors = <String>[];
  for (final e in emails) {
    final err = store.inviteByEmail(team, e);
    if (err != null) errors.add(err);
  }
  final sent = emails.length - errors.length;
  showSnack(
      context,
      errors.isEmpty
          ? (sent == 1
              ? 'Invitation sent to ${normalizeEmail(emails.first)}'
              : '$sent invitations sent')
          : '${sent > 0 ? '$sent sent. ' : ''}${errors.first}');
}

Future<void> _memberAction(BuildContext context, Team team, String action, String uid) async {
  final store = TeamStore.instance;
  final name = team.nameOf(uid);
  switch (action) {
    case 'message':
      final email = team.members[uid]?.email ?? '';
      openChatWith(context, Contact(uid, name, email, [team.id]));
      break;
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

/// 💬 next to a teammate: opens our direct chat (a request the first time).
Widget _messageButton(BuildContext context, Team team, String me, String uid) => uid == me
    ? const SizedBox.shrink()
    : IconButton(
        tooltip: 'Message ${team.nameOf(uid)}',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
        onPressed: () => _memberAction(context, team, 'message', uid),
        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 21, color: AppColors.primary),
      );

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
          _messageButton(context, team, me, uid),
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

  const _DoneChart({required this.doneByDay, required this.color});

  static const height = 140.0;
  static const bare = false;

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
