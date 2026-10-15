import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/team_store.dart';
import '../widgets/responsive.dart';
import 'calendar_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'task_form_screen.dart';
import 'task_panel.dart';
import 'tasks_screen.dart';
import 'teams_screen.dart';

/// Bottom navigation: Home | Tasks | (+) | Teams | Profile.
/// Calendar (index 2) opens from the shortcut on Home.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Lets child screens switch tabs (e.g. Home → "See all" opens Tasks).
  static void switchTab(BuildContext context, int index) {
    context.findAncestorStateOfType<_MainShellState>()?.setTab(index);
  }

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  void setTab(int i) => setState(() => _index = i);

  Future<void> _addTask() async {
    final day = DateTime.now();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TaskFormScreen(initialDate: day)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isWideScreen(context)) return _buildWide(context);
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setTab(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: const [
            HomeScreen(),
            TasksScreen(),
            CalendarScreen(),
            ProfileScreen(),
            TeamsScreen(),
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
            listenable: TeamStore.instance,
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
                    label: 'Tasks',
                    active: _index == 1,
                    onTap: () => setTab(1)),
                const SizedBox(width: 64),
                _NavItem(
                    icon: Icons.groups_outlined,
                    activeIcon: Icons.groups_rounded,
                    label: 'Teams',
                    badge: TeamStore.instance.invites.length,
                    active: _index == 4,
                    onTap: () => setTab(4)),
                _NavItem(
                    icon: Icons.person_outline_rounded,
                    activeIcon: Icons.person_rounded,
                    label: 'Profile',
                    active: _index == 3,
                    onTap: () => setTab(3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension on _MainShellState {
  // Side menu order -> index in the IndexedStack.
  static const _railToTab = [0, 1, 2, 4, 3]; // Home, Tasks, Calendar, Teams, Profile

  /// Laptop / big screen: menu on the left, pages in the middle, the chosen
  /// task in a panel on the right.
  Widget _buildWide(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      body: Row(
        children: [
          ListenableBuilder(
            listenable: TeamStore.instance,
            builder: (context, _) {
              final invites = TeamStore.instance.invites.length;
              return NavigationRail(
                extended: width >= 1200,
                minExtendedWidth: 200,
                backgroundColor: Colors.white,
                selectedIndex: _railToTab.indexOf(_index),
                onDestinationSelected: (i) => setTab(_railToTab[i]),
                labelType: width >= 1200 ? null : NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: width >= 1200
                      ? FloatingActionButton.extended(
                          heroTag: 'rail-add',
                          elevation: 1,
                          onPressed: _addTask,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('New task'),
                        )
                      : FloatingActionButton(
                          heroTag: 'rail-add',
                          elevation: 1,
                          tooltip: 'New task',
                          onPressed: _addTask,
                          child: const Icon(Icons.add_rounded),
                        ),
                ),
                destinations: [
                  const NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: Text('Home')),
                  const NavigationRailDestination(
                      icon: Icon(Icons.check_box_outlined),
                      selectedIcon: Icon(Icons.check_box_rounded),
                      label: Text('Tasks')),
                  const NavigationRailDestination(
                      icon: Icon(Icons.calendar_today_outlined),
                      selectedIcon: Icon(Icons.calendar_today_rounded),
                      label: Text('Calendar')),
                  NavigationRailDestination(
                      icon: Badge(
                          isLabelVisible: invites > 0,
                          label: Text('$invites'),
                          child: const Icon(Icons.groups_outlined)),
                      selectedIcon: const Icon(Icons.groups_rounded),
                      label: const Text('Teams')),
                  const NavigationRailDestination(
                      icon: Icon(Icons.person_outline_rounded),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: Text('Profile')),
                ],
              );
            },
          ),
          const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(
            child: DetailPanelHost(
              panelBuilder: buildTaskPanel,
              child: IndexedStack(
                index: _index,
                children: const [
                  CenteredContent(child: HomeScreen()),
                  CenteredContent(child: TasksScreen()),
                  CenteredContent(child: CalendarScreen()),
                  CenteredContent(child: ProfileScreen()),
                  CenteredContent(child: TeamsScreen()),
                ],
              ),
            ),
          ),
        ],
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
