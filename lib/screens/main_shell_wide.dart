part of 'main_shell.dart';

// Laptop / big screen frame: side menu on the left, a top bar with search,
// notifications and the account menu, pages in the middle and the chosen task
// in a panel on the right.

class _NavEntry {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int tab; // index in the IndexedStack
  const _NavEntry(this.icon, this.activeIcon, this.label, this.tab);
}

const _navEntries = [
  _NavEntry(Icons.home_outlined, Icons.home_rounded, 'Home', 0),
  _NavEntry(Icons.check_box_outlined, Icons.check_box_rounded, 'My Tasks', 1),
  _NavEntry(Icons.calendar_today_outlined, Icons.calendar_today_rounded, 'Calendar', 2),
  _NavEntry(Icons.groups_outlined, Icons.groups_rounded, 'Teams', 4),
  _NavEntry(Icons.person_outline_rounded, Icons.person_rounded, 'Profile', 3),
];

extension on _MainShellState {
  Widget _buildWide(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 1150;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          ListenableBuilder(
            listenable: TeamStore.instance,
            builder: (context, _) => _SideMenu(
              compact: compact,
              current: _index,
              invites: TeamStore.instance.invites.length,
              onNewTask: _addTask,
              onSelect: (tab) {
                // Teams again while inside a team: back to the team list.
                if (tab == 4 && _index == 4) {
                  _teamsNav.currentState?.popUntil((r) => r.isFirst);
                }
                setTab(tab);
              },
            ),
          ),
          const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  onOpenTeam: _showTeam,
                  onProfile: () => setTab(3),
                  onTeams: () => setTab(4),
                  onOpenTask: (ref) =>
                      _panelKey.currentState?.show(PanelTarget(ref.task.id, teamId: ref.team?.id)),
                ),
                Expanded(
                  child: DetailPanelHost(
                    key: _panelKey,
                    panelBuilder: buildTaskPanel,
                    child: IndexedStack(
                      index: _index,
                      children: [
                        const HomeScreen(),
                        const TasksScreen(), // has its own laptop layout
                        const CenteredContent(child: CalendarScreen()),
                        const ProfileScreen(), // has its own laptop layout
                        Navigator(
                          key: _teamsNav,
                          onGenerateRoute: (_) => MaterialPageRoute(
                            builder: (_) => const Scaffold(
                                backgroundColor: AppColors.background, body: TeamsScreen()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideMenu extends StatelessWidget {
  final bool compact;
  final int current;
  final int invites;
  final VoidCallback onNewTask;
  final ValueChanged<int> onSelect;
  const _SideMenu({
    required this.compact,
    required this.current,
    required this.invites,
    required this.onNewTask,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 84 : 248,
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ------------------------------------------------------- logo
          Row(
            mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 24),
              ),
              if (!compact) ...[
                const SizedBox(width: 10),
                const Flexible(
                  child: Text('TaskFlow',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 26),
          // --------------------------------------------------- new task
          SizedBox(
            height: 48,
            child: compact
                ? Tooltip(
                    message: 'New task',
                    child: FilledButton(
                      onPressed: onNewTask,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Icon(Icons.add_rounded),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: onNewTask,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New Task'),
                  ),
          ),
          const SizedBox(height: 20),
          for (final e in _navEntries)
            _SideItem(
              entry: e,
              compact: compact,
              active: current == e.tab,
              badge: e.tab == 4 ? invites : 0,
              onTap: () => onSelect(e.tab),
            ),
        ],
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  final _NavEntry entry;
  final bool compact;
  final bool active;
  final int badge;
  final VoidCallback onTap;
  const _SideItem({
    required this.entry,
    required this.compact,
    required this.active,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = Badge(
      isLabelVisible: badge > 0,
      label: Text('$badge'),
      child: Icon(active ? entry.activeIcon : entry.icon,
          color: active ? AppColors.primary : AppColors.text, size: 23),
    );
    final item = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: active ? AppColors.primaryLight : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 16, vertical: 12),
            child: compact
                ? Center(child: icon)
                : Row(
                    children: [
                      icon,
                      const SizedBox(width: 16),
                      Text(entry.label,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                            color: active ? AppColors.primary : AppColors.text,
                          )),
                    ],
                  ),
          ),
        ),
      ),
    );
    return compact ? Tooltip(message: entry.label, child: item) : item;
  }
}

/// Search, notifications bell and the account menu.
class _TopBar extends StatelessWidget {
  final ValueChanged<Team> onOpenTeam;
  final VoidCallback onProfile;
  final VoidCallback onTeams;
  final ValueChanged<TaskRef> onOpenTask;
  const _TopBar(
      {required this.onOpenTeam,
      required this.onProfile,
      required this.onTeams,
      required this.onOpenTask});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _SearchBox(onOpenTeam: onOpenTeam, onOpenTask: onOpenTask),
            ),
          ),
          const Spacer(),
          ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final user = store.currentUser;
              final name = user?.name ?? '';
              return Row(
                children: [
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                    icon: Badge(
                      smallSize: 9,
                      isLabelVisible: store.unreadCount > 0,
                      child: const Icon(Icons.notifications_none_rounded, size: 26),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Teams',
                    onPressed: onTeams,
                    style: IconButton.styleFrom(backgroundColor: AppColors.primaryLight),
                    icon: const Icon(Icons.groups_outlined, color: AppColors.primary),
                  ),
                  const SizedBox(width: 14),
                  PopupMenuButton<String>(
                    tooltip: 'Account',
                    position: PopupMenuPosition.under,
                    onSelected: (a) async {
                      switch (a) {
                        case 'profile':
                          onProfile();
                        case 'logout':
                          final ok = await confirmDialog(context,
                              title: 'Log out?',
                              message: 'You can log in again any time.',
                              confirmLabel: 'Log out');
                          if (ok) await store.logout();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        enabled: false,
                        child: Text(user?.email ?? '',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                      ),
                      const PopupMenuItem(value: 'profile', child: Text('Profile & settings')),
                      const PopupMenuItem(
                          value: 'logout',
                          child: Text('Log out', style: TextStyle(color: AppColors.danger))),
                    ],
                    child: Row(
                      children: [
                        Avatar(name: name.isEmpty ? '?' : name, size: 38),
                        const SizedBox(width: 10),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(name.split(' ').first,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// "Search tasks, teams, projects..." with live results under the box.
class _SearchBox extends StatelessWidget {
  final ValueChanged<Team> onOpenTeam;
  final ValueChanged<TaskRef> onOpenTask;
  const _SearchBox({required this.onOpenTeam, required this.onOpenTask});

  /// Every task I can see: mine (personal + assigned) and my teams' tasks.
  static List<TaskRef> _allVisibleTasks() {
    final seen = <String>{};
    final out = <TaskRef>[];
    for (final r in TaskRepository.myTasks()) {
      if (seen.add(r.task.id)) out.add(r);
    }
    for (final team in TeamStore.instance.teams) {
      for (final t in TeamStore.instance.tasksOf(team.id)) {
        if (!t.isCancelled && seen.add(t.id)) out.add(TaskRef(t, team));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return SearchAnchor(
      isFullScreen: false,
      viewConstraints: const BoxConstraints(maxHeight: 440, minWidth: 420),
      viewHintText: 'Search tasks, teams, projects...',
      builder: (context, controller) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: controller.openView,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEEF1F6)),
          ),
          child: const Row(
            children: [
              Icon(Icons.search_rounded, color: AppColors.textMuted, size: 21),
              SizedBox(width: 10),
              Expanded(
                child: Text('Search tasks, teams, projects...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14.5)),
              ),
            ],
          ),
        ),
      ),
      suggestionsBuilder: (context, controller) {
        final q = controller.text.trim().toLowerCase();
        if (q.isEmpty) {
          return const [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('Type to search your tasks, teams and projects.',
                  style: TextStyle(color: AppColors.textMuted)),
            ),
          ];
        }
        final tasks = _allVisibleTasks()
            .where((r) =>
                r.task.title.toLowerCase().contains(q) ||
                r.task.description.toLowerCase().contains(q))
            .take(8)
            .toList();
        final teams =
            TeamStore.instance.teams.where((t) => t.name.toLowerCase().contains(q)).toList();
        final projects = AppStore.instance.projects
            .where((p) => p.deletedAt == null && p.name.toLowerCase().contains(q))
            .toList();

        Widget header(String text) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
            );
        void close() => controller.closeView(null);

        return [
          if (tasks.isEmpty && teams.isEmpty && projects.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nothing found.', style: TextStyle(color: AppColors.textMuted)),
            ),
          if (tasks.isNotEmpty) header('TASKS'),
          for (final r in tasks)
            ListTile(
              leading: Icon(r.task.isCompleted ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: r.task.isCompleted ? AppColors.success : AppColors.textMuted),
              title: Text(r.task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${r.sourceLabel} • ${relativeDay(r.task.startAt)}'),
              onTap: () {
                close();
                onOpenTask(r);
              },
            ),
          if (teams.isNotEmpty) header('TEAMS'),
          for (final t in teams)
            ListTile(
              leading: Icon(Icons.groups_rounded, color: Color(t.color)),
              title: Text(t.name),
              subtitle: Text('${t.memberIds.length} members'),
              onTap: () {
                close();
                onOpenTeam(t);
              },
            ),
          if (projects.isNotEmpty) header('PROJECTS'),
          for (final p in projects)
            ListTile(
              leading: Icon(Icons.folder_rounded, color: Color(p.color)),
              title: Text(p.name),
              onTap: () {
                close();
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ProjectDetailScreen(projectId: p.id)));
              },
            ),
        ];
      },
    );
  }
}
