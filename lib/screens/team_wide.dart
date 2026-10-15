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
      3 => _WideOverview(team: team, tasks: tasks),
      _ => TeamBoard(team: team, tasks: tasks, padding: const EdgeInsets.only(bottom: 20)),
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
                Row(
                  children: [
                    if (Navigator.of(context).canPop()) ...[
                      IconButton(
                        tooltip: 'All teams',
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 6),
                    ],
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
                    if (store.canCreateTask(team))
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
                    labels: [
                      'Board',
                      'List',
                      'Members (${team.memberIds.length})',
                      if (admin) 'Overview',
                    ],
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

  // ------------------------------------------------------------------ list

  Widget _wideList(BuildContext context, Team team, List<TaskItem> tasks, String me) {
    final active = tasks.where((t) => !t.isCancelled).toList();
    final q = _search.trim().toLowerCase();
    final shown = _filtered(tasks, me)
        .where((t) =>
            !t.isCancelled &&
            (q.isEmpty ||
                t.title.toLowerCase().contains(q) ||
                t.description.toLowerCase().contains(q)))
        .toList();
    int count(_Filter f) => switch (f) {
          _Filter.all => active.length,
          _Filter.mine => active.where((t) => t.assigneeId == me).length,
          _Filter.pending => active.where((t) => t.status == TaskStatus.pending).length,
          _Filter.done => active.where((t) => t.isCompleted).length,
        };
    final now = DateTime.now();
    const head = TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final f in _Filter.values) ...[
              FilterPill(
                label: '${switch (f) {
                  _Filter.all => 'All',
                  _Filter.mine => 'Mine',
                  _Filter.pending => 'Pending',
                  _Filter.done => 'Done',
                }} (${count(f)})',
                selected: _filter == f,
                onTap: () => _update(() => _filter = f),
              ),
              const SizedBox(width: 10),
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
    return InkWell(
      onTap: () => openTaskRef(context, ref),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Align(
                alignment: Alignment.centerLeft,
                child: TickBox(
                    value: t.isCompleted,
                    onChanged: ref.canComplete ? (v) => ref.setCompleted(v) : null),
              ),
            ),
            Expanded(
              flex: 5,
              child: Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.isCompleted ? AppColors.textMuted : AppColors.text,
                    decoration: t.isCompleted ? TextDecoration.lineThrough : null,
                  )),
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
  final int selected;
  final ValueChanged<int> onSelect;
  const _SegTabs({required this.labels, required this.selected, required this.onSelect});

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
          for (var i = 0; i < labels.length; i++)
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
                child: Text(labels[i],
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: i == selected ? Colors.white : AppColors.text)),
              ),
            ),
        ],
      ),
    );
  }
}

// ================================================================= members

class _WideMembers extends StatelessWidget {
  final Team team;
  final String me;
  const _WideMembers({required this.team, required this.me});

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    final admin = team.isAdmin(me);
    final invites = store.sentInvites[team.id] ?? const <TeamInvite>[];
    final managers = team.managerIds.length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        DashCard(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              if (admin) ...[
                Expanded(
                  flex: 4,
                  child: PrimaryButton(
                    label: 'Add person by email',
                    icon: Icons.person_add_alt_1_rounded,
                    onPressed: () => showInviteDialog(context, team),
                  ),
                ),
                const _VDivider(),
              ],
              Expanded(
                flex: 3,
                child: _MiniStat(
                    icon: Icons.groups_rounded,
                    color: AppColors.primary,
                    value: team.memberIds.length,
                    label: 'Team members'),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 3,
                child: admin
                    ? _MiniStat(
                        icon: Icons.person_add_alt_1_rounded,
                        color: AppColors.warning,
                        value: invites.length,
                        label: 'Pending invites')
                    : _MiniStat(
                        icon: Icons.manage_accounts_rounded,
                        color: AppColors.primary,
                        value: managers,
                        label: managers == 1 ? 'Manager' : 'Managers'),
              ),
              const SizedBox(width: 14),
              const Expanded(
                flex: 3,
                child: _MiniStat(
                    icon: Icons.workspace_premium_rounded,
                    color: AppColors.purple,
                    value: 1,
                    label: 'Owner'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        DashCard(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Team members (${team.memberIds.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              for (final uid in team.sortedMemberIds) _memberRow(context, uid),
            ],
          ),
        ),
        if (admin && invites.isNotEmpty) ...[
          const SizedBox(height: 18),
          DashCard(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Waiting to accept (${invites.length})',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                for (final i in invites)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.warningLight,
                          child: Icon(Icons.hourglass_top_rounded, color: AppColors.warning),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(i.email, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                  'Invited by ${i.invitedByName.isEmpty ? 'a manager' : i.invitedByName}',
                                  style:
                                      const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        _BoxButton(
                          tooltip: 'Cancel invitation',
                          icon: Icons.close_rounded,
                          onTap: () => store.cancelInvite(i),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        const Text(
          'Owner: everything. Managers: add people and create/assign tasks. '
          'Members: see the team and mark their own tasks done.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
        ),
      ],
    );
  }

  Widget _memberRow(BuildContext context, String uid) {
    final role = team.roleOf(uid) ?? TeamRole.member;
    final info = team.members[uid];
    final isMe = uid == me;
    final pending = TeamStore.instance
        .tasksOf(team.id)
        .where((t) => t.assigneeId == uid && t.status == TaskStatus.pending)
        .length;
    final actions = _memberMenu(team, me, uid);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? AppColors.primaryLight.withAlpha(120) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Avatar(name: team.nameOf(uid), size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isMe ? '${team.nameOf(uid)} (you)' : team.nameOf(uid),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                if (info != null && info.email.isNotEmpty)
                  Text(info.email,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ],
            ),
          ),
          RoleChip(role: role),
          if (pending > 0) ...[
            const SizedBox(width: 16),
            Container(width: 1, height: 28, color: AppColors.border),
            const SizedBox(width: 16),
            const Icon(Icons.schedule_rounded, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Text('$pending pending', style: const TextStyle(color: AppColors.text)),
          ],
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: actions.isEmpty
                ? null
                : PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (a) => _memberAction(context, team, a, uid),
                    itemBuilder: (_) => actions,
                  ),
          ),
        ],
      ),
    );
  }
}

// ================================================================ overview

class _WideOverview extends StatelessWidget {
  final Team team;
  final List<TaskItem> tasks;
  const _WideOverview({required this.team, required this.tasks});

  @override
  Widget build(BuildContext context) {
    final st = TeamStats.compute(team, tasks, DateTime.now());
    final color = Color(team.color);
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        Row(
          children: [
            _BigStat(
                icon: Icons.description_outlined,
                color: AppColors.warning,
                value: st.pending,
                label: 'Pending'),
            const SizedBox(width: 16),
            _BigStat(
                icon: Icons.error_outline_rounded,
                color: AppColors.danger,
                value: st.overdue,
                label: 'Overdue'),
            const SizedBox(width: 16),
            _BigStat(
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
                value: st.doneThisWeek,
                label: 'Done this week'),
          ],
        ),
        const SizedBox(height: 16),
        DashCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('${st.done} of ${st.total} tasks done',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${(st.progress * 100).round()}%',
                      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18)),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: st.progress,
                  minHeight: 10,
                  color: color,
                  backgroundColor: color.withAlpha(30),
                ),
              ),
              if (st.unassigned > 0) ...[
                const SizedBox(height: 10),
                Text('${st.unassigned} task(s) not assigned to anyone',
                    style: const TextStyle(color: AppColors.textMuted)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: DashCard(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DoneChart(doneByDay: st.doneByDay, color: color, height: 220, bare: true),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => openWeeklyReport(context, team),
                      icon: const Icon(Icons.summarize_outlined),
                      label: const Text('Weekly report (share on WhatsApp)'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DashCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('People',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        for (final m in st.members) _MemberLoad(team: team, stats: m),
                      ],
                    ),
                  ),
                  if (st.overdueTasks.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    DashCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Overdue',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          for (final t in st.overdueTasks)
                            TaskTile(
                              task: t,
                              teamTask: true,
                              onTap: () => openTeamTask(context, team, t),
                              trailing: AssigneeBadge(team: team, task: t),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================ small parts

class _VDivider extends StatelessWidget {
  const _VDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 48,
        margin: const EdgeInsets.symmetric(horizontal: 22),
        color: AppColors.border,
      );
}

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

class _BoxButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _BoxButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: _BoxIcon(icon: icon),
        ),
      );
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int value;
  final String label;
  const _MiniStat(
      {required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEF1F6)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color.withAlpha(30),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$value', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _BigStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int value;
  final String label;
  const _BigStat(
      {required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withAlpha(40)),
            gradient: LinearGradient(
              colors: [color.withAlpha(28), color.withAlpha(10)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: color.withAlpha(36),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(width: 18),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$value',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: color)),
                  Text(label, style: const TextStyle(fontSize: 15, color: AppColors.text)),
                ],
              ),
            ],
          ),
        ),
      );
}
