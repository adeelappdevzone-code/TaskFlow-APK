import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../data/task_repository.dart';
import '../data/team_stats.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import '../widgets/responsive.dart';
import 'create_task_dialog.dart';
import 'task_open.dart';
import 'task_ui.dart';

enum _View { day, week, month }

/// Calendar of my tasks (personal + assigned team tasks): day and week time
/// grids and a month overview. Tap a task to open it, an empty slot to add one.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  _View _view = _View.week;
  DateTime _day = dateOnly(DateTime.now());

  void _today() => setState(() => _day = dateOnly(DateTime.now()));

  void _move(int dir) => setState(() {
        _day = switch (_view) {
          _View.day => DateTime(_day.year, _day.month, _day.day + dir),
          _View.week => DateTime(_day.year, _day.month, _day.day + 7 * dir),
          _View.month => DateTime(_day.year, _day.month + dir, 1),
        };
      });

  List<DateTime> get _weekDays {
    final monday = TeamStats.weekStart(_day);
    return [for (var i = 0; i < 7; i++) DateTime(monday.year, monday.month, monday.day + i)];
  }

  String get _title {
    switch (_view) {
      case _View.day:
        return DateFormat('EEEE, d MMMM yyyy').format(_day);
      case _View.month:
        return DateFormat('MMMM yyyy').format(_day);
      case _View.week:
        final d = _weekDays;
        if (d.first.month == d.last.month) return DateFormat('MMMM yyyy').format(d.first);
        return '${DateFormat('MMM').format(d.first)} – ${DateFormat('MMM yyyy').format(d.last)}';
    }
  }

  void _openDay(DateTime d) => setState(() {
        _day = dateOnly(d);
        _view = _View.day;
      });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppStore.instance, TeamStore.instance]),
      builder: (context, _) {
        final refs = TaskRepository.myTasks();
        return isWideScreen(context) ? _wide(context, refs) : _phone(context, refs);
      },
    );
  }

  // ===================================================================== wide

  Widget _wide(BuildContext context, List<TaskRef> refs) {
    final screenH = MediaQuery.sizeOf(context).height;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Calendar', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text('Manage your tasks and schedule.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => showCreateTask(context, date: _day),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Task', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            _OutlineBox(onTap: _today, child: const Text('Today')),
            const SizedBox(width: 12),
            _OutlineBox(
                onTap: () => _move(-1),
                tooltip: 'Previous',
                child: const Icon(Icons.chevron_left_rounded)),
            const SizedBox(width: 12),
            _OutlineBox(
                onTap: () => _move(1),
                tooltip: 'Next',
                child: const Icon(Icons.chevron_right_rounded)),
            const SizedBox(width: 20),
            Expanded(
              child: Text(_title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
            _ViewSwitch(view: _view, onChanged: (v) => setState(() => _view = v)),
          ],
        ),
        const SizedBox(height: 16),
        DashCard(
          padding: EdgeInsets.zero,
          child: switch (_view) {
            _View.month => _MonthView(
                month: _day,
                refs: refs,
                onOpenDay: _openDay,
                rowHeight: ((screenH - 330) / 6).clamp(96.0, 150.0),
              ),
            _View.week => _TimeGrid(days: _weekDays, refs: refs, onHeaderTap: _openDay),
            _View.day => _TimeGrid(days: [_day], refs: refs),
          },
        ),
      ],
    );
  }

  // ==================================================================== phone

  Widget _phone(BuildContext context, List<TaskRef> refs) {
    final dayRefs = refs.where((r) => isSameDay(r.task.startAt, _day)).toList()
      ..sort((a, b) => a.task.startAt.compareTo(b.task.startAt));
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Row(
            children: [
              const Expanded(
                child:
                    Text('Calendar', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              ),
              TextButton(onPressed: _today, child: const Text('Today')),
              IconButton.filled(
                tooltip: 'New task',
                onPressed: () => showCreateTask(context, date: _day),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ViewSwitch(view: _view, onChanged: (v) => setState(() => _view = v), expand: true),
          const SizedBox(height: 12),
          WhiteCard(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                        icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _move(-1)),
                    Expanded(
                      child: Text(_title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                        icon: const Icon(Icons.chevron_right_rounded), onPressed: () => _move(1)),
                  ],
                ),
                switch (_view) {
                  _View.month => _PhoneMonth(
                      month: _day,
                      selected: _day,
                      refs: refs,
                      onSelect: (d) => setState(() => _day = d)),
                  _View.week => _WeekStrip(
                      days: _weekDays,
                      selected: _day,
                      refs: refs,
                      onSelect: (d) => setState(() => _day = d)),
                  _View.day => const SizedBox.shrink(),
                },
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_view == _View.day)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ColoredBox(
                  color: Colors.white, child: _TimeGrid(days: [_day], refs: refs, gutter: 56)),
            )
          else ...[
            Text(
                isSameDay(_day, DateTime.now())
                    ? "Today's schedule"
                    : DateFormat('EEEE, d MMM').format(_day),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (dayRefs.isEmpty)
              const EmptyState(
                icon: Icons.event_available_outlined,
                title: 'No tasks on this day',
                subtitle: 'Enjoy the free time, or add a task.',
              )
            else
              for (final r in dayRefs) _AgendaTile(ref: r),
          ],
        ],
      ),
    );
  }
}

// ==================================================================== pieces

/// Event color: done green, otherwise by priority.
Color _colorOf(TaskItem t) {
  if (t.isCompleted) return AppColors.success;
  return switch (t.priority) {
    Priority.high => AppColors.danger,
    Priority.medium => AppColors.primary,
    Priority.low => AppColors.purple,
  };
}

class _OutlineBox extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final String? tooltip;
  const _OutlineBox({required this.child, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final box = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 48,
          constraints: const BoxConstraints(minWidth: 56),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), child: child),
        ),
      ),
    );
    return tooltip == null ? box : Tooltip(message: tooltip!, child: box);
  }
}

class _ViewSwitch extends StatelessWidget {
  final _View view;
  final ValueChanged<_View> onChanged;
  final bool expand;
  const _ViewSwitch({required this.view, required this.onChanged, this.expand = false});

  @override
  Widget build(BuildContext context) {
    Widget item(_View v, String label) {
      final on = view == v;
      final child = InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(v),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: expand ? 0 : 30, vertical: expand ? 10 : 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: on ? Colors.white : AppColors.text)),
        ),
      );
      return expand ? Expanded(child: child) : child;
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          item(_View.day, 'Day'),
          item(_View.week, 'Week'),
          item(_View.month, 'Month'),
        ],
      ),
    );
  }
}

// ================================================================ time grid

/// Hours down the side, one column per day, tasks placed by their time.
/// Tasks without a time sit in an "All day" row on top.
class _TimeGrid extends StatelessWidget {
  final List<DateTime> days;
  final List<TaskRef> refs;
  final ValueChanged<DateTime>? onHeaderTap;
  final double gutter;
  const _TimeGrid({required this.days, required this.refs, this.onHeaderTap, this.gutter = 90});

  static const _hourHeight = 56.0;

  @override
  Widget build(BuildContext context) {
    final perDay = [
      for (final d in days) refs.where((r) => isSameDay(r.task.startAt, d)).toList(),
    ];
    final timed = [for (final l in perDay) l.where((r) => !r.task.isAllDay).toList()];
    final allDay = [for (final l in perDay) l.where((r) => r.task.isAllDay).toList()];

    // Hours shown: at least 9 AM – 7 PM, more if tasks fall outside.
    var startHour = 9, endHour = 19;
    for (final l in timed) {
      for (final r in l) {
        final s = r.task.startAt;
        final e = r.task.endAt ?? s.add(const Duration(hours: 1));
        startHour = math.min(startHour, s.hour);
        final endH = isSameDay(e, s) ? (e.minute > 0 ? e.hour + 1 : e.hour) : 24;
        endHour = math.max(endHour, endH);
      }
    }
    final hours = endHour - startHour;
    final today = dateOnly(DateTime.now());
    const line = BorderSide(color: Color(0xFFEDF0F5));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --------------------------------------------------------- header
        if (days.length > 1)
          Container(
            decoration: const BoxDecoration(border: Border(bottom: line)),
            child: Row(
              children: [
                SizedBox(width: gutter),
                for (final d in days)
                  Expanded(
                    child: InkWell(
                      onTap: onHeaderTap == null ? null : () => onHeaderTap!(d),
                      child: Container(
                        decoration: const BoxDecoration(border: Border(left: line)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: _DayHead(day: d, today: isSameDay(d, today))),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (allDay.any((l) => l.isNotEmpty))
          Container(
            decoration: const BoxDecoration(border: Border(bottom: line)),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: gutter,
                    child: const Center(
                      child: Text('All day',
                          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    ),
                  ),
                  for (final l in allDay)
                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(border: Border(left: line)),
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          children: [
                            for (final r in l)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: _Pill(ref: r),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        // ----------------------------------------------------------- body
        SizedBox(
          height: hours * _hourHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: gutter,
                child: Stack(
                  children: [
                    for (var h = 0; h < hours; h++)
                      Positioned(
                        top: h * _hourHeight + 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Text(DateFormat('h a').format(DateTime(2000, 1, 1, startHour + h)),
                              style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                        ),
                      ),
                  ],
                ),
              ),
              for (final (i, d) in days.indexed)
                Expanded(
                  child: _DayColumn(
                    day: d,
                    refs: timed[i],
                    startHour: startHour,
                    hours: hours,
                    hourHeight: _hourHeight,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayHead extends StatelessWidget {
  final DateTime day;
  final bool today;
  const _DayHead({required this.day, required this.today});

  @override
  Widget build(BuildContext context) {
    final fg = today ? Colors.white : AppColors.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: today ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(DateFormat('EEE').format(day),
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: today ? Colors.white : AppColors.textMuted)),
          Text('${day.day}',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: fg)),
        ],
      ),
    );
  }
}

/// One day: hour lines, the tasks (side by side when they overlap) and
/// a tap on an empty hour to add a task then.
class _DayColumn extends StatelessWidget {
  final DateTime day;
  final List<TaskRef> refs;
  final int startHour;
  final int hours;
  final double hourHeight;
  const _DayColumn({
    required this.day,
    required this.refs,
    required this.startHour,
    required this.hours,
    required this.hourHeight,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...refs]..sort((a, b) => a.task.startAt.compareTo(b.task.startAt));
    DateTime endOf(TaskItem t) {
      final e = t.endAt ?? t.startAt.add(const Duration(hours: 1));
      final min = t.startAt.add(const Duration(minutes: 30));
      final end = e.isBefore(min) ? min : e;
      return isSameDay(end, t.startAt) ? end : DateTime(day.year, day.month, day.day, 23, 59);
    }

    // Lanes: a task goes into the first lane that is free at its start.
    final laneEnds = <DateTime>[];
    final lane = <TaskRef, int>{};
    for (final r in sorted) {
      var i = laneEnds.indexWhere((e) => !e.isAfter(r.task.startAt));
      if (i < 0) {
        laneEnds.add(endOf(r.task));
        i = laneEnds.length - 1;
      } else {
        laneEnds[i] = endOf(r.task);
      }
      lane[r] = i;
    }
    final lanes = math.max(1, laneEnds.length);
    double y(DateTime t) => ((t.hour - startHour) * 60 + t.minute) / 60 * hourHeight;

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return Container(
        decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFFEDF0F5)))),
        child: Stack(
          children: [
            for (var h = 0; h < hours; h++)
              Positioned(
                top: h * hourHeight,
                left: 0,
                right: 0,
                height: hourHeight,
                child: InkWell(
                  onTap: () => showCreateTask(context,
                      date: day, time: TimeOfDay(hour: startHour + h, minute: 0)),
                  child: Container(
                    decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0xFFEDF0F5)))),
                  ),
                ),
              ),
            for (final r in sorted)
              Positioned(
                top: y(r.task.startAt).clamp(0.0, hours * hourHeight) + 2,
                height: math.max(
                    26.0,
                    (y(endOf(r.task)) - y(r.task.startAt))
                            .clamp(0.0, hours * hourHeight - y(r.task.startAt)) -
                        4),
                left: w / lanes * lane[r]! + 4,
                width: w / lanes - 8,
                child: _Event(ref: r),
              ),
          ],
        ),
      );
    });
  }
}

class _Event extends StatelessWidget {
  final TaskRef ref;
  const _Event({required this.ref});

  @override
  Widget build(BuildContext context) {
    final t = ref.task;
    final c = _colorOf(t);
    return Tooltip(
      message: '${t.title} • ${ref.sourceLabel}',
      child: Material(
        color: c.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openTaskRef(context, ref),
          child: Container(
            decoration: BoxDecoration(border: Border(left: BorderSide(color: c, width: 4))),
            padding: const EdgeInsets.fromLTRB(10, 5, 6, 4),
            child: LayoutBuilder(
              builder: (context, box) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      maxLines: box.maxHeight > 60 ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color.lerp(c, Colors.black, 0.45),
                        decoration: t.isCompleted ? TextDecoration.lineThrough : null,
                      )),
                  if (box.maxHeight > 38)
                    Text(timeRangeText(t.startAt, t.endAt),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(fontSize: 12.5, color: Color.lerp(c, Colors.black, 0.2))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small one-line task chip (all-day row, month cells).
class _Pill extends StatelessWidget {
  final TaskRef ref;
  final bool showTime;
  const _Pill({required this.ref, this.showTime = false});

  @override
  Widget build(BuildContext context) {
    final t = ref.task;
    final c = _colorOf(t);
    return Material(
      color: c.withAlpha(26),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => openTaskRef(context, ref),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: c, width: 3))),
          child: Text(
            showTime && !t.isAllDay ? '${formatTime(t.startAt)} ${t.title}' : t.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color.lerp(c, Colors.black, 0.4),
              decoration: t.isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================== month view

List<List<DateTime>> _monthWeeks(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final start = first.subtract(Duration(days: first.weekday - 1));
  final last = DateTime(month.year, month.month + 1, 0);
  final weeks = <List<DateTime>>[];
  var d = start;
  while (!d.isAfter(last)) {
    weeks.add([for (var i = 0; i < 7; i++) DateTime(d.year, d.month, d.day + i)]);
    d = DateTime(d.year, d.month, d.day + 7);
  }
  return weeks;
}

class _MonthView extends StatelessWidget {
  final DateTime month;
  final List<TaskRef> refs;
  final ValueChanged<DateTime> onOpenDay;
  final double rowHeight;
  const _MonthView(
      {required this.month, required this.refs, required this.onOpenDay, required this.rowHeight});

  @override
  Widget build(BuildContext context) {
    final weeks = _monthWeeks(month);
    final today = dateOnly(DateTime.now());
    const line = BorderSide(color: Color(0xFFEDF0F5));
    return Column(
      children: [
        Row(
          children: [
            for (final w in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(w,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  ),
                ),
              ),
          ],
        ),
        for (final week in weeks)
          SizedBox(
            height: rowHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final d in week)
                  Expanded(
                    child: _MonthCell(
                      day: d,
                      inMonth: d.month == month.month,
                      today: isSameDay(d, today),
                      refs: (refs.where((r) => isSameDay(r.task.startAt, d)).toList()
                        ..sort((a, b) => a.task.startAt.compareTo(b.task.startAt))),
                      onOpenDay: onOpenDay,
                      border: const Border(top: line, left: line),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  final DateTime day;
  final bool inMonth;
  final bool today;
  final List<TaskRef> refs;
  final ValueChanged<DateTime> onOpenDay;
  final Border border;
  const _MonthCell({
    required this.day,
    required this.inMonth,
    required this.today,
    required this.refs,
    required this.onOpenDay,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onOpenDay(day),
      child: Container(
        decoration: BoxDecoration(
          border: border,
          color: inMonth ? null : const Color(0xFFFAFBFD),
        ),
        padding: const EdgeInsets.all(6),
        child: LayoutBuilder(builder: (context, box) {
          final fit = math.max(0, ((box.maxHeight - 32) / 24).floor());
          final shown = refs.length > fit ? math.max(0, fit - 1) : refs.length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: today ? AppColors.primary : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Text('${day.day}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: today
                          ? Colors.white
                          : (inMonth ? AppColors.text : const Color(0xFFB8BEC8)),
                    )),
              ),
              const SizedBox(height: 4),
              for (final r in refs.take(shown))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: _Pill(ref: r, showTime: true),
                ),
              if (refs.length > shown)
                Text('+${refs.length - shown} more',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
            ],
          );
        }),
      ),
    );
  }
}

// ==================================================================== phone

class _PhoneMonth extends StatelessWidget {
  final DateTime month;
  final DateTime selected;
  final List<TaskRef> refs;
  final ValueChanged<DateTime> onSelect;
  const _PhoneMonth(
      {required this.month, required this.selected, required this.refs, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    return Column(
      children: [
        Row(
          children: [
            for (final w in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
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
        for (final week in _monthWeeks(month))
          Row(
            children: [
              for (final d in week)
                Expanded(
                  child: _DayDot(
                    day: d,
                    dim: d.month != month.month,
                    selected: isSameDay(d, selected),
                    today: isSameDay(d, today),
                    has: refs.any((r) => isSameDay(r.task.startAt, d)),
                    onTap: () => onSelect(d),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _WeekStrip extends StatelessWidget {
  final List<DateTime> days;
  final DateTime selected;
  final List<TaskRef> refs;
  final ValueChanged<DateTime> onSelect;
  const _WeekStrip(
      {required this.days, required this.selected, required this.refs, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    return Row(
      children: [
        for (final d in days)
          Expanded(
            child: Column(
              children: [
                Text(DateFormat('EEE').format(d),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                _DayDot(
                  day: d,
                  selected: isSameDay(d, selected),
                  today: isSameDay(d, today),
                  has: refs.any((r) => isSameDay(r.task.startAt, d)),
                  onTap: () => onSelect(d),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DayDot extends StatelessWidget {
  final DateTime day;
  final bool selected;
  final bool today;
  final bool has;
  final bool dim;
  final VoidCallback onTap;
  const _DayDot({
    required this.day,
    required this.selected,
    required this.today,
    required this.has,
    required this.onTap,
    this.dim = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                color: selected ? AppColors.primary : Colors.transparent,
                shape: BoxShape.circle,
                border:
                    today && !selected ? Border.all(color: AppColors.primary, width: 1.5) : null,
              ),
              child: Text('${day.day}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected || today ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? Colors.white
                        : (today
                            ? AppColors.primary
                            : (dim ? const Color(0xFFB8BEC8) : AppColors.text)),
                  )),
            ),
            const SizedBox(height: 2),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: has ? AppColors.primary : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgendaTile extends StatelessWidget {
  final TaskRef ref;
  const _AgendaTile({required this.ref});

  @override
  Widget build(BuildContext context) {
    final t = ref.task;
    final c = _colorOf(t);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(t.isAllDay ? 'All day' : formatTime(t.startAt),
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            ),
          ),
          Expanded(
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => openTaskRef(context, ref),
                child: Container(
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: c, width: 4))),
                  padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
                  child: Row(
                    children: [
                      TickBox(
                          value: t.isCompleted,
                          onChanged: ref.canComplete ? (v) => tickTask(context, ref, v) : null),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  decoration: t.isCompleted ? TextDecoration.lineThrough : null,
                                )),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(timeRangeText(t.startAt, t.endAt),
                                      maxLines: 1,
                                      style: const TextStyle(
                                          fontSize: 12.5, color: AppColors.textMuted)),
                                ),
                                const SizedBox(width: 8),
                                Flexible(child: SourceChip(ref: ref, small: true)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      StatusChip(task: t),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
