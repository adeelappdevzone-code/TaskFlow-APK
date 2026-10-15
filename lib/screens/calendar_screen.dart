import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../widgets/common.dart';
import 'task_page.dart';
import 'create_task_dialog.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month; // first day of visible month
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = dateOnly(now);
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _month = DateTime(now.year, now.month);
      _selected = dateOnly(now);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return SafeArea(
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          // Count of (non-cancelled) tasks per day in this month.
          final counts = <int, int>{};
          for (final t in store.tasks) {
            if (t.isCancelled) continue;
            if (t.startAt.year == _month.year && t.startAt.month == _month.month) {
              counts[t.startAt.day] = (counts[t.startAt.day] ?? 0) + 1;
            }
          }
          final dayTasks = store.tasksOnDay(_selected)
            ..sort((a, b) => a.startAt.compareTo(b.startAt));

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Calendar',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                  TextButton(onPressed: _goToday, child: const Text('Today')),
                ],
              ),
              const SizedBox(height: 12),
              WhiteCard(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded),
                          onPressed: () => _changeMonth(-1),
                        ),
                        Expanded(
                          child: Text(
                            DateFormat('MMMM yyyy').format(_month),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded),
                          onPressed: () => _changeMonth(1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _MonthGrid(
                      month: _month,
                      selected: _selected,
                      counts: counts,
                      onSelect: (d) => setState(() => _selected = d),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              SectionHeader(
                title: isSameDay(_selected, DateTime.now())
                    ? "Today's Schedule"
                    : DateFormat('EEEE, d MMM').format(_selected),
                actionLabel: '+ Add',
                onAction: () => showCreateTask(context, date: _selected),
              ),
              const SizedBox(height: 12),
              if (dayTasks.isEmpty)
                const EmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'No tasks on this day',
                  subtitle: 'Enjoy the free time, or add a task.',
                )
              else
                ...dayTasks.map((t) => Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 50,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(t.isAllDay ? 'All day' : formatTime(t.startAt),
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textMuted,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                        Expanded(
                          child: TaskTile(
                            task: t,
                            showDay: false,
                            onTap: () => openTaskDetail(context, t),
                          ),
                        ),
                      ],
                    )),
            ],
          );
        },
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime selected;
  final Map<int, int> counts;
  final ValueChanged<DateTime> onSelect;

  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    const weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final offset = first.weekday - 1; // Monday = 0
    final cells = offset + daysInMonth;
    final rows = (cells / 7).ceil();
    final today = dateOnly(DateTime.now());

    return Column(
      children: [
        Row(
          children: [
            for (final w in weekDays)
              Expanded(
                child: Center(
                  child: Text(w,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _cell(r * 7 + c - offset + 1, daysInMonth, today)),
            ],
          ),
      ],
    );
  }

  Widget _cell(int day, int daysInMonth, DateTime today) {
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 46);
    final date = DateTime(month.year, month.month, day);
    final isSelected = isSameDay(date, selected);
    final isToday = isSameDay(date, today);
    final hasTasks = (counts[day] ?? 0) > 0;

    return GestureDetector(
      onTap: () => onSelect(date),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 46,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: isToday && !isSelected
                    ? Border.all(color: AppColors.primary, width: 1.5)
                    : null,
              ),
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected || isToday ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : (isToday ? AppColors.primary : AppColors.text),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: hasTasks
                    ? (isSelected ? AppColors.primary : AppColors.primary.withAlpha(150))
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
