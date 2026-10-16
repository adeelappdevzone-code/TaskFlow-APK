import '../data/inbox.dart';
import 'inbox_screen.dart';
import 'planner_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/activity.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../data/task_repository.dart';
import '../data/team_stats.dart';
import '../data/team_store.dart';
import '../data/time_tracker.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import '../widgets/responsive.dart';
import '../widgets/task_extras.dart';
import 'main_shell.dart';
import 'notifications_screen.dart';
import 'projects_screen.dart';
import 'task_open.dart';
import 'task_ui.dart';
import 'tasks_screen.dart';

/// Home: today's focus. My personal tasks and the team tasks assigned to me,
/// what is late, what comes next and what happened in my teams.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final teams = TeamStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([store, teams]),
      builder: (context, _) {
        final data = _HomeData(DateTime.now());
        return isWideScreen(context) ? _WideHome(data: data) : _PhoneHome(data: data);
      },
    );
  }
}

/// Everything Home shows, worked out once per build.
class _HomeData {
  final DateTime now;
  final List<TaskRef> all;
  final List<TaskRef> today;
  final List<TaskRef> overdue;
  final List<TaskRef> upcoming;
  final TaskCounts counts;
  final int doneToday;
  final int inProgress;
  final String firstName;

  factory _HomeData(DateTime now) {
    final all = TaskRepository.myTasks();
    final today = TaskRepository.today(all, now);
    return _HomeData._(
      now: now,
      all: all,
      today: today,
      overdue: TaskRepository.overdue(all, now),
      upcoming: TaskRepository.upcoming(all, now, limit: 4),
      counts: TaskCounts(all.map((r) => r.task)),
      doneToday: all
          .where((r) => r.task.isCompleted && r.task.completedAt != null)
          .where((r) => isSameDay(r.task.completedAt!, now))
          .length,
      inProgress: all.where((r) => r.task.displayStatus == DisplayStatus.inProgress).length,
      firstName: (AppStore.instance.currentUser?.name ?? '').split(' ').first,
    );
  }

  _HomeData._({
    required this.now,
    required this.all,
    required this.today,
    required this.overdue,
    required this.upcoming,
    required this.counts,
    required this.doneToday,
    required this.inProgress,
    required this.firstName,
  });

  String get greetingLine => '${greeting()}! Here is your work overview for today.';
}

// ======================================================================= wide

class _WideHome extends StatelessWidget {
  final _HomeData data;
  const _WideHome({required this.data});

  @override
  Widget build(BuildContext context) {
    final running = TimeTracker.running();
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      children: [
        // --------------------------------------------------------- header
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hello, ${data.firstName} 👋',
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(data.greetingLine,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 15)),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => MainShell.switchTab(context, 2),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(DateFormat('EEE, d MMM yyyy').format(data.now)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        for (final (team, t) in running)
          RunningTimerBanner(
            task: t,
            team: team,
            onOpen: () => openTaskRef(context, TaskRef(t, team)),
          ),

        // ----------------------------------------------- totals + glance
        LayoutBuilder(builder: (context, box) {
          // Narrower content (small laptop, or a task open in the panel):
          // cards stack instead of sitting side by side.
          final w = box.maxWidth;
          final stackTop = w < 820;
          final twoByTwo = w < 1000;
          final stackBottom = w < 900;
          const gap = SizedBox(width: 18, height: 18);
          final side = Column(
            children: [
              _ProgressCard(all: data.all, now: data.now),
              if (TeamStore.instance.teams.isNotEmpty) ...[gap, const _ActivityCard()],
              gap,
              _UpcomingCard(items: data.upcoming),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stackTop) ...[
                _TotalCard(data: data),
                gap,
                _GlanceCard(data: data, smallTiles: w < 600),
              ] else
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: _TotalCard(data: data)),
                      gap,
                      Expanded(
                          flex: 6,
                          child: _GlanceCard(data: data, smallTiles: (w - 18) * 6 / 11 < 600)),
                    ],
                  ),
                ),
              gap,
              // ------------------------------------------------ shortcuts
              for (final row in twoByTwo
                  ? [_shortcuts.sublist(0, 2), _shortcuts.sublist(2)]
                  : [_shortcuts]) ...[
                Row(
                  children: [
                    for (final (i, s) in row.indexed) ...[
                      if (i > 0) gap,
                      Expanded(child: _ShortcutCard(shortcut: s)),
                    ],
                  ],
                ),
                gap,
              ],
              // ------------------------------- my day | progress, activity
              if (stackBottom) ...[
                _MyDayCard(data: data, wide: true),
                gap,
                side,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _MyDayCard(data: data, wide: true)),
                    gap,
                    Expanded(flex: 2, child: side),
                  ],
                ),
            ],
          );
        }),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  final _HomeData data;
  const _TotalCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = data.counts;
    final open = c.inProgress + c.pending;
    return DashCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconBox(icon: Icons.inventory_2_outlined, color: AppColors.primary),
                    const SizedBox(width: 12),
                    const Flexible(
                      child: Text('Total Tasks',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('${c.total}',
                        style: const TextStyle(
                            fontSize: 46, fontWeight: FontWeight.w800, color: AppColors.primary)),
                    const SizedBox(width: 10),
                    const Flexible(
                      child: Text('Personal + assigned',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _Pill(
                        icon: Icons.check_box_rounded,
                        text: '${c.done} done',
                        color: AppColors.success,
                        bg: AppColors.successLight),
                    _Pill(
                        icon: Icons.schedule_rounded,
                        text: '$open pending',
                        color: AppColors.danger,
                        bg: AppColors.dangerLight),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            height: 130,
            child: DonutRing(
              parts: [(c.done, AppColors.primary)],
              total: c.total,
              center: '${c.pct(c.done)}%',
              caption: 'Completed',
            ),
          ),
        ],
      ),
    );
  }
}

class _GlanceCard extends StatelessWidget {
  final _HomeData data;

  /// Icon above the number (narrow tiles).
  final bool smallTiles;
  const _GlanceCard({required this.data, this.smallTiles = false});

  @override
  Widget build(BuildContext context) {
    return DashCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBox(icon: Icons.wb_sunny_rounded, color: Color(0xFFF59E0B)),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Today at a glance',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text('Your key activities for today.',
                        style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => MainShell.switchTab(context, 2),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('View Calendar'),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, size: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                  child: _GlanceTile(
                      icon: Icons.event_rounded,
                      color: AppColors.danger,
                      bg: const Color(0xFFFFF1F1),
                      value: data.today.length,
                      small: smallTiles,
                      label: 'Due today')),
              const SizedBox(width: 12),
              Expanded(
                  child: _GlanceTile(
                      icon: Icons.timelapse_rounded,
                      color: AppColors.primary,
                      bg: const Color(0xFFF0F5FF),
                      value: data.inProgress,
                      small: smallTiles,
                      label: 'In progress')),
              const SizedBox(width: 12),
              Expanded(
                  child: _GlanceTile(
                      icon: Icons.check_rounded,
                      color: AppColors.success,
                      bg: const Color(0xFFF0FBF4),
                      value: data.doneToday,
                      small: smallTiles,
                      label: 'Done today')),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlanceTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  final int value;
  final String label;
  final bool small;
  const _GlanceTile({
    required this.icon,
    required this.color,
    required this.bg,
    required this.value,
    required this.label,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(small ? 12 : 16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: small
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 8),
                Text('$value',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$value',
                          style:
                              TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
                      Text(label,
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

// ------------------------------------------------------------------ shortcuts

class _Shortcut {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final void Function(BuildContext) onTap;
  const _Shortcut(this.icon, this.color, this.title, this.subtitle, this.onTap);
}

final _shortcuts = [
  _Shortcut(Icons.format_list_bulleted_rounded, AppColors.primary, 'All Tasks',
      'View and manage all tasks', (c) => MainShell.switchTab(c, 1)),
  _Shortcut(
      Icons.flag_outlined,
      AppColors.danger,
      'High Priority',
      'Focus on important tasks',
      (c) => Navigator.push(
          c,
          MaterialPageRoute(
              builder: (_) =>
                  const TasksScreen(standalone: true, initialPriority: Priority.high)))),
  _Shortcut(Icons.calendar_month_outlined, AppColors.primary, 'Calendar', 'View your schedule',
      (c) => MainShell.switchTab(c, 2)),
  _Shortcut(Icons.folder_outlined, AppColors.purple, 'Projects', 'Browse all projects',
      (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const ProjectsScreen()))),
];

class _ShortcutCard extends StatelessWidget {
  final _Shortcut shortcut;
  const _ShortcutCard({required this.shortcut});

  @override
  Widget build(BuildContext context) {
    final s = shortcut;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => s.onTap(context),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEEF1F6)),
          ),
          child: Row(
            children: [
              IconBox(icon: s.icon, color: s.color, size: 50),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(s.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.text),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- my day

class _MyDayCard extends StatelessWidget {
  final _HomeData data;
  final bool wide;
  const _MyDayCard({required this.data, required this.wide});

  @override
  Widget build(BuildContext context) {
    final header = Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('My Day (Today)', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              Text('Your personal tasks and team tasks assigned to you.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            ],
          ),
        ),
        TextButton(
          onPressed: () => MainShell.switchTab(context, 1),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('See All', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(width: 4),
              Icon(Icons.arrow_forward_rounded, size: 16),
            ],
          ),
        ),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 14),
        if (data.overdue.isNotEmpty) ...[
          _Group(
            icon: Icons.error_rounded,
            title: 'Overdue (${data.overdue.length})',
            color: AppColors.danger,
            bg: const Color(0xFFFFF1F1),
            items: data.overdue,
            wide: wide,
            showDate: true,
          ),
          const SizedBox(height: 14),
        ],
        if (data.today.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(
              children: [
                Icon(Icons.wb_sunny_outlined, color: AppColors.primary, size: 30),
                SizedBox(height: 8),
                Text('Nothing planned for today',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                SizedBox(height: 2),
                Text('Use New Task to plan something.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ],
            ),
          )
        else
          _Group(
            icon: Icons.schedule_rounded,
            title: 'Today (${data.today.length})',
            color: AppColors.primary,
            bg: const Color(0xFFF0F5FF),
            items: data.today,
            wide: wide,
          ),
      ],
    );
    return wide ? DashCard(padding: const EdgeInsets.all(20), child: body) : body;
  }
}

/// "Overdue (1)" / "Today (4)" box with its tasks.
class _Group extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final Color bg;
  final List<TaskRef> items;
  final bool wide;
  final bool showDate;
  const _Group({
    required this.icon,
    required this.title,
    required this.color,
    required this.bg,
    required this.items,
    required this.wide,
    this.showDate = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEF1F6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: bg,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Text('${items.length} ${items.length == 1 ? 'task' : 'tasks'}',
                    style: TextStyle(color: color, fontSize: 13)),
              ],
            ),
          ),
          for (final (i, r) in items.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            _TaskRow(ref: r, wide: wide, showDate: showDate),
          ],
        ],
      ),
    );
  }
}

/// One task line: tick box, icon, title, time, team/project/Personal, menu.
class _TaskRow extends StatelessWidget {
  final TaskRef ref;
  final bool wide;
  final bool showDate;
  const _TaskRow({required this.ref, required this.wide, this.showDate = false});

  @override
  Widget build(BuildContext context) {
    final t = ref.task;
    final done = t.isCompleted;
    final late = !done && (t.endAt ?? t.startAt).isBefore(DateTime.now());
    final range = timeRangeText(t.startAt, t.endAt);
    final when = showDate ? '${DateFormat('d MMM').format(t.startAt)}, $range' : range;
    final timeStyle = TextStyle(
      fontSize: 13.5,
      color: late ? AppColors.danger : AppColors.textMuted,
      fontWeight: late ? FontWeight.w600 : FontWeight.w500,
    );
    final title = Text(t.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: done ? AppColors.textMuted : AppColors.text,
          decoration: done ? TextDecoration.lineThrough : null,
        ));

    return InkWell(
      onTap: () => openTaskRef(context, ref),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, wide ? 10 : 8, 4, wide ? 10 : 8),
        child: Row(
          children: [
            TickBox(
              value: done,
              onChanged: ref.canComplete ? (v) => ref.setCompleted(v) : null,
            ),
            const SizedBox(width: 10),
            IconBox(icon: taskIconFor(ref), color: Color(ref.sourceColor), size: 36),
            const SizedBox(width: 12),
            if (wide) ...[
              Expanded(child: title),
              if (t.timerRunning)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.timer_rounded, size: 16, color: AppColors.primary),
                ),
              SizedBox(width: showDate ? 150 : 110, child: Text(when, style: timeStyle)),
              SizedBox(
                width: 130,
                child: Align(alignment: Alignment.centerLeft, child: SourceChip(ref: ref)),
              ),
            ] else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(when, maxLines: 1, style: timeStyle.copyWith(fontSize: 12.5)),
                        const SizedBox(width: 8),
                        Flexible(child: SourceChip(ref: ref, small: true)),
                      ],
                    ),
                  ],
                ),
              ),
            TaskActionsMenu(ref: ref),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- progress

enum _Period { week, month, all }

class _ProgressCard extends StatefulWidget {
  final List<TaskRef> all;
  final DateTime now;
  const _ProgressCard({required this.all, required this.now});

  @override
  State<_ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends State<_ProgressCard> {
  _Period _period = _Period.week;

  static String _label(_Period p) => switch (p) {
        _Period.week => 'This Week',
        _Period.month => 'This Month',
        _Period.all => 'All Time',
      };

  @override
  Widget build(BuildContext context) {
    final now = widget.now;
    final (DateTime? from, DateTime? to) = switch (_period) {
      _Period.week => (
          TeamStats.weekStart(now),
          TeamStats.weekStart(now).add(const Duration(days: 7))
        ),
      _Period.month => (DateTime(now.year, now.month), DateTime(now.year, now.month + 1)),
      _Period.all => (null, null),
    };
    final tasks = widget.all
        .map((r) => r.task)
        .where((t) => from == null || (!t.startAt.isBefore(from) && t.startAt.isBefore(to!)));
    final c = TaskCounts(tasks);

    Widget legend(Color color, String label, int n) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text('$n $label', style: const TextStyle(fontSize: 14))),
              Text('${c.pct(n)}%',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return DashCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBox(icon: Icons.bar_chart_rounded, color: AppColors.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Task Progress',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text('Task completion overview.',
                        style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  ],
                ),
              ),
              PopupMenuButton<_Period>(
                tooltip: 'Period',
                position: PopupMenuPosition.under,
                onSelected: (p) => setState(() => _period = p),
                itemBuilder: (_) => [
                  for (final p in _Period.values) PopupMenuItem(value: p, child: Text(_label(p))),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_label(_period), style: const TextStyle(fontSize: 13)),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: DonutRing(
                  parts: [
                    (c.done, AppColors.success),
                    (c.inProgress, AppColors.primary),
                    (c.pending, AppColors.danger),
                  ],
                  total: c.total,
                  center: '${c.pct(c.done)}%',
                  caption: 'Completed',
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  children: [
                    legend(AppColors.success, 'Completed', c.done),
                    legend(AppColors.primary, 'In Progress', c.inProgress),
                    legend(AppColors.danger, 'Pending', c.pending),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- activity

class _ActivityCard extends StatelessWidget {
  final bool wide;
  const _ActivityCard({this.wide = true});

  @override
  Widget build(BuildContext context) {
    final teams = TeamStore.instance;
    final me = teams.uid ?? '';
    final myName = AppStore.instance.currentUser?.name ?? 'You';
    final items = recentActivity(
      teams: teams.teams,
      tasksOf: teams.tasksOf,
      invitesOf: (id) => teams.sentInvites[id] ?? const [],
      me: me,
      limit: 4,
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const IconBox(icon: Icons.groups_outlined, color: AppColors.primary),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Team Activity',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('Recent activity from your teams.',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                ],
              ),
            ),
            TextButton(
              onPressed: () => MainShell.switchTab(context, 4),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('View All', style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 16),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No team activity yet.', style: TextStyle(color: AppColors.textMuted)),
          ),
        for (final a in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Avatar(
                    name: a.actor == 'You' ? myName : (a.actor.isEmpty ? a.object : a.actor),
                    size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      if (a.actor.isNotEmpty)
                        TextSpan(
                            text: '${a.actor} ',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: '${a.verb} '),
                      TextSpan(
                          text: a.object,
                          style: const TextStyle(
                              color: AppColors.primary, fontWeight: FontWeight.w600)),
                      TextSpan(text: a.suffix),
                    ]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, color: AppColors.text),
                  ),
                ),
                const SizedBox(width: 8),
                Text(timeAgo(a.at),
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
      ],
    );
    return wide ? DashCard(padding: const EdgeInsets.all(18), child: body) : body;
  }
}

// ------------------------------------------------------------------- upcoming

class _UpcomingCard extends StatelessWidget {
  final List<TaskRef> items;
  final bool wide;
  const _UpcomingCard({required this.items, this.wide = true});

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            IconBox(icon: Icons.event_note_outlined, color: AppColors.primary),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Upcoming', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('Next scheduled tasks after today.',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nothing scheduled yet.', style: TextStyle(color: AppColors.textMuted)),
          ),
        for (final r in items)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => openTaskRef(context, r),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  TickBox(
                      value: r.task.isCompleted,
                      onChanged: r.canComplete ? (v) => r.setCompleted(v) : null),
                  const SizedBox(width: 8),
                  IconBox(icon: taskIconFor(r), color: Color(r.sourceColor), size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(
                            '${relativeDay(r.task.startAt)} • ${timeRangeText(r.task.startAt, r.task.endAt)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: SourceChip(ref: r, small: true),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    return wide ? DashCard(padding: const EdgeInsets.all(18), child: body) : body;
  }
}

// ---------------------------------------------------------------------- phone

class _PhoneHome extends StatelessWidget {
  final _HomeData data;
  const _PhoneHome({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = data.counts;
    final hasTeams = TeamStore.instance.teams.isNotEmpty;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hello, ${data.firstName} 👋',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(data.greetingLine,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Planner',
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PlannerScreen(page: true))),
                icon: const Icon(Icons.event_note_outlined, size: 26),
              ),
              ListenableBuilder(
                listenable: InboxStore.instance,
                builder: (context, _) => IconButton(
                  tooltip: 'Inbox',
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const InboxScreen(page: true))),
                  icon: Badge(
                    isLabelVisible: InboxStore.instance.count > 0,
                    label: Text('${InboxStore.instance.count}'),
                    child: const Icon(Icons.inbox_outlined, size: 27),
                  ),
                ),
              ),
              _BellButton(count: AppStore.instance.unreadCount),
            ],
          ),
          const SizedBox(height: 16),
          for (final (team, t) in TimeTracker.running())
            RunningTimerBanner(
              task: t,
              team: team,
              onOpen: () => openTaskRef(context, TaskRef(t, team)),
            ),
          _PhoneSummary(counts: c),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _GlanceTile(
                      small: true,
                      icon: Icons.event_rounded,
                      color: AppColors.danger,
                      bg: const Color(0xFFFFF1F1),
                      value: data.today.length,
                      label: 'Due today')),
              const SizedBox(width: 10),
              Expanded(
                  child: _GlanceTile(
                      small: true,
                      icon: Icons.timelapse_rounded,
                      color: AppColors.primary,
                      bg: const Color(0xFFF0F5FF),
                      value: data.inProgress,
                      label: 'In progress')),
              const SizedBox(width: 10),
              Expanded(
                  child: _GlanceTile(
                      small: true,
                      icon: Icons.check_rounded,
                      color: AppColors.success,
                      bg: const Color(0xFFF0FBF4),
                      value: data.doneToday,
                      label: 'Done today')),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final (i, s) in _shortcuts.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _PhoneShortcut(shortcut: s)),
              ],
            ],
          ),
          const SizedBox(height: 22),
          _MyDayCard(data: data, wide: false),
          const SizedBox(height: 22),
          _UpcomingCard(items: data.upcoming, wide: false),
          if (hasTeams) ...[
            const SizedBox(height: 22),
            const _ActivityCard(wide: false),
          ],
        ],
      ),
    );
  }
}

class _PhoneSummary extends StatelessWidget {
  final TaskCounts counts;
  const _PhoneSummary({required this.counts});

  @override
  Widget build(BuildContext context) {
    final c = counts;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2F7CF6), AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withAlpha(60), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Tasks', style: TextStyle(color: Colors.white70, fontSize: 13.5)),
                Text('${c.total}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('${c.done} done  •  ${c.inProgress + c.pending} pending',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(
                    value: c.progress,
                    strokeWidth: 6,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                Text('${c.pct(c.done)}%',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneShortcut extends StatelessWidget {
  final _Shortcut shortcut;
  const _PhoneShortcut({required this.shortcut});

  @override
  Widget build(BuildContext context) {
    final s = shortcut;
    return WhiteCard(
      onTap: () => s.onTap(context),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Column(
        children: [
          IconBox(icon: s.icon, color: s.color, size: 40),
          const SizedBox(height: 6),
          Text(s.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.2)),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------- shared

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final Color bg;
  const _Pill({required this.icon, required this.text, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class _BellButton extends StatelessWidget {
  final int count;
  const _BellButton({required this.count});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 9 ? '9+' : '$count'),
        child: const Icon(Icons.notifications_none_rounded, size: 28),
      ),
    );
  }
}
