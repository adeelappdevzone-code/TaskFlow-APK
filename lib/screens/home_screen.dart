import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../widgets/common.dart';
import 'main_shell.dart';
import 'notifications_screen.dart';
import 'projects_screen.dart';
import 'task_detail_screen.dart';
import 'tasks_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final user = store.currentUser;
        final firstName = (user?.name ?? '').split(' ').first;
        final today = store.todayTasks;

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              // ---------------------------------------------------- header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hello, $firstName 👋',
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          '${greeting()}! There is a lot you can finish today.',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 13.5),
                        ),
                      ],
                    ),
                  ),
                  _BellButton(count: store.unreadCount),
                ],
              ),
              const SizedBox(height: 20),

              // ----------------------------------------------- summary card
              _SummaryCard(
                total: store.totalCount,
                done: store.doneCount,
                pending: store.pendingCount,
              ),
              const SizedBox(height: 20),

              // --------------------------------------------- quick actions
              Row(
                children: [
                  _QuickAction(
                    icon: Icons.format_list_bulleted_rounded,
                    label: 'All Tasks',
                    color: AppColors.primary,
                    onTap: () => MainShell.switchTab(context, 1),
                  ),
                  _QuickAction(
                    icon: Icons.local_fire_department_rounded,
                    label: 'High Priority',
                    color: const Color(0xFFF97316),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TasksScreen(
                          standalone: true,
                          initialPriority: Priority.high,
                        ),
                      ),
                    ),
                  ),
                  _QuickAction(
                    icon: Icons.calendar_month_rounded,
                    label: 'Calendar',
                    color: AppColors.primary,
                    onTap: () => MainShell.switchTab(context, 2),
                  ),
                  _QuickAction(
                    icon: Icons.folder_rounded,
                    label: 'Projects',
                    color: AppColors.success,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ProjectsScreen())),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ------------------------------------------------ today list
              SectionHeader(
                title: "Today's Tasks",
                actionLabel: 'See all',
                onAction: () => MainShell.switchTab(context, 1),
              ),
              const SizedBox(height: 12),
              if (today.isEmpty)
                const EmptyState(
                  icon: Icons.wb_sunny_outlined,
                  title: 'Nothing planned for today',
                  subtitle: 'Tap the + button to add a task.',
                )
              else
                ...today.map((t) => TaskTile(
                      task: t,
                      showDay: false,
                      onTap: () => openTaskDetail(context, t),
                    )),
            ],
          ),
        );
      },
    );
  }
}

class _BellButton extends StatelessWidget {
  final int count;
  const _BellButton({required this.count});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.notifications_none_rounded, size: 28),
            if (count > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 18),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.background, width: 1.5),
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int total;
  final int done;
  final int pending;
  const _SummaryCard({required this.total, required this.done, required this.pending});

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : done / total;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2F7CF6), AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(60),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Tasks',
                    style: TextStyle(color: Colors.white70, fontSize: 13.5)),
                const SizedBox(height: 4),
                Text('$total',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _pill(Icons.check_circle_rounded, '$done done'),
                    _pill(Icons.hourglass_bottom_rounded, '$pending pending'),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: 70,
            height: 70,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 70,
                  height: 70,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 6,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                Text('${(progress * 100).round()}%',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(40),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(text,
                style: const TextStyle(
                    color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction(
      {required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: WhiteCard(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Column(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withAlpha(28),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.2)),
            ],
          ),
        ),
      ),
    );
  }
}
