import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/app_store.dart';
import '../widgets/common.dart';

// My work day: start / end time and work days. Used by the Daily Planner
// (what fits in a day, where moved tasks go) and Team Workload (capacity).

const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _time(BuildContext context, int minutes) =>
    TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

/// "Mon–Fri", "Mon–Sat", "Mon, Wed, Fri".
String workDaysText(List<int> days) {
  final d = [...days]..sort();
  if (d.isEmpty) return 'No days';
  if (d.length == 7) return 'Every day';
  final run = d.last - d.first + 1 == d.length;
  if (run && d.length > 2) return '${_dayNames[d.first - 1]}–${_dayNames[d.last - 1]}';
  return d.map((x) => _dayNames[x - 1]).join(', ');
}

/// "9:00 AM – 5:30 PM".
String workHoursText(BuildContext context) {
  final s = AppStore.instance;
  return '${_time(context, s.workStart)} – ${_time(context, s.workEnd)}';
}

/// "8h 30m".
String hoursText(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// Edit my work hours and work days.
Future<void> editWorkHours(BuildContext context) async {
  final store = AppStore.instance;
  var start = TimeOfDay(hour: store.workStart ~/ 60, minute: store.workStart % 60);
  var end = TimeOfDay(hour: store.workEnd ~/ 60, minute: store.workEnd % 60);
  final days = {...store.workDays};
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final mins = (end.hour * 60 + end.minute) - (start.hour * 60 + start.minute);
        return AlertDialog(
          title: const Text('Your working hours'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                    'The planner fits your tasks into these hours and moves extra work to your '
                    'next work day. Your team sees your weekly hours in Team Workload.',
                    style: TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: 12),
                for (final (label, isStart) in [('Start', true), ('End', false)])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(isStart ? Icons.wb_sunny_outlined : Icons.nights_stay_outlined),
                    title: Text(label),
                    trailing: Text((isStart ? start : end).format(ctx),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    onTap: () async {
                      final t =
                          await showTimePicker(context: ctx, initialTime: isStart ? start : end);
                      if (t != null) setState(() => isStart ? start = t : end = t);
                    },
                  ),
                const SizedBox(height: 6),
                const Text('Work days', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        tooltip: _dayNames[d - 1],
                        label: Text(_dayLetters[d - 1]),
                        showCheckmark: false,
                        selected: days.contains(d),
                        onSelected: (on) => setState(() => on ? days.add(d) : days.remove(d)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  mins > 0 && days.isNotEmpty
                      ? '${hoursText(mins)} a day • ${hoursText(mins * days.length)} a week'
                      : 'Pick an end after the start and at least one day.',
                  style: TextStyle(
                      color: mins > 0 && days.isNotEmpty ? AppColors.textMuted : AppColors.danger,
                      fontSize: 13),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        );
      },
    ),
  );
  if (ok != true) return;
  final s = start.hour * 60 + start.minute, e = end.hour * 60 + end.minute;
  if (e <= s) {
    if (context.mounted) showSnack(context, 'The end must be after the start.');
    return;
  }
  if (days.isEmpty) {
    if (context.mounted) showSnack(context, 'Pick at least one work day.');
    return;
  }
  store.setWorkHours(s, e, days.toList());
  if (context.mounted) showSnack(context, 'Working hours saved');
}
