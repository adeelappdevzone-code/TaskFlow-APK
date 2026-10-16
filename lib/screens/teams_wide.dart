part of 'teams_screen.dart';

// The Teams page (laptop and phone): invitations for me, totals, search /
// sort / grid-list, team cards, a "Create new team" card, open invitations I
// sent and recent activity.

/// Pending (not late) / overdue / done-this-week summed over my teams.
class _Totals {
  int pending = 0;
  int overdue = 0;
  int doneThisWeek = 0;

  _Totals(List<Team> teams) {
    final store = TeamStore.instance;
    final now = DateTime.now();
    for (final t in teams) {
      final st = TeamStats.compute(t, store.tasksOf(t.id), now);
      pending += st.pending - st.overdue;
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
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} ${diff.inHours == 1 ? 'hour' : 'hours'} ago';
  if (diff.inDays == 1) return '1 day ago';
  return '${diff.inDays} days ago';
}

/// "fatima.ali@x.com" -> "Fatima Ali".
String _nameFromEmail(String email) => email
    .split('@')
    .first
    .split(RegExp(r'[._\-+]+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// ⋮ menu of a team card.
Widget _teamMenu(BuildContext context, Team team, String me) {
  final owner = team.ownerId == me;
  final admin = team.isAdmin(me);
  return PopupMenuButton<String>(
    tooltip: 'More',
    icon: const Icon(Icons.more_vert_rounded),
    onSelected: (a) async {
      final store = TeamStore.instance;
      switch (a) {
        case 'open':
          openTeam(context, team);
        case 'task':
          showCreateTask(context, team: team);
        case 'invite':
          await showInviteDialog(context, team);
        case 'report':
          openWeeklyReport(context, team);
        case 'edit':
          final r = await showTeamDialog(context, team: team);
          if (r != null) store.renameTeam(team, r.$1, r.$2);
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
      const PopupMenuItem(value: 'task', child: Text('New task in this team')),
      if (admin) const PopupMenuItem(value: 'invite', child: Text('Add person')),
      if (admin) const PopupMenuItem(value: 'report', child: Text('Weekly report')),
      if (owner) const PopupMenuItem(value: 'edit', child: Text('Edit team')),
      if (!owner) const PopupMenuItem(value: 'leave', child: Text('Leave team')),
      if (owner)
        const PopupMenuItem(
            value: 'delete', child: Text('Delete team', style: TextStyle(color: AppColors.danger))),
    ],
  );
}

// ======================================================================= page

class _TeamsPage extends StatefulWidget {
  final Future<void> Function(BuildContext) onCreate;
  final bool wide;
  const _TeamsPage({required this.onCreate, required this.wide});

  @override
  State<_TeamsPage> createState() => _TeamsPageState();
}

class _TeamsPageState extends State<_TeamsPage> {
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
    final wide = widget.wide;
    final totals = _Totals(store.teams);
    final teams = _visible(store.teams);
    final sent = _sentInvites(me);
    final activity = _activity(me, limit: wide ? 6 : 5);
    final gap = SizedBox(height: wide ? 20 : 14, width: wide ? 18 : 10);

    final stats = [
      _StatTile(
          icon: Icons.groups_rounded,
          color: AppColors.primary,
          label: 'Total teams',
          value: store.teams.length,
          caption: 'Across the workspace',
          compact: !wide),
      _StatTile(
          icon: Icons.schedule_rounded,
          color: AppColors.danger,
          label: 'Pending',
          value: totals.pending,
          caption: 'Tasks awaiting action',
          compact: !wide),
      _StatTile(
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFEA580C),
          label: 'Overdue',
          value: totals.overdue,
          caption: 'Tasks past due date',
          compact: !wide),
      _StatTile(
          icon: Icons.check_circle_rounded,
          color: AppColors.success,
          label: 'Done this week',
          value: totals.doneThisWeek,
          caption: 'Tasks completed',
          compact: !wide),
    ];

    final toolbar = wide
        ? Row(
            children: [
              Expanded(
                flex: 5,
                child: SizedBox(height: 46, child: _searchField()),
              ),
              const Spacer(flex: 3),
              _sortButton(),
              const SizedBox(width: 12),
              _GridListSwitch(grid: _grid, onChanged: (g) => setState(() => _grid = g)),
            ],
          )
        : Row(
            children: [
              Expanded(child: SizedBox(height: 46, child: _searchField())),
              const SizedBox(width: 8),
              _sortButton(compact: true),
              IconButton(
                tooltip: 'Team Workload',
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const WorkloadScreen(page: true))),
                icon: const Icon(Icons.stacked_bar_chart_rounded),
              ),
            ],
          );

    final cards = LayoutBuilder(builder: (context, box) {
      final cols = !wide ? 1 : (box.maxWidth >= 1100 ? 3 : 2);
      final w = (box.maxWidth - 18 * (cols - 1)) / cols;
      if (wide && !_grid) {
        return _TeamTable(teams: teams, me: me);
      }
      return Wrap(
        spacing: 18,
        runSpacing: 18,
        children: [
          for (final t in teams) SizedBox(width: w, child: _TeamCard(team: t, me: me)),
          if (_search.isEmpty)
            SizedBox(width: w, child: _CreateTeamCard(onTap: () => widget.onCreate(context))),
        ],
      );
    });

    final invitesCard = DashCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(
            icon: Icons.mail_outline_rounded,
            title: 'Pending Invites',
            subtitle: 'Invitations waiting for people to join.',
            count: sent.length,
          ),
          const SizedBox(height: 8),
          if (sent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('No open invitations.', style: TextStyle(color: AppColors.textMuted)),
            )
          else
            for (final (i, inv) in sent.indexed) ...[
              if (i > 0) const Divider(height: 1),
              _SentInviteRow(invite: inv, wide: wide),
            ],
        ],
      ),
    );

    final activityCard = DashCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle(
            icon: Icons.history_rounded,
            title: 'Recent Activity',
            subtitle: 'Latest team activity across your workspace.',
          ),
          const SizedBox(height: 8),
          if (activity.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Nothing yet.', style: TextStyle(color: AppColors.textMuted)),
            )
          else
            for (final a in activity) _ActivityRow(item: a),
        ],
      ),
    );

    return ListView(
      padding: wide
          ? const EdgeInsets.fromLTRB(28, 24, 28, 40)
          : const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        // ------------------------------------------------------------ header
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Teams',
                      style: TextStyle(fontSize: wide ? 30 : 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Manage your teams and collaborate with your colleagues.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: wide ? 15 : 13)),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => widget.onCreate(context),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: wide ? 22 : 14, vertical: wide ? 18 : 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New team', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        // -------------------------------------------- invitations for me first
        if (store.invites.isNotEmpty) ...[
          gap,
          _InvitesForMe(invites: store.invites, wide: wide),
        ],
        gap,
        if (wide)
          Row(children: [
            for (final (i, s) in stats.indexed) ...[
              if (i > 0) const SizedBox(width: 18),
              Expanded(child: s),
            ],
          ])
        else
          Column(children: [
            Row(children: [
              Expanded(child: stats[0]),
              const SizedBox(width: 10),
              Expanded(child: stats[1])
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: stats[2]),
              const SizedBox(width: 10),
              Expanded(child: stats[3])
            ]),
          ]),
        gap,
        if (store.teams.isNotEmpty) ...[toolbar, gap],
        if (store.teams.isEmpty)
          _CreateTeamCard(onTap: () => widget.onCreate(context), big: true)
        else if (teams.isEmpty)
          const EmptyState(
              icon: Icons.search_off_rounded, title: 'No team found', subtitle: 'Try another name.')
        else
          cards,
        gap,
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 11, child: invitesCard),
              const SizedBox(width: 18),
              Expanded(flex: 9, child: activityCard),
            ],
          )
        else ...[
          if (sent.isNotEmpty) ...[invitesCard, gap],
          if (activity.isNotEmpty) activityCard,
        ],
      ],
    );
  }

  Widget _searchField() => TextField(
        onChanged: (v) => setState(() => _search = v),
        decoration: fieldDecoration('Search teams...', icon: Icons.search_rounded)
            .copyWith(contentPadding: EdgeInsets.zero),
      );

  Widget _sortButton({bool compact = false}) => PopupMenuButton<String>(
        tooltip: 'Sort',
        position: PopupMenuPosition.under,
        onSelected: (v) => setState(() => _sort = v),
        itemBuilder: (_) => [
          for (final o in const ['Name', 'Newest', 'Most pending'])
            CheckedPopupMenuItem(value: o, checked: o == _sort, child: Text(o)),
        ],
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_vert_rounded, size: 20),
              if (!compact) ...[
                const SizedBox(width: 8),
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Sort by: ', style: TextStyle(color: AppColors.textMuted)),
                  TextSpan(text: _sort, style: const TextStyle(fontWeight: FontWeight.w600)),
                ])),
                const SizedBox(width: 18),
                const Icon(Icons.expand_more_rounded, size: 20),
              ],
            ],
          ),
        ),
      );
}

// ===================================================================== pieces

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int value;
  final String caption;
  final bool compact;
  const _StatTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.caption,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return DashCard(
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Row(
        children: [
          Container(
            width: compact ? 40 : 64,
            height: compact ? 40 : 64,
            decoration: BoxDecoration(
              color: color.withAlpha(24),
              borderRadius: BorderRadius.circular(compact ? 11 : 16),
            ),
            child: Icon(icon, color: color, size: compact ? 21 : 32),
          ),
          SizedBox(width: compact ? 10 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: compact ? 12 : 14, color: const Color(0xFF4B5563))),
                Text('$value',
                    style: TextStyle(
                        fontSize: compact ? 20 : 28,
                        fontWeight: FontWeight.w800,
                        color: label == 'Total teams' ? AppColors.primary : color)),
                if (!compact)
                  Text(caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridListSwitch extends StatelessWidget {
  final bool grid;
  final ValueChanged<bool> onChanged;
  const _GridListSwitch({required this.grid, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget item(bool g, IconData icon, String label) {
      final on = grid == g;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(g),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: on ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 19, color: on ? Colors.white : AppColors.text),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: on ? Colors.white : AppColors.text)),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        item(true, Icons.grid_view_rounded, 'Grid'),
        item(false, Icons.view_list_rounded, 'List'),
      ]),
    );
  }
}

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int? count;
  const _CardTitle({required this.icon, required this.title, required this.subtitle, this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration:
              BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: AppColors.primary, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                if (count != null && count! > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppColors.primaryLight, borderRadius: BorderRadius.circular(10)),
                    child: Text('$count',
                        style:
                            const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Invitations sent to me: shown first, with Accept / Decline.
class _InvitesForMe extends StatelessWidget {
  final List<TeamInvite> invites;
  final bool wide;
  const _InvitesForMe({required this.invites, required this.wide});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF5FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCFE0FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.mark_email_unread_outlined, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(
                invites.length == 1
                    ? 'You have an invitation'
                    : 'You have ${invites.length} invitations',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            children: [
              for (final i in invites)
                SizedBox(width: wide ? 420 : double.infinity, child: _InviteCard(invite: i)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Overlapping member avatars, "+N" and "+" to add someone.
class _AvatarStack extends StatelessWidget {
  final Team team;
  final bool canInvite;
  const _AvatarStack({required this.team, required this.canInvite});

  static const _colors = [
    AppColors.primary,
    AppColors.purple,
    Color(0xFF0891B2),
    Color(0xFFDB2777),
  ];

  @override
  Widget build(BuildContext context) {
    final ids = team.sortedMemberIds;
    final shown = ids.take(4).toList();
    const size = 34.0, step = 26.0;
    final extra = ids.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    return Row(
      children: [
        SizedBox(
          width: step * (count - 1) + size,
          height: size,
          child: Stack(
            children: [
              for (final (i, uid) in shown.indexed)
                Positioned(
                  left: step * i,
                  child: Tooltip(
                    message: team.nameOf(uid),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        color: Colors.white,
                      ),
                      child: Avatar(
                          name: team.nameOf(uid),
                          size: size - 4,
                          color: _colors[i % _colors.length]),
                    ),
                  ),
                ),
              if (extra > 0)
                Positioned(
                  left: step * shown.length,
                  child: Container(
                    width: size,
                    height: size,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDF1F7),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text('+$extra',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ),
        if (canInvite) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: 'Add person',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => showInviteDialog(context, team),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary.withAlpha(90), width: 1.4),
                ),
                child: const Icon(Icons.add_rounded, size: 19, color: AppColors.primary),
              ),
            ),
          ),
        ],
      ],
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration:
            BoxDecoration(color: color.withAlpha(16), borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$value',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _TeamCard extends StatelessWidget {
  final Team team;
  final String me;
  const _TeamCard({required this.team, required this.me});

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    final st = TeamStats.compute(team, store.tasksOf(team.id), DateTime.now());
    final color = Color(team.color);
    final role = team.roleOf(me) ?? TeamRole.member;
    final mine = store.pendingForMe(team.id);

    return DashCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openTeam(context, team),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 6, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: color.withAlpha(28), borderRadius: BorderRadius.circular(16)),
                      child: Text(initials(team.name),
                          style:
                              TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 20)),
                    ),
                    const SizedBox(width: 14),
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
                                      const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 8),
                            RoleChip(role: role),
                          ]),
                          const SizedBox(height: 4),
                          Text(
                            '${team.memberIds.length} ${team.memberIds.length == 1 ? 'member' : 'members'}'
                            '  •  ${st.total} ${st.total == 1 ? 'task' : 'tasks'}',
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    _teamMenu(context, team, me),
                  ],
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(children: [
                    Expanded(child: _AvatarStack(team: team, canInvite: team.isAdmin(me))),
                    if (mine > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                            color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                        child: Text('$mine for you',
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                  ]),
                ),
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
                            color: AppColors.success,
                            backgroundColor: const Color(0xFFE6EAF0),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('${st.done}/${st.total} done',
                          style: const TextStyle(color: Color(0xFF4B5563))),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(children: [
                    Expanded(
                        child: _MiniStat(
                            icon: Icons.schedule_rounded,
                            color: AppColors.danger,
                            value: st.pending - st.overdue,
                            label: 'Pending')),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _MiniStat(
                            icon: Icons.warning_amber_rounded,
                            color: const Color(0xFFEA580C),
                            value: st.overdue,
                            label: 'Overdue')),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _MiniStat(
                            icon: Icons.check_circle_outline_rounded,
                            color: AppColors.success,
                            value: st.done,
                            label: 'Done')),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateTeamCard extends StatelessWidget {
  final VoidCallback onTap;
  final bool big;
  const _CreateTeamCard({required this.onTap, this.big = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorder(),
        child: Container(
          constraints: BoxConstraints(minHeight: big ? 260 : 232),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration:
                    const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
                child: const Icon(Icons.group_add_outlined, color: AppColors.primary, size: 30),
              ),
              const SizedBox(height: 14),
              const Text('Create new team',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary)),
              const SizedBox(height: 6),
              const Text('Organize your people, assign tasks\nand start collaborating.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, size.width - 2, size.height - 2), const Radius.circular(18));
    final paint = Paint()
      ..color = const Color(0xFFB6CCF5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 7), paint);
        d += 13;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => false;
}

/// List view of teams (laptop).
class _TeamTable extends StatelessWidget {
  final List<Team> teams;
  final String me;
  const _TeamTable({required this.teams, required this.me});

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600);
    final store = TeamStore.instance;
    return DashCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 8, 12),
            child: Row(children: [
              Expanded(flex: 4, child: Text('Team', style: head)),
              Expanded(flex: 3, child: Text('Members', style: head)),
              Expanded(flex: 3, child: Text('Progress', style: head)),
              SizedBox(width: 90, child: Text('Pending', style: head)),
              SizedBox(width: 90, child: Text('Overdue', style: head)),
              SizedBox(width: 100, child: Text('Your role', style: head)),
              SizedBox(width: 48),
            ]),
          ),
          for (final t in teams) ...[
            const Divider(height: 1),
            Builder(builder: (context) {
              final st = TeamStats.compute(t, store.tasksOf(t.id), DateTime.now());
              final color = Color(t.color);
              return InkWell(
                onTap: () => openTeam(context, t),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
                  child: Row(children: [
                    Expanded(
                      flex: 4,
                      child: Row(children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: color.withAlpha(28), borderRadius: BorderRadius.circular(11)),
                          child: Text(initials(t.name),
                              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(t.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                      ]),
                    ),
                    Expanded(flex: 3, child: _AvatarStack(team: t, canInvite: false)),
                    Expanded(
                      flex: 3,
                      child: Row(children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: st.progress,
                              minHeight: 6,
                              color: AppColors.success,
                              backgroundColor: const Color(0xFFE6EAF0),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('${st.done}/${st.total}'),
                        const SizedBox(width: 16),
                      ]),
                    ),
                    SizedBox(
                        width: 90,
                        child: Text('${st.pending - st.overdue}',
                            style: const TextStyle(
                                color: AppColors.danger, fontWeight: FontWeight.w700))),
                    SizedBox(
                        width: 90,
                        child: Text('${st.overdue}',
                            style: const TextStyle(
                                color: Color(0xFFEA580C), fontWeight: FontWeight.w700))),
                    SizedBox(
                        width: 100,
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: RoleChip(role: t.roleOf(me) ?? TeamRole.member))),
                    SizedBox(width: 48, child: _teamMenu(context, t, me)),
                  ]),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

/// Row of an invitation I (or another manager) sent.
class _SentInviteRow extends StatelessWidget {
  final TeamInvite invite;
  final bool wide;
  const _SentInviteRow({required this.invite, this.wide = true});

  @override
  Widget build(BuildContext context) {
    final i = invite;
    final team = TeamStore.instance.teamById(i.teamId);
    final color = team == null ? AppColors.primary : Color(team.color);
    final name = _nameFromEmail(i.email);
    final teamChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withAlpha(24), borderRadius: BorderRadius.circular(8)),
      child: Text(i.teamName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
    );
    final pending = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: AppColors.warningLight, borderRadius: BorderRadius.circular(8)),
      child: const Text('Pending',
          style: TextStyle(color: Color(0xFFB45309), fontSize: 12.5, fontWeight: FontWeight.w600)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Avatar(name: name, size: 38, color: color),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(wide ? 'Invited ${_ago(i.createdAt)}' : '${i.email} • ${i.teamName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              ],
            ),
          ),
          if (wide) ...[
            Expanded(
              flex: 5,
              child: Text(i.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF4B5563), fontSize: 13.5)),
            ),
            Expanded(flex: 3, child: Align(alignment: Alignment.centerLeft, child: teamChip)),
            pending,
          ],
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (a) {
              if (a == 'copy') {
                Clipboard.setData(ClipboardData(text: i.email));
                showSnack(context, 'Email copied');
              } else {
                TeamStore.instance.cancelInvite(i);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('Copy email')),
              PopupMenuItem(
                  value: 'cancel',
                  child: Text('Cancel invitation', style: TextStyle(color: AppColors.danger))),
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
    final team = TeamStore.instance.teamById(item.teamId);
    final who = item.actor.isEmpty
        ? (team?.name ?? '?')
        : (item.actor == 'You' ? (AppStore.instance.currentUser?.name ?? 'You') : item.actor);
    const bold = TextStyle(fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Avatar(name: who, size: 32, color: team == null ? AppColors.primary : Color(team.color)),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                if (item.actor.isNotEmpty) TextSpan(text: '${item.actor} ', style: bold),
                TextSpan(text: '${item.verb} '),
                TextSpan(
                    text: item.object,
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                TextSpan(text: item.suffix),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
          const SizedBox(width: 10),
          Text(_ago(item.at), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
