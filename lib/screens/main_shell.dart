import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'calendar_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'task_form_screen.dart';
import 'tasks_screen.dart';

/// Bottom navigation: Home | Tasks | (+) | Calendar | Profile
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
          child: Row(
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
                  icon: Icons.calendar_today_outlined,
                  activeIcon: Icons.calendar_today_rounded,
                  label: 'Calendar',
                  active: _index == 2,
                  onTap: () => setTab(2)),
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
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
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
            Icon(active ? activeIcon : icon, color: color, size: 24),
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
