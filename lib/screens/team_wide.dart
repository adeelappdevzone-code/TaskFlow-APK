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
    final tab = (!admin && _wideTab == 2) ? 0 : _wideTab;

    Widget content = switch (tab) {
      1 => _WideMembers(team: team, me: me),
      2 => _WideOverview(team: team, tasks: tasks),
      _ => _wideTasks(context, team, tasks, me),
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: tab == 0 && TeamStore.instance.canCreateTask(team)
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TaskFormScreen(team: team)),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Task'),
            )
          : null,
      body: DetailPanelHost(
        panelBuilder: buildTaskPanel,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ------------------------------------------------ header
                Row(
                  children: [
                    if (Navigator.of(context).canPop()) ...[
                      IconButton(
                        tooltip: 'Back',
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(team.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                    ),
                    if (admin)
                      _BoxButton(
                        tooltip: 'Weekly report',
                        icon: Icons.summarize_outlined,
                        onTap: () => openWeeklyReport(context, team),
                      ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      onSelected: (a) => _onMenu(a, team),
                      itemBuilder: (_) => [
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
                      child: const _BoxIcon(icon: Icons.more_vert_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // ------------------------------------------------- tabs
                Align(
                  alignment: Alignment.centerLeft,
                  child: _PillTabs(
                    labels: [
                      'Tasks (${tasks.where((t) => !t.isCancelled).length})',
                      'Members (${team.memberIds.length})',
                      if (admin) 'Overview',
                    ],
                    selected: tab,
                    onSelect: (i) => _update(() => _wideTab = i),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(child: content),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- tasks

  Widget _wideTasks(BuildContext context, Team team, List<TaskItem> tasks, String me) {
    final store = TeamStore.instance;
    final active = tasks.where((t) => !t.isCancelled).toList();
    final done = active.where((t) => t.isCompleted).length;
    int inStage(String s) => active.where((t) => !t.isCompleted && t.stage == s).length;
    final q = _search.trim().toLowerCase();
    final shown = _filtered(tasks, me)
        .where((t) =>
            q.isEmpty ||
            t.title.toLowerCase().contains(q) ||
            t.description.toLowerCase().contains(q))
        .toList();
    int count(_Filter f) => switch (f) {
          _Filter.all => active.length,
          _Filter.mine => active.where((t) => t.assigneeId == me).length,
          _Filter.pending => active.where((t) => t.status == TaskStatus.pending).length,
          _Filter.done => done,
        };
    final color = Color(team.color);
    final progress = active.isEmpty ? 0.0 : done / active.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --------------------------------------------- summary card
        DashCard(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$done of ${active.length} tasks completed',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 8,
                              color: color,
                              backgroundColor: color.withAlpha(30),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text('${(progress * 100).round()}%',
                            style:
                                TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
                      ],
                    ),
                  ],
                ),
              ),
              const _VDivider(),
              _AvatarStack(team: team),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${team.memberIds.length} ${team.memberIds.length == 1 ? 'member' : 'members'}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Text('Active team',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                ],
              ),
              const _VDivider(),
              Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [
                  _Legend(color: AppColors.textMuted, text: '${inStage(TaskStage.todo)} To do'),
                  _Legend(color: AppColors.purple, text: '${inStage(TaskStage.doing)} In progress'),
                  _Legend(color: AppColors.warning, text: '${inStage(TaskStage.review)} Review'),
                  _Legend(color: AppColors.success, text: '$done Done'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // --------------------------------------- filters + search
        DashCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
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
              const SizedBox(width: 14),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    onChanged: (v) => _update(() => _search = v),
                    decoration: fieldDecoration('Search tasks...', icon: Icons.search_rounded)
                        .copyWith(contentPadding: const EdgeInsets.symmetric(vertical: 0)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              ViewToggle(
                board: _wideBoard,
                onChanged: (b) => _update(() => _wideBoard = b),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ------------------------------------------ board / list
        Expanded(
          child: _wideBoard
              ? TaskBoard(team: team, tasks: shown, padding: const EdgeInsets.only(bottom: 90))
              : (shown.isEmpty
                  ? ListView(children: [
                      EmptyState(
                        icon: Icons.inbox_outlined,
                        title: tasks.isEmpty ? 'No tasks yet' : 'Nothing here',
                        subtitle: tasks.isEmpty
                            ? 'Tap "+ Task" to create one and assign it to someone.'
                            : 'Try another filter or search.',
                      ),
                    ])
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 100),
                      children: [
                        for (final t in shown)
                          TaskTile(
                            task: t,
                            teamTask: true,
                            onTap: () => openTeamTask(context, team, t),
                            onToggle: store.canComplete(team, t)
                                ? () => store.setCompleted(team, t, !t.isCompleted)
                                : null,
                            trailing: AssigneeBadge(team: team, task: t),
                          ),
                      ],
                    )),
        ),
      ],
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
  const _BoxIcon({required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
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

class _PillTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  const _PillTabs({required this.labels, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF1F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
                decoration: BoxDecoration(
                  color: i == selected ? AppColors.primaryLight : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                      color: i == selected ? AppColors.primary.withAlpha(90) : Colors.transparent),
                ),
                child: Text(labels[i],
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: i == selected ? AppColors.primary : AppColors.text)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;
  const _Legend({required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13.5)),
        ],
      );
}

/// Up to three member initials overlapping, like a group photo.
class _AvatarStack extends StatelessWidget {
  final Team team;
  const _AvatarStack({required this.team});

  @override
  Widget build(BuildContext context) {
    final ids = team.sortedMemberIds.take(3).toList();
    return SizedBox(
      width: 40.0 + 26 * (ids.length - 1),
      height: 40,
      child: Stack(
        children: [
          for (var i = 0; i < ids.length; i++)
            Positioned(
              left: 26.0 * i,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: i == 0 ? AppColors.primary : AppColors.primaryLight,
                  child: Text(initials(team.nameOf(ids[i])),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: i == 0 ? Colors.white : AppColors.primary)),
                ),
              ),
            ),
        ],
      ),
    );
  }
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
