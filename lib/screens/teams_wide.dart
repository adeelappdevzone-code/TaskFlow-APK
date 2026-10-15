part of 'teams_screen.dart';

// Teams page on a laptop (wide screen): stats, search/sort, team cards,
// sent invitations and recent activity. Also the pieces the phone layout
// shares (totals, activity list, sent-invite rows, team menu).

/// Pending / overdue / done-this-week summed over all my teams.
class _Totals {
  int pending = 0;
  int overdue = 0;
  int doneThisWeek = 0;

  _Totals(List<Team> teams) {
    final store = TeamStore.instance;
    final now = DateTime.now();
    for (final t in teams) {
      final st = TeamStats.compute(t, store.tasksOf(t.id), now);
      pending += st.pending;
      overdue += st.overdue;
      doneThisWeek += st.doneThisWeek;
    }
  }
}

/// Open invitations sent by teams I manage, newest first.
List<TeamInvite> _sentInvites(String me) {
  final store = TeamStore.instance;
  return [
    for (final t in store.teams)
      if (t.isAdmin(me)) ...?store.sentInvites[t.id],
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

List<ActivityItem> _activity(String me, {int limit = 8}) {
  final store = TeamStore.instance;
  return recentActivity(
    teams: store.teams,
    tasksOf: store.tasksOf,
    invitesOf: (id) => store.sentInvites[id] ?? const [],
    me: me,
    limit: limit,
  );
}

String _ago(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'yesterday';
  return '${diff.inDays} days ago';
}

/// ⋮ menu of a team card.
Widget _teamMenu(BuildContext context, Team team, String me) {
  final owner = team.ownerId == me;
  final admin = team.isAdmin(me);
  return PopupMenuButton<String>(
    icon: const Icon(Icons.more_vert_rounded),
    onSelected: (a) async {
      final store = TeamStore.instance;
      switch (a) {
        case 'open':
          openTeam(context, team);
        case 'invite':
          await showInviteDialog(context, team);
        case 'report':
          openWeeklyReport(context, team);
        case 'leave':
          final ok = await confirmDialog(context,
              title: 'Leave ${team.name}?',
              message: 'You will no longer see this team or its tasks.',
              confirmLabel: 'Leave',
              danger: true);
          if (ok) store.leaveTeam(team);
        case 'delete':
          final ok = await confirmDialog(context,
              title: 'Delete ${team.name}?',
              message: 'The team and ALL its tasks will be deleted for everyone. '
                  'This cannot be undone.',
              confirmLabel: 'Delete team',
              danger: true);
          if (ok) store.deleteTeam(team);
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'open', child: Text('Open')),
      if (admin) const PopupMenuItem(value: 'invite', child: Text('Add person')),
      if (admin) const PopupMenuItem(value: 'report', child: Text('Weekly report')),
      if (!owner) const PopupMenuItem(value: 'leave', child: Text('Leave team')),
      if (owner)
        const PopupMenuItem(
            value: 'delete', child: Text('Delete team', style: TextStyle(color: AppColors.danger))),
    ],
  );
}

/// Member initials (up to 3) and a "+" to add someone (owner/managers).
class _MemberDots extends StatelessWidget {
  final Team team;
  final bool canInvite;
  const _MemberDots({required this.team, required this.canInvite});

  @override
  Widget build(BuildContext context) {
    final ids = team.sortedMemberIds;
    return Row(
      children: [
        for (final uid in ids.take(3)) ...[
          Avatar(name: team.nameOf(uid), size: 34),
          const SizedBox(width: 8),
        ],
        if (ids.length > 3) ...[
          Text('+${ids.length - 3}', style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(width: 8),
        ],
        if (canInvite)
          Tooltip(
            message: 'Add person',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => showInviteDialog(context, team),
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(color: Color(0xFFEDF1F7), shape: BoxShape.circle),
                child: const Icon(Icons.add_rounded, size: 20, color: AppColors.textMuted),
              ),
            ),
          ),
      ],
    );
  }
}

/// pending • overdue • done with coloured dots.
class _TeamLegend extends StatelessWidget {
  final TeamStats stats;
  const _TeamLegend({required this.stats});

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Text(t, style: const TextStyle(fontSize: 13)),
          ],
        );
    return Wrap(
      spacing: 22,
      runSpacing: 6,
      children: [
        dot(AppColors.warning, '${stats.pending} pending'),
        dot(AppColors.danger, '${stats.overdue} overdue'),
        dot(AppColors.success, '${stats.done} done'),
      ],
    );
  }
}

/// Row of an invitation I (or another manager) sent.
class _SentInviteRow extends StatelessWidget {
  final TeamInvite invite;
  final bool showTeam;
  const _SentInviteRow({required this.invite, this.showTeam = false});

  @override
  Widget build(BuildContext context) {
    final i = invite;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Avatar(name: i.email.split('@').first.replaceAll(RegExp(r'[._-]+'), ' '), size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  [
                    if (showTeam) i.teamName,
                    'Invited by ${i.invitedByName.isEmpty ? 'a manager' : i.invitedByName}',
                    _ago(i.createdAt),
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule_rounded, size: 15, color: AppColors.warning),
                SizedBox(width: 5),
                Text('Pending',
                    style: TextStyle(
                        color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (_) => TeamStore.instance.cancelInvite(i),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'cancel', child: Text('Cancel invitation')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final ActivityItem item;
  const _ActivityRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.kind) {
      ActivityKind.completed => (Icons.check_circle_rounded, AppColors.success),
      ActivityKind.assigned => (Icons.person_rounded, AppColors.primary),
      ActivityKind.invited => (Icons.add_rounded, AppColors.purple),
      ActivityKind.teamCreated => (Icons.groups_rounded, AppColors.primary),
    };
    const bold = TextStyle(fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withAlpha(28),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    if (item.actor.isNotEmpty) TextSpan(text: '${item.actor} ', style: bold),
                    TextSpan(text: '${item.verb} '),
                    TextSpan(text: item.object, style: bold),
                    TextSpan(text: item.suffix),
                  ]),
                  style: const TextStyle(fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(_ago(item.at),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================== laptop page

class _TeamsWide extends StatefulWidget {
  final Future<void> Function(BuildContext) onCreate;
  const _TeamsWide({required this.onCreate});

  @override
  State<_TeamsWide> createState() => _TeamsWideState();
}

class _TeamsWideState extends State<_TeamsWide> {
  String _search = '';
  String _sort = 'Name';
  bool _grid = true;

  List<Team> _visible(List<Team> teams) {
    final q = _search.trim().toLowerCase();
    final store = TeamStore.instance;
    final list = teams.where((t) => q.isEmpty || t.name.toLowerCase().contains(q)).toList();
    int pending(Team t) => store.tasksOf(t.id).where((x) => x.status == TaskStatus.pending).length;
    switch (_sort) {
      case 'Newest':
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case 'Most pending':
        list.sort((a, b) => pending(b).compareTo(pending(a)));
      default:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    final me = store.uid ?? '';
    final totals = _Totals(store.teams);
    final teams = _visible(store.teams);
    final sent = _sentInvites(me);
    final activity = _activity(me);

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
      children: [
        PageHeader(
          title: 'Teams',
          subtitle: 'Create a team, invite people by email and give them tasks.',
          actions: [
            TextButton.icon(
              onPressed: () => widget.onCreate(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New team', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: StatCard(
                  icon: Icons.groups_rounded,
                  color: AppColors.primary,
                  value: store.teams.length,
                  label: 'Total teams',
                  colorValue: false),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: StatCard(
                  icon: Icons.schedule_rounded,
                  color: AppColors.warning,
                  value: totals.pending,
                  label: 'Pending'),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: StatCard(
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.danger,
                  value: totals.overdue,
                  label: 'Overdue'),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: StatCard(
                  icon: Icons.check_circle_rounded,
                  color: AppColors.success,
                  value: totals.doneThisWeek,
                  label: 'Done this week'),
            ),
          ],
        ),
        if (store.invites.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionHeader(title: 'Invitations for you'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            children: [
              for (final i in store.invites) SizedBox(width: 420, child: _InviteCard(invite: i)),
            ],
          ),
        ],
        const SizedBox(height: 20),
        DashCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: fieldDecoration('Search teams...', icon: Icons.search_rounded)
                        .copyWith(contentPadding: EdgeInsets.zero),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SortButton(
                options: const ['Name', 'Newest', 'Most pending'],
                selected: _sort,
                onSelected: (v) => setState(() => _sort = v),
              ),
              const SizedBox(width: 16),
              ViewToggle(
                board: _grid,
                onChanged: (v) => setState(() => _grid = v),
                firstIcon: Icons.grid_view_rounded,
                firstTip: 'Cards',
                secondIcon: Icons.view_list_rounded,
                secondTip: 'List',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text('My teams', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (store.teams.isEmpty)
          EmptyState(
            icon: Icons.groups_rounded,
            title: 'No teams yet',
            subtitle: 'Make a team (for example "SEO"), then add people by email.',
          )
        else if (teams.isEmpty)
          const EmptyState(
              icon: Icons.search_off_rounded, title: 'No team found', subtitle: 'Try another name.')
        else if (_grid)
          LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth >= 1100 ? 3 : 2;
            final w = (box.maxWidth - 16 * (cols - 1)) / cols;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final t in teams) SizedBox(width: w, child: _WideTeamCard(team: t, me: me)),
              ],
            );
          })
        else
          Column(children: [for (final t in teams) _TeamCard(team: t, me: me)]),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DashCard(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pending invites (${sent.length})',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    if (sent.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No open invitations.',
                            style: TextStyle(color: AppColors.textMuted)),
                      )
                    else
                      for (final i in sent) _SentInviteRow(invite: i, showTeam: true),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DashCard(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Recent activity',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    if (activity.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Nothing yet.', style: TextStyle(color: AppColors.textMuted)),
                      )
                    else
                      for (final a in activity) _ActivityRow(item: a),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WideTeamCard extends StatelessWidget {
  final Team team;
  final String me;
  const _WideTeamCard({required this.team, required this.me});

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    final tasks = store.tasksOf(team.id);
    final st = TeamStats.compute(team, tasks, DateTime.now());
    final color = Color(team.color);
    final role = team.roleOf(me) ?? TeamRole.member;

    return DashCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openTeam(context, team),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 8, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                          color: color.withAlpha(30), borderRadius: BorderRadius.circular(14)),
                      child: Icon(Icons.groups_rounded, color: color, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(team.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(
                            '${team.memberIds.length} ${team.memberIds.length == 1 ? 'member' : 'members'}'
                            ' • ${st.total} ${st.total == 1 ? 'task' : 'tasks'}',
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 8),
                          RoleChip(role: role),
                        ],
                      ),
                    ),
                    _teamMenu(context, team, me),
                  ],
                ),
                const SizedBox(height: 14),
                _MemberDots(team: team, canInvite: team.isAdmin(me)),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: st.progress,
                            minHeight: 7,
                            color: color,
                            backgroundColor: color.withAlpha(30),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('${st.done}/${st.total} done',
                          style: const TextStyle(color: AppColors.textMuted)),
                    ],
                  ),
                ),
                const Divider(height: 26),
                _TeamLegend(stats: st),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
