part of 'team_screen.dart';

// Laptop / big screen layout of a team (phones use the tabbed layout in
// team_screen.dart). Header, pill tabs, then Tasks (summary, filters, search,
// board or list), Members (stats, people, invitations) or Overview.

extension _WideTeam on _TeamScreenState {
  Widget _buildWide(BuildContext context, Team team) {
    final store = TeamStore.instance;
    final me = store.uid ?? '';
    final admin = team.isAdmin(me);
    final owner = team.ownerId == me;
    final tasks = store.tasksOf(team.id);
    final active = tasks.where((t) => !t.isCancelled).length;
    // 0 board, 1 list, 2 members, 3 overview (owner/managers).
    final tab = (!admin && _wideTab == 3) ? 0 : _wideTab;
    final color = Color(team.color);

    final Widget content = switch (tab) {
      1 => _wideList(context, team, tasks, me),
      2 => _WideMembers(team: team, me: me),
      3 => _WideOverview(
          team: team,
          tasks: tasks,
          days: _overviewDays,
          onOpenList: (f) => _update(() {
            _filter = f;
            _wideTab = 1;
          }),
          onOpenMembers: () => _update(() => _wideTab = 2),
        ),
      _ => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _mineBar(team, tasks, me, list: false),
            const SizedBox(height: 14),
            Expanded(
              child: TeamBoard(
                  team: team,
                  tasks: _searched(_filter == _Filter.mine
                      ? tasks.where((t) => t.assigneeId == me).toList()
                      : tasks),
                  padding: const EdgeInsets.only(bottom: 20)),
            ),
          ],
        ),
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      body: DetailPanelHost(
        panelBuilder: buildTaskPanel,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ------------------------------------------------ header
                if (Navigator.of(context).canPop())
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: TextButton.styleFrom(foregroundColor: AppColors.text),
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      label: const Text('Back to teams', style: TextStyle(fontSize: 15)),
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: color.withAlpha(28), borderRadius: BorderRadius.circular(20)),
                      child: Icon(Icons.groups_rounded, color: color, size: 40),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Flexible(
                              child: Text(team.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 12),
                            RoleChip(role: team.roleOf(me) ?? TeamRole.member),
                          ]),
                          const SizedBox(height: 4),
                          Text(
                              '${team.memberIds.length} ${team.memberIds.length == 1 ? 'member' : 'members'}'
                              '  •  $active ${active == 1 ? 'task' : 'tasks'}',
                              style: const TextStyle(fontSize: 17, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    if (tab == 3) ...[
                      _PeriodMenu(
                          days: _overviewDays, onChanged: (d) => _update(() => _overviewDays = d)),
                      const SizedBox(width: 12),
                    ],
                    if (tab == 2 && admin)
                      FilledButton.icon(
                        onPressed: () => showInviteDialog(context, team),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Invite member',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      )
                    else if (store.canCreateTask(team))
                      FilledButton.icon(
                        onPressed: () => showCreateTask(context, team: team),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New Task',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    const SizedBox(width: 12),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      onSelected: (a) async {
                        if (a == 'invite') {
                          await showInviteDialog(context, team);
                        } else {
                          await _onMenu(a, team);
                        }
                      },
                      itemBuilder: (_) => [
                        if (admin) const PopupMenuItem(value: 'invite', child: Text('Add person')),
                        if (admin)
                          const PopupMenuItem(value: 'report', child: Text('Weekly report')),
                        if (owner) const PopupMenuItem(value: 'edit', child: Text('Edit team')),
                        if (!owner) const PopupMenuItem(value: 'leave', child: Text('Leave team')),
                        if (owner)
                          const PopupMenuItem(
                              value: 'delete',
                              child:
                                  Text('Delete team', style: TextStyle(color: AppColors.danger))),
                      ],
                      child: const _BoxIcon(icon: Icons.more_horiz_rounded, size: 52),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // ------------------------------------------------- tabs
                Align(
                  alignment: Alignment.centerLeft,
                  child: _SegTabs(
                    labels: const ['Board', 'List', 'Members', 'Overview'],
                    icons: const [
                      Icons.view_kanban_outlined,
                      Icons.format_list_bulleted_rounded,
                      Icons.groups_outlined,
                      Icons.bar_chart_rounded,
                    ],
                    count: admin ? 4 : 3,
                    selected: tab,
                    onSelect: (i) => _update(() => _wideTab = i),
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(child: content),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- filters

  List<TaskItem> _searched(List<TaskItem> tasks) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return tasks;
    return tasks
        .where((t) => t.title.toLowerCase().contains(q) || t.description.toLowerCase().contains(q))
        .toList();
  }

  /// All | Assigned to me (+ the overview's Pending / Done on the list),
  /// search, and a note when only my tasks are shown.
  Widget _mineBar(Team team, List<TaskItem> tasks, String me, {required bool list}) {
    final active = tasks.where((t) => !t.isCancelled).toList();
    final mine = active.where((t) => t.assigneeId == me).length;
    final filter =
        !list && (_filter == _Filter.pending || _filter == _Filter.done) ? _Filter.all : _filter;
    Widget pill(_Filter f, String label) => FilterPill(
          label: label,
          selected: filter == f,
          onTap: () => _update(() => _filter = f),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            pill(_Filter.all, 'All (${active.length})'),
            const SizedBox(width: 10),
            pill(_Filter.mine, 'Assigned to me ($mine)'),
            if (list && (filter == _Filter.pending || filter == _Filter.done)) ...[
              const SizedBox(width: 10),
              InputChip(
                label: Text(filter == _Filter.pending
                    ? 'Pending (${active.where((t) => t.status == TaskStatus.pending).length})'
                    : 'Done (${active.where((t) => t.isCompleted).length})'),
                selected: true,
                showCheckmark: false,
                onDeleted: () => _update(() => _filter = _Filter.all),
              ),
            ],
            const Spacer(),
            SizedBox(
              width: 260,
              height: 44,
              child: TextField(
                onChanged: (v) => _update(() => _search = v),
                decoration: fieldDecoration('Search tasks...', icon: Icons.search_rounded)
                    .copyWith(contentPadding: EdgeInsets.zero),
              ),
            ),
          ],
        ),
        if (filter == _Filter.mine) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withAlpha(150),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Avatar(name: team.nameOf(me), size: 40, uid: me),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      mine == 0
                          ? 'Nothing is assigned to you in ${team.name}'
                          : '$mine ${mine == 1 ? 'task' : 'tasks'} assigned to you',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  Text(
                      list
                          ? 'Only your tasks are listed. Clear the filter to see the whole team.'
                          : 'The board shows only your tasks, in the column each one is in.',
                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                ]),
              ),
              OutlinedButton.icon(
                onPressed: () => _update(() => _filter = _Filter.all),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Clear filter'),
              ),
            ]),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------------ list

  Widget _wideList(BuildContext context, Team team, List<TaskItem> tasks, String me) {
    final q = _search.trim().toLowerCase();
    final shown = _filtered(tasks, me)
        .where((t) =>
            !t.isCancelled &&
            (q.isEmpty ||
                t.title.toLowerCase().contains(q) ||
                t.description.toLowerCase().contains(q)))
        .toList();
    final now = DateTime.now();
    const head = TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _mineBar(team, tasks, me, list: true),
        const SizedBox(height: 14),
        Expanded(
          child: DashCard(
            padding: EdgeInsets.zero,
            child: shown.isEmpty
                ? ListView(children: [
                    EmptyState(
                      icon: Icons.inbox_outlined,
                      title: tasks.isEmpty ? 'No tasks yet' : 'Nothing here',
                      subtitle: tasks.isEmpty
                          ? 'Use New Task to add one and assign it to someone.'
                          : 'Try another filter or search.',
                    ),
                  ])
                : ListView(
                    padding: const EdgeInsets.only(bottom: 20),
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 14, 8, 12),
                        child: Row(children: [
                          SizedBox(width: 40),
                          Expanded(flex: 5, child: Text('Title', style: head)),
                          SizedBox(width: 120, child: Text('Due Date', style: head)),
                          SizedBox(width: 110, child: Text('Priority', style: head)),
                          SizedBox(width: 120, child: Text('Status', style: head)),
                          Expanded(flex: 2, child: Text('Assignee', style: head)),
                          SizedBox(width: 44),
                        ]),
                      ),
                      for (final t in shown) ...[
                        const Divider(height: 1),
                        _ListRow(team: team, task: t, now: now),
                      ],
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _ListRow extends StatelessWidget {
  final Team team;
  final TaskItem task;
  final DateTime now;
  const _ListRow({required this.team, required this.task, required this.now});

  @override
  Widget build(BuildContext context) {
    final t = task;
    final ref = TaskRef(t, team);
    final assignee = t.assigneeId == null ? 'Unassigned' : team.nameOf(t.assigneeId);
    final mine = t.assigneeId != null && t.assigneeId == TeamStore.instance.uid;
    return InkWell(
      onTap: () => openTaskRef(context, ref),
      child: Container(
        // My tasks: blue bar on the left and a light blue row.
        decoration: mine
            ? BoxDecoration(
                color: AppColors.primaryLight.withAlpha(90),
                border: const Border(left: BorderSide(color: AppColors.primary, width: 4)),
              )
            : null,
        padding: EdgeInsets.fromLTRB(mine ? 12 : 16, 8, 8, 8),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Align(
                alignment: Alignment.centerLeft,
                child: TickBox(
                    value: t.isCompleted,
                    onChanged: ref.canComplete ? (v) => tickTask(context, ref, v) : null),
              ),
            ),
            Expanded(
              flex: 5,
              child: Row(children: [
                Flexible(
                  child: Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: mine ? FontWeight.w700 : FontWeight.w600,
                        color: t.isCompleted ? AppColors.textMuted : AppColors.text,
                        decoration: t.isCompleted ? TextDecoration.lineThrough : null,
                      )),
                ),
                if (mine) ...[const SizedBox(width: 10), const AssignedToYouChip()],
              ]),
            ),
            SizedBox(
              width: 120,
              child: Text(dueLabel(t, now),
                  style: TextStyle(
                      color: dueIsUrgent(t, now) ? AppColors.danger : const Color(0xFF4B5563))),
            ),
            SizedBox(
                width: 110,
                child: Align(
                    alignment: Alignment.centerLeft, child: PriorityChip(priority: t.priority))),
            SizedBox(
                width: 120,
                child: Align(alignment: Alignment.centerLeft, child: StatusChip(task: t))),
            Expanded(
              flex: 2,
              child: Row(children: [
                Avatar(name: assignee, size: 30),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(t.assigneeId == TeamStore.instance.uid ? 'You' : assignee,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),
            SizedBox(width: 44, child: TaskActionsMenu(ref: ref)),
          ],
        ),
      ),
    );
  }
}

/// Board | List | Members | Overview.
class _SegTabs extends StatelessWidget {
  final List<String> labels;
  final List<IconData> icons;

  /// How many of the tabs to show (Overview is for owner/managers).
  final int count;
  final int selected;
  final ValueChanged<int> onSelect;
  const _SegTabs({
    required this.labels,
    required this.icons,
    required this.count,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 13),
                decoration: BoxDecoration(
                  color: i == selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icons[i], size: 21, color: i == selected ? Colors.white : AppColors.text),
                  const SizedBox(width: 10),
                  Text(labels[i],
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: i == selected ? Colors.white : AppColors.text)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

// ================================================================= members

class _WideMembers extends StatefulWidget {
  final Team team;
  final String me;
  const _WideMembers({required this.team, required this.me});

  @override
  State<_WideMembers> createState() => _WideMembersState();
}

class _WideMembersState extends State<_WideMembers> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final team = widget.team;
    final me = widget.me;
    final store = TeamStore.instance;
    final admin = team.isAdmin(me);
    final invites = store.sentInvites[team.id] ?? const <TeamInvite>[];
    final tasks = store.tasksOf(team.id);
    final q = _q.trim().toLowerCase();
    bool match(String name, String email) =>
        q.isEmpty || name.toLowerCase().contains(q) || email.toLowerCase().contains(q);
    final people = [
      for (final uid in team.sortedMemberIds)
        if (match(team.nameOf(uid), team.members[uid]?.email ?? '')) uid,
    ];
    final waiting = [
      for (final i in invites)
        if (match(i.email, i.email)) i
    ];
    const head = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151));

    Widget row({
      required Widget avatar,
      required Widget name,
      required Widget role,
      required String email,
      required String tasksText,
      required Widget status,
      required Widget action,
    }) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          child: Row(children: [
            avatar,
            const SizedBox(width: 14),
            Expanded(flex: 4, child: name),
            Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: role)),
            Expanded(
                flex: 4,
                child: Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, color: Color(0xFF4B5563)))),
            SizedBox(
                width: 80,
                child: Text(tasksText,
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 15))),
            const SizedBox(width: 20),
            SizedBox(width: 130, child: Align(alignment: Alignment.centerLeft, child: status)),
            SizedBox(width: 130, child: Align(alignment: Alignment.center, child: action)),
          ]),
        );

    Widget statusChip(String text, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: c.withAlpha(24), borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
          ]),
        );

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        Row(children: [
          Expanded(
            child: _TintStat(
                icon: Icons.groups_rounded,
                color: AppColors.primary,
                value: team.memberIds.length,
                label: 'Total members'),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: _TintStat(
                icon: Icons.person_add_alt_outlined,
                color: AppColors.danger,
                value: invites.length,
                label: 'Pending invites'),
          ),
        ]),
        const SizedBox(height: 20),
        DashCard(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Team Members',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                        SizedBox(height: 4),
                        Text('Manage team members, roles and access permissions.',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 14.5)),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 300,
                    height: 46,
                    child: TextField(
                      onChanged: (v) => setState(() => _q = v),
                      decoration: fieldDecoration('Search members...', icon: Icons.search_rounded)
                          .copyWith(contentPadding: EdgeInsets.zero),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FB), borderRadius: BorderRadius.circular(12)),
                child: row(
                  avatar: const SizedBox(width: 0),
                  name: const Text('Name', style: head),
                  role: const Text('Role', style: head),
                  email: 'Email',
                  tasksText: 'Tasks',
                  status: const Text('Status', style: head),
                  action: const Text('Actions', style: head),
                ),
              ),
              for (final uid in people) ...[
                row(
                  avatar: Avatar(
                      name: team.nameOf(uid),
                      size: 46,
                      color: uid == me ? AppColors.primary : AppColors.purple),
                  name: Text(uid == me ? '${team.nameOf(uid)} (you)' : team.nameOf(uid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  role: RoleChip(role: team.roleOf(uid) ?? TeamRole.member),
                  email: team.members[uid]?.email ?? '',
                  tasksText:
                      '${tasks.where((t) => t.assigneeId == uid && t.status == TaskStatus.pending).length}',
                  status: statusChip('Active', AppColors.success),
                  action: Builder(builder: (context) {
                    final actions = _memberMenu(team, me, uid);
                    return Row(mainAxisSize: MainAxisSize.min, children: [
                      _messageButton(context, team, me, uid),
                      if (actions.isNotEmpty)
                        PopupMenuButton<String>(
                          tooltip: 'Actions',
                          icon: const Icon(Icons.more_vert_rounded),
                          onSelected: (a) => _memberAction(context, team, a, uid),
                          itemBuilder: (_) => actions,
                        ),
                    ]);
                  }),
                ),
                const Divider(height: 1, indent: 12, endIndent: 12),
              ],
              if (admin)
                for (final i in waiting) ...[
                  row(
                    avatar: const CircleAvatar(
                      radius: 23,
                      backgroundColor: AppColors.warningLight,
                      child: Icon(Icons.hourglass_top_rounded, color: AppColors.warning),
                    ),
                    name: Text(i.email.split('@').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    role: const Text('—', style: TextStyle(color: AppColors.textMuted)),
                    email: i.email,
                    tasksText: '—',
                    status: statusChip('Invited', AppColors.warning),
                    action: TextButton(
                      onPressed: () => store.cancelInvite(i),
                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const Divider(height: 1, indent: 12, endIndent: 12),
                ],
              if (admin)
                row(
                  avatar: Container(
                    width: 46,
                    height: 46,
                    decoration:
                        const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
                    child: const Icon(Icons.person_add_alt_outlined, color: AppColors.primary),
                  ),
                  name: const Text('Invite new member',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  role: const Text('—', style: TextStyle(color: AppColors.textMuted)),
                  email: '—',
                  tasksText: '—',
                  status: const Text('—', style: TextStyle(color: AppColors.textMuted)),
                  action: FilledButton.tonal(
                    onPressed: () => showInviteDialog(context, team),
                    child: const Text('Send invite'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Owner: everything. Managers: add people and create/assign tasks. '
          'Members: see the team, add their own tasks and finish the ones given to them.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _TintStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int value;
  final String label;
  final VoidCallback? onTap;
  const _TintStat(
      {required this.icon,
      required this.color,
      required this.value,
      required this.label,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(12),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withAlpha(45)),
          ),
          child: Row(children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                  color: color.withAlpha(26), borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$value',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: color)),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, color: Color.lerp(color, Colors.black, 0.3))),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right_rounded, color: AppColors.text),
          ]),
        ),
      ),
    );
  }
}

// ================================================================ overview

/// One line of the team's recent activity, from the tasks' history.
class _TeamEvent {
  final DateTime at;
  final String? by;
  final String verb;
  final String object;
  final IconData icon;
  final Color color;
  const _TeamEvent(this.at, this.by, this.verb, this.object, this.icon, this.color);
}

List<_TeamEvent> _teamEvents(Team team, List<TaskItem> tasks, List<TeamInvite> invites,
    {int limit = 6}) {
  final out = <_TeamEvent>[];
  for (final t in tasks) {
    for (final e in t.historyOrDerived) {
      final (verb, icon, color) = switch (e.kind) {
        HistoryKind.created => ('created a task', Icons.add_rounded, AppColors.success),
        HistoryKind.done => ('completed a task', Icons.check_rounded, AppColors.success),
        HistoryKind.approved => ('approved a task', Icons.verified_outlined, AppColors.success),
        HistoryKind.changes => ('asked for changes on', Icons.replay_rounded, AppColors.warning),
        HistoryKind.submitted => ('sent for approval', Icons.send_outlined, AppColors.primary),
        HistoryKind.moveAsked => (
            'asked to move a task',
            Icons.event_repeat_rounded,
            AppColors.purple
          ),
        HistoryKind.moveOk => ('moved a task date', Icons.event_repeat_rounded, AppColors.purple),
        HistoryKind.reopened => ('reopened a task', Icons.undo_rounded, AppColors.warning),
        HistoryKind.cancelled => ('cancelled a task', Icons.close_rounded, AppColors.danger),
        HistoryKind.restored => ('restored a task', Icons.undo_rounded, AppColors.primary),
        HistoryKind.assigned => (
            'assigned a task to ${e.to == null ? 'someone' : team.nameOf(e.to)}',
            Icons.person_add_alt_outlined,
            AppColors.purple
          ),
        HistoryKind.unassigned => (
            'removed the assignee',
            Icons.person_off_outlined,
            AppColors.textMuted
          ),
        HistoryKind.stage => (
            e.to == TaskStage.boardDone
                ? 'completed a task'
                : 'moved a task to ${TaskStage.label(e.to ?? '').toLowerCase()}',
            Icons.swap_horiz_rounded,
            const Color(0xFFEA7A0C)
          ),
        _ => ('updated a task', Icons.edit_outlined, AppColors.primary),
      };
      out.add(_TeamEvent(e.at, e.by, verb, t.title, icon, color));
    }
  }
  for (final i in invites) {
    out.add(_TeamEvent(i.createdAt, i.invitedBy, 'invited a new member', i.email,
        Icons.person_add_alt_outlined, AppColors.purple));
  }
  out.sort((a, b) => b.at.compareTo(a.at));
  return out.length > limit ? out.sublist(0, limit) : out;
}

String _since(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} ${diff.inHours == 1 ? 'hour' : 'hours'} ago';
  return '${diff.inDays} ${diff.inDays == 1 ? 'day' : 'days'} ago';
}

class _WideOverview extends StatelessWidget {
  final Team team;
  final List<TaskItem> tasks;

  /// Only tasks due, made or finished in the last [days] days (0 = all).
  final int days;
  final void Function(_Filter filter) onOpenList;
  final VoidCallback onOpenMembers;
  const _WideOverview({
    required this.team,
    required this.tasks,
    required this.days,
    required this.onOpenList,
    required this.onOpenMembers,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final from = days == 0 ? null : now.subtract(Duration(days: days));
    bool inRange(TaskItem t) =>
        from == null ||
        !t.startAt.isBefore(from) ||
        !t.createdAt.isBefore(from) ||
        (t.completedAt != null && !t.completedAt!.isBefore(from)) ||
        (t.status == TaskStatus.pending);
    final list = tasks.where((t) => !t.isCancelled && inRange(t)).toList();
    final done = list.where((t) => t.isCompleted).length;
    final open = list.where((t) => !t.isCompleted).toList();
    final overdue = open.where((t) => t.isOverdue).length;
    final todo = open.where((t) => t.stage == TaskStage.todo && !t.isOverdue).length;
    final doing = open.where((t) => t.stage == TaskStage.doing && !t.isOverdue).length;
    final review = open.where((t) => t.stage == TaskStage.review && !t.isOverdue).length;
    final total = list.length;
    int pct(int n) => total == 0 ? 0 : (n * 100 / total).round();
    final store = TeamStore.instance;
    final events = _teamEvents(team, tasks, store.sentInvites[team.id] ?? const [], limit: 6);
    final st = TeamStats.compute(team, list, now);

    Widget card(String title, Widget child, {VoidCallback? viewAll}) => DashCard(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                    child: Text(title,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                if (viewAll != null)
                  OutlinedButton(
                    onPressed: viewAll,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.border)),
                    child: const Text('View all'),
                  ),
              ]),
              const SizedBox(height: 16),
              child,
            ],
          ),
        );

    Widget legend(Color c, int n, String label) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Container(
                width: 14, height: 14, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 14),
            SizedBox(
                width: 34,
                child:
                    Text('$n', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
            Text('${pct(n)}%', style: const TextStyle(fontSize: 16)),
          ]),
        );

    final status = card(
      'Task Status',
      Row(children: [
        SizedBox(
          width: 200,
          height: 200,
          child: DonutRing(
            parts: [
              (done, const Color(0xFF22C55E)),
              (doing, AppColors.primary),
              (todo, const Color(0xFF93C5FD)),
              (review, AppColors.warning),
              (overdue, const Color(0xFFF87171)),
            ],
            total: total,
            center: '$total',
            caption: 'Total Tasks',
            stroke: 26,
          ),
        ),
        const SizedBox(width: 36),
        Expanded(
          child: Column(children: [
            legend(const Color(0xFF22C55E), done, 'Completed'),
            legend(AppColors.primary, doing, 'In Progress'),
            legend(const Color(0xFF93C5FD), todo, 'To Do'),
            legend(AppColors.warning, review, 'Review'),
            legend(const Color(0xFFF87171), overdue, 'Overdue'),
          ]),
        ),
      ]),
    );

    int byPriority(Priority p) => list.where((t) => t.priority == p).length;
    final maxP = [for (final p in Priority.values) byPriority(p)].fold(1, (a, b) => b > a ? b : a);
    Widget bar(String label, int n, Color c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 16))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                    value: n / maxP,
                    minHeight: 22,
                    color: c,
                    backgroundColor: const Color(0xFFEFF2F6)),
              ),
            ),
            SizedBox(
                width: 40,
                child: Text('$n',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          ]),
        );
    final priority = card(
      'Tasks by Priority',
      Column(children: [
        bar('High', byPriority(Priority.high), const Color(0xFFF87171)),
        bar('Medium', byPriority(Priority.medium), const Color(0xFFFBBF24)),
        bar('Low', byPriority(Priority.low), const Color(0xFF34D399)),
      ]),
    );

    final activity = card(
      'Recent Activity',
      events.isEmpty
          ? const Text('Nothing yet.', style: TextStyle(color: AppColors.textMuted))
          : Column(children: [
              for (final (i, e) in events.indexed) ...[
                if (i > 0) const Divider(height: 18),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: e.color.withAlpha(26), shape: BoxShape.circle),
                    child: Icon(e.icon, color: e.color, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(TextSpan(children: [
                          TextSpan(
                              text: e.by == null
                                  ? 'Someone'
                                  : (e.by == store.uid ? 'You' : team.nameOf(e.by)),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: ' ${e.verb}'),
                        ])),
                        Text(e.object,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  Text(_since(e.at),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ]),
              ],
            ]),
    );

    final workload = card(
      'Team Workload',
      Column(children: [
        for (final m in st.members)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              Avatar(name: team.nameOf(m.uid), size: 38, uid: m.uid),
              const SizedBox(width: 12),
              Expanded(
                  flex: 4,
                  child: Text(m.uid == store.uid ? 'You' : team.nameOf(m.uid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15))),
              SizedBox(
                  width: 80,
                  child: Text('${m.total} ${m.total == 1 ? 'task' : 'tasks'}',
                      style: const TextStyle(color: Color(0xFF4B5563)))),
              Expanded(
                flex: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                      value: m.progress,
                      minHeight: 10,
                      color: AppColors.primary,
                      backgroundColor: const Color(0xFFEFF2F6)),
                ),
              ),
              SizedBox(
                  width: 52,
                  child: Text('${(m.progress * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ),
      ]),
      viewAll: onOpenMembers,
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        Row(children: [
          Expanded(
              child: _TintStat(
                  icon: Icons.assignment_outlined,
                  color: AppColors.primary,
                  value: todo,
                  label: 'To Do',
                  onTap: () => onOpenList(_Filter.pending))),
          const SizedBox(width: 18),
          Expanded(
              child: _TintStat(
                  icon: Icons.check_box_rounded,
                  color: AppColors.success,
                  value: done,
                  label: 'Completed',
                  onTap: () => onOpenList(_Filter.done))),
          const SizedBox(width: 18),
          Expanded(
              child: _TintStat(
                  icon: Icons.timelapse_rounded,
                  color: AppColors.primary,
                  value: doing,
                  label: 'In Progress',
                  onTap: () => onOpenList(_Filter.pending))),
          const SizedBox(width: 18),
          Expanded(
              child: _TintStat(
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.danger,
                  value: overdue,
                  label: 'Overdue',
                  onTap: () => onOpenList(_Filter.pending))),
        ]),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                flex: 11, child: Column(children: [status, const SizedBox(height: 18), priority])),
            const SizedBox(width: 18),
            Expanded(
                flex: 9, child: Column(children: [activity, const SizedBox(height: 18), workload])),
          ],
        ),
      ],
    );
  }
}

// ============================================================ small parts

class _BoxIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  const _BoxIcon({required this.icon, this.size = 44});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 22),
      );
}

/// "Last 7 days" / "Last 30 days" / "All time" for the Overview.
class _PeriodMenu extends StatelessWidget {
  final int days;
  final ValueChanged<int> onChanged;
  const _PeriodMenu({required this.days, required this.onChanged});

  static String label(int d) => d == 0 ? 'All time' : 'Last $d days';

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Period',
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final d in const [7, 30, 0])
          CheckedPopupMenuItem(value: d, checked: d == days, child: Text(label(d))),
      ],
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.calendar_today_outlined, size: 19),
          const SizedBox(width: 10),
          Text(label(days), style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 14),
          const Icon(Icons.expand_more_rounded),
        ]),
      ),
    );
  }
}
