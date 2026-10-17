import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/task_repository.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';
import 'calendar_screen.dart';
import 'home_screen.dart';
import 'inbox_screen.dart';
import 'messages_screen.dart';
import '../data/chat_store.dart';
import 'approvals_screen.dart';
import 'planner_screen.dart';
import 'workload_screen.dart';
import 'time_screen.dart';
import 'reports_screen.dart';
import 'templates_screen.dart';
import '../data/inbox.dart';
import 'profile_screen.dart';
import 'notifications_screen.dart';
import 'projects_screen.dart';
import 'task_panel.dart';
import 'tasks_screen.dart';
import 'team_screen.dart';
import 'teams_screen.dart';
import 'create_task_dialog.dart';

part 'main_shell_wide.dart';

/// Phone: bottom navigation Home | Tasks | (+) | Chats | Menu. Menu (or a
/// swipe from the left edge) opens the laptop side menu as a drawer.
/// Calendar (index 2) opens from the shortcut on Home.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Lets child screens switch tabs (e.g. Home → "See all" opens Tasks).
  static void switchTab(BuildContext context, int index) {
    context.findAncestorStateOfType<_MainShellState>()?.setTab(index);
  }

  /// Opens a team's workspace: next to the side menu on a laptop, as a new
  /// page on a phone.
  static void openTeamWorkspace(BuildContext context, Team team) {
    final shell = context.findAncestorStateOfType<_MainShellState>();
    if (shell != null && isWideScreen(context)) {
      shell._showTeam(team);
    } else {
      openTeam(context, team);
    }
  }

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  /// Laptop layout: the Teams tab has its own page stack, so a team opens
  /// next to the side menu instead of covering it.
  final _teamsNav = GlobalKey<NavigatorState>();

  /// Laptop: the task opened over the pages.
  final _panelKey = GlobalKey<DetailPanelHostState>();

  /// Phone: opens the menu drawer.
  final _phoneScaffold = GlobalKey<ScaffoldState>();

  void setTab(int i) {
    _panelKey.currentState?.close();
    setState(() => _index = i);
  }

  void _showTeam(Team team) {
    setTab(4);
    final nav = _teamsNav.currentState;
    if (nav == null) return;
    nav.popUntil((r) => r.isFirst);
    openTeam(nav.context, team);
  }

  Future<void> _addTask() => showCreateTask(context);

  /// Phone: a page opened from the menu drawer, with its title and a menu
  /// button.
  Widget _menuPage(String title, Widget child) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          leading: IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => _phoneScaffold.currentState?.openDrawer(),
          ),
          title: Text(title),
        ),
        body: child,
      );

  @override
  Widget build(BuildContext context) {
    if (isWideScreen(context)) return _buildWide(context);
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setTab(0);
      },
      child: Scaffold(
        key: _phoneScaffold,
        drawer: _buildDrawer(context),
        body: IndexedStack(
          index: _index,
          children: [
            const HomeScreen(),
            const TasksScreen(),
            const CalendarScreen(),
            const ProfileScreen(),
            const TeamsScreen(),
            _menuPage('Capture', const InboxScreen()),
            _menuPage('Notifications', const NotificationsScreen(page: false)),
            _menuPage('Approvals', const ApprovalsScreen()),
            _menuPage('Daily Planner', const PlannerScreen()),
            _menuPage('Team Workload', const WorkloadScreen()),
            _menuPage('Time Tracking', const TimeScreen()),
            _menuPage('Reports', const ReportsScreen()),
            _menuPage('Templates', const TemplatesScreen()),
            const SafeArea(child: MessagesScreen()),
          ],
        ),
        floatingActionButton: SizedBox(
          width: 58,
          height: 58,
          child: FloatingActionButton(
            onPressed: _addTask,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 4,
            shape: const CircleBorder(),
            child: const Icon(Icons.add_rounded, size: 30),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          color: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 12,
          shape: const CircularNotchedRectangle(),
          notchMargin: 7,
          height: 68,
          padding: EdgeInsets.zero,
          // Rebuilds for the invitation badge on Teams.
          child: ListenableBuilder(
            listenable: Listenable.merge([TeamStore.instance, ChatStore.instance]),
            builder: (context, _) => Row(
              children: [
                _NavItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    label: 'Home',
                    active: _index == 0,
                    onTap: () => setTab(0)),
                _NavItem(
                    icon: Icons.check_box_outlined,
                    activeIcon: Icons.check_box_rounded,
                    label: 'My Tasks',
                    active: _index == 1,
                    onTap: () => setTab(1)),
                const SizedBox(width: 64),
                _NavItem(
                    icon: Icons.forum_outlined,
                    activeIcon: Icons.forum_rounded,
                    label: 'Chats',
                    badge: ChatStore.instance.unreadCount,
                    active: _index == 13,
                    onTap: () => setTab(13)),
                _NavItem(
                    icon: Icons.menu_rounded,
                    activeIcon: Icons.menu_rounded,
                    label: 'Menu',
                    badge: TeamStore.instance.invites.length +
                        TeamStore.instance.awaitingMyApproval.length +
                        TeamStore.instance.moveRequestsForMe.length,
                    active: _index != 0 && _index != 1 && _index != 13,
                    onTap: () => _phoneScaffold.currentState?.openDrawer()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badge;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : const Color(0xFF9CA3AF);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: badge > 0,
              label: Text('$badge'),
              child: Icon(active ? activeIcon : icon, color: color, size: 24),
            ),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
