import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../data/time_tracker.dart';
import '../widgets/common.dart';
import '../widgets/task_extras.dart';
import 'main_shell.dart';
import 'notifications_screen.dart';
import 'projects_screen.dart';
import 'task_detail_screen.dart';
import 'tasks_screen.dart';
import 'team_task_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final teams = TeamStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([store, teams]),
      builder: (context, _) {
        final user = store.currentUser;
        final firstName = (user?.name ?? '').split(' ').first;
        final day = _MyDay.build(store, teams, DateTime.now());

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

              // ---------------------------------------------- running timers
              for (final (team, t) in TimeTracker.running())
                RunningTimerBanner(
                  task: t,
                  team: team,
                  onOpen: () =>
                      team == null ? openTaskDetail(context, t) : openTeamTask(context, team, t),
                ),

              // ----------------------------------------------- summary card
              _SummaryCard(
                total: day.total,
                done: day.done,
                pending: day.total - day.done,
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

              // ------------------------------------------------- my day
              SectionHeader(
                title: 'My Day',
                actionLabel: 'See all',
                onAction: () => MainShell.switchTab(context, 1),
              ),
              const SizedBox(height: 4),
              const Text('Your personal tasks and team tasks assigned to you.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              const SizedBox(height: 12),
              if (day.overdue.isNotEmpty) ...[
                Text('Overdue (${day.overdue.length})',
                    style: const TextStyle(
                        color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 8),
                for (final e in day.overdue) _tile(context, e),
                const SizedBox(height: 10),
                const Text('Today',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 8),
              ],
              if (day.today.isEmpty)
                const EmptyState(
                  icon: Icons.wb_sunny_outlined,
                  title: 'Nothing planned for today',
                  subtitle: 'Tap the + button to add a task.',
                )
              else
                for (final e in day.today) _tile(context, e),
            ],
          ),
        );
      },
    );
  }
}

Widget _tile(BuildContext context, _DayItem e) {
  final team = e.team;
  final t = e.task;
  if (team == null) {
    return TaskTile(task: t, showDay: false, onTap: () => openTaskDetail(context, t));
  }
  final teams = TeamStore.instance;
  return TaskTile(
    task: t,
    showDay: false,
    teamTask: true,
    onTap: () => openTeamTask(context, team, t),
    onToggle: () => teams.setCompleted(team, t, !t.isCompleted),
    trailing: TagChip(label: team.name, color: Color(team.color)),
  );
}

/// A task on My Day; [team] is null for personal tasks.
class _DayItem {
  final TaskItem task;
  final Team? team;
  const _DayItem(this.task, this.team);
}

/// Today's and overdue tasks from personal + my team tasks.
class _MyDay {
  final List<_DayItem> today;
  final List<_DayItem> overdue;
  final int total;
  final int done;
  const _MyDay(this.today, this.overdue, this.total, this.done);

  static _MyDay build(AppStore store, TeamStore teams, DateTime now) {
    final all = [
      for (final t in store.tasks)
        if (!t.isCancelled) _DayItem(t, null),
      for (final (team, t) in teams.myTeamTasksWithTeam) _DayItem(t, team),
    ];
    final today = all.where((e) => isSameDay(e.task.startAt, now)).toList()
      ..sort((a, b) => a.task.startAt.compareTo(b.task.startAt));
    final overdue = all
        .where((e) => e.task.isOverdue && !isSameDay(e.task.startAt, now))
        .toList()
      ..sort((a, b) => a.task.startAt.compareTo(b.task.startAt));
    final done = all.where((e) => e.task.isCompleted).length;
    return _MyDay(today, overdue, all.length, done);
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
