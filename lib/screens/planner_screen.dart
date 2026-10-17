import 'package:flutter/material.dart';
import 'work_hours.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/planner.dart';
import '../data/task_repository.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import 'task_open.dart';
import 'task_ui.dart';

/// Saves new times (and/or an estimate) on one of my tasks.
void _saveTask(TaskRef r) {
  final t = r.task;
  final team = r.team;
  if (team == null) {
    AppStore.instance.saveTask(t, t.checklist, isNew: false);
  } else {
    TeamStore.instance
        .saveTask(team, t, t.checklist, isNew: false, previousAssigneeId: t.assigneeId);
  }
}

String _hm(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

/// Planner / Daily Rescue: today's work against the time in the work day,
/// and a rescue plan when it does not fit.
class PlannerScreen extends StatefulWidget {
  final bool page;
  const PlannerScreen({super.key, this.page = false});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  bool _tomorrow = false;

  /// Chosen suggestions (all on by default, see [_chosenFor]).
  Set<RescueKind>? _chosen;

  Set<RescueKind> _chosenFor(DayPlan plan) =>
      _chosen ??
      {
        for (final s in plan.suggestions)
          if (s.kind != RescueKind.timeBlock || plan.overloadMinutes > 0) s.kind
      };

  Future<void> _customize() => editWorkHours(context);

  void _apply(DayPlan plan, Set<RescueKind> chosen) {
    final changes = rescueChanges(plan, chosen);
    if (changes.isEmpty) {
      showSnack(context, 'Nothing to change.');
      return;
    }
    for (final MapEntry(key: r, value: (s, e)) in changes.entries) {
      r.task
        ..startAt = s
        ..endAt = e;
      _saveTask(r);
    }
    setState(() => _chosen = null);
    showSnack(context,
        'Plan applied: ${changes.length} ${changes.length == 1 ? 'task' : 'tasks'} updated');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppStore.instance, TeamStore.instance]),
      builder: (context, _) {
        final store = AppStore.instance;
        final now = DateTime.now();
        final day = dateOnly(now).add(Duration(days: _tomorrow ? 1 : 0));
        final plan = planDay(TaskRepository.myTasks(), day, now,
            workStart: store.workStart, workEnd: store.workEnd, workDays: store.workDays);
        final chosen = _chosenFor(plan);
        final after = plan.after(chosen);
        final showAfter = chosen.isNotEmpty && plan.suggestions.isNotEmpty;

        return LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final main = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: IconBox(icon: Icons.event_note_rounded, color: AppColors.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: PageHeader(
                        title: plan.overloadMinutes > 0 ? 'Daily Rescue' : 'Daily Planner',
                        subtitle: plan.overloadMinutes > 0
                            ? 'Your day is overloaded. Here is a smarter plan.'
                            : 'Your work for the day against the time you have.',
                      ),
                    ),
                    _DaySwitch(
                        tomorrow: _tomorrow,
                        onChanged: (v) => setState(() {
                              _tomorrow = v;
                              _chosen = null;
                            })),
                  ],
                ),
                const SizedBox(height: 16),
              ] else ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: _DaySwitch(
                      tomorrow: _tomorrow,
                      onChanged: (v) => setState(() {
                            _tomorrow = v;
                            _chosen = null;
                          })),
                ),
                const SizedBox(height: 12),
              ],
              _WorkDayLine(plan: plan, tomorrow: _tomorrow, onChange: _customize),
              const SizedBox(height: 12),
              _Banner(
                plan: plan,
                tomorrow: _tomorrow,
                onCustomize: _customize,
                onApply: plan.suggestions.isEmpty ? null : () => _apply(plan, chosen),
              ),
              const SizedBox(height: 14),
              _Tiles(plan: plan, wide: wide),
              const SizedBox(height: 14),
              _Timeline(
                title: showAfter ? 'Before rescue' : 'Your plan',
                subtitle: plan.overloadMinutes > 0
                    ? 'Your current plan has more work than time.'
                    : 'Tasks with a time stay; the rest fill your free time.',
                entries: plan.before,
                good: false,
                overloaded: plan.overloadMinutes > 0,
              ),
              if (showAfter) ...[
                const SizedBox(height: 14),
                _Timeline(
                  title: 'After rescue',
                  subtitle: 'A plan that fits, important work first.',
                  entries: after,
                  good: true,
                  overloaded: false,
                ),
              ],
            ],
          );
          final side = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Suggestions(
                plan: plan,
                chosen: chosen,
                onChanged: (s) => setState(() => _chosen = s),
              ),
              const SizedBox(height: 14),
              _SummaryCard(plan: plan, chosen: chosen),
              const SizedBox(height: 14),
              _WhyCard(
                onIgnore: () => setState(() => _chosen = {}),
                onCustomize: _customize,
                onApply: plan.suggestions.isEmpty ? null : () => _apply(plan, chosen),
              ),
            ],
          );
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: widget.page
                ? AppBar(backgroundColor: AppColors.background, title: const Text('Planner'))
                : null,
            body: ListView(
              padding: EdgeInsets.fromLTRB(wide ? 28 : 16, wide ? 22 : 8, wide ? 28 : 16, 28),
              children: [
                if (box.maxWidth >= 1150)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: main),
                      const SizedBox(width: 20),
                      SizedBox(width: 400, child: side),
                    ],
                  )
                else ...[
                  main,
                  const SizedBox(height: 14),
                  side,
                ],
              ],
            ),
          );
        });
      },
    );
  }
}

/// "Your work day: 9:00 AM – 5:30 PM • Mon–Fri • 3h 30m left" + Change.
class _WorkDayLine extends StatelessWidget {
  final DayPlan plan;
  final bool tomorrow;
  final VoidCallback onChange;
  const _WorkDayLine({required this.plan, required this.tomorrow, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final left = !plan.isWorkDay
        ? 'Day off'
        : tomorrow
            ? '${hoursText(plan.availableMinutes)} tomorrow'
            : '${hoursText(plan.availableMinutes)} left today';
    return DashCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(children: [
        const Icon(Icons.work_history_outlined, size: 20, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Your work day: ', style: TextStyle(color: AppColors.textMuted)),
              TextSpan(
                  text: workHoursText(context),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(
                  text: '  •  ${workDaysText(store.workDays)}  •  $left',
                  style: const TextStyle(color: AppColors.textMuted)),
            ]),
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
        TextButton(onPressed: onChange, child: const Text('Change')),
      ]),
    );
  }
}

class _DaySwitch extends StatelessWidget {
  final bool tomorrow;
  final ValueChanged<bool> onChanged;
  const _DaySwitch({required this.tomorrow, required this.onChanged});

  @override
  Widget build(BuildContext context) => SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Today')),
          ButtonSegment(value: true, label: Text('Tomorrow')),
        ],
        selected: {tomorrow},
        showSelectedIcon: false,
        onSelectionChanged: (s) => onChanged(s.first),
      );
}

class _Banner extends StatelessWidget {
  final DayPlan plan;
  final bool tomorrow;
  final VoidCallback onCustomize;
  final VoidCallback? onApply;
  const _Banner(
      {required this.plan,
      required this.tomorrow,
      required this.onCustomize,
      required this.onApply});

  @override
  Widget build(BuildContext context) {
    final over = plan.overloadMinutes;
    final day = tomorrow ? 'tomorrow' : 'today';
    final bad = over > 0;
    final color = bad ? AppColors.danger : AppColors.success;
    final dayOff = !plan.isWorkDay;
    final dayOver = !tomorrow && plan.availableMinutes == 0;
    final title = dayOff
        ? (tomorrow ? 'Tomorrow is not a work day.' : 'Today is not a work day.')
        : dayOver
            ? 'Your work day is over.'
            : bad
                ? "You're overloaded by ${_hm(over)} $day."
                : "Your day fits. ${_hm(plan.availableMinutes - plan.plannedMinutes)} free $day.";
    final text = dayOff
        ? 'Rescue moves extra work to your next work day. Change your work days in Working hours.'
        : dayOver
            ? 'Switch to Tomorrow to plan ahead, or change your work hours.'
            : 'Your planned work is ${_hm(plan.plannedMinutes)}, and you have '
                '${_hm(plan.availableMinutes)} available.';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(bad ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                  color: color, size: 34),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: bad ? AppColors.danger : AppColors.text)),
                    const SizedBox(height: 3),
                    Text(text, style: const TextStyle(color: Color(0xFF4B5563))),
                    if (plan.unestimatedCount > 0) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.hourglass_empty_rounded,
                            size: 16, color: Color(0xFFB45309)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                              '${plan.unestimatedCount} ${plan.unestimatedCount == 1 ? 'task has' : 'tasks have'} '
                              'no estimate (counted as ${kDefaultTaskMinutes}m). Tap "Set time" to fix.',
                              style: const TextStyle(color: Color(0xFFB45309), fontSize: 13)),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: onCustomize, child: const Text('Work hours')),
              if (bad) FilledButton(onPressed: onApply, child: const Text('Apply rescue plan')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tiles extends StatelessWidget {
  final DayPlan plan;
  final bool wide;
  const _Tiles({required this.plan, required this.wide});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      (Icons.schedule_rounded, AppColors.primary, 'Available time', _hm(plan.availableMinutes)),
      (
        Icons.event_rounded,
        AppColors.danger,
        'Planned work',
        _hm(plan.plannedMinutes),
      ),
      (Icons.error_rounded, const Color(0xFFEA7A0C), 'Overdue tasks', '${plan.overdueCount}'),
      (Icons.layers_rounded, AppColors.success, 'Flexible tasks', '${plan.flexibleCount}'),
    ];
    Widget tile((IconData, Color, String, String) t) => DashCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            IconBox(icon: t.$1, color: t.$2, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.$3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(t.$4,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: t.$2)),
                  ),
                ],
              ),
            ),
          ]),
        );
    if (wide) {
      return Row(children: [
        for (final (i, t) in tiles.indexed) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: tile(t)),
        ],
      ]);
    }
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.2,
      children: [for (final t in tiles) tile(t)],
    );
  }
}

(String, Color, Color) _markLook(PlanMark m) => switch (m) {
      PlanMark.noChange => ('No change', AppColors.textMuted, const Color(0xFFF3F4F6)),
      PlanMark.overloaded => ('Overloaded', AppColors.danger, AppColors.dangerLight),
      PlanMark.overdue => ('Overdue', AppColors.danger, AppColors.dangerLight),
      PlanMark.rescheduled => ('Rescheduled', const Color(0xFFB45309), AppColors.warningLight),
      PlanMark.focus => ('Protected', AppColors.success, AppColors.successLight),
      PlanMark.moved => ('Later', AppColors.purple, AppColors.purpleLight),
      PlanMark.scheduled => ('Scheduled', AppColors.primary, AppColors.primaryLight),
    };

class _Timeline extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<PlanEntry> entries;
  final bool good;
  final bool overloaded;
  const _Timeline(
      {required this.title,
      required this.subtitle,
      required this.entries,
      required this.good,
      required this.overloaded});

  @override
  Widget build(BuildContext context) {
    final total = entries.fold(0, (s, e) => s + e.minutes);
    final color = good ? AppColors.success : (overloaded ? AppColors.danger : AppColors.primary);
    return DashCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBox(
                  icon: good
                      ? Icons.check_box_rounded
                      : (overloaded ? Icons.warning_amber_rounded : Icons.view_agenda_outlined),
                  color: color,
                  size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: color.withAlpha(24), borderRadius: BorderRadius.circular(8)),
                child: Text('Total: ${_hm(total)}',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Nothing planned for this day.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
            ),
          for (final e in entries) _Row(e: e),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final PlanEntry e;
  const _Row({required this.e});

  Future<void> _setEstimate(BuildContext context, Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final m = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        const PopupMenuItem(enabled: false, height: 32, child: Text('How long will it take?')),
        for (final m in kEstimateChoices.where((m) => m > 0))
          PopupMenuItem(value: m, child: Text(formatMinutes(m))),
      ],
    );
    if (m == null) return;
    e.ref.task.estimateMinutes = m;
    _saveTask(e.ref);
  }

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = _markLook(e.mark);
    final f = DateFormat('h:mm a');
    final rowBg = switch (e.mark) {
      PlanMark.overloaded || PlanMark.overdue => AppColors.dangerLight.withAlpha(150),
      PlanMark.focus => AppColors.successLight.withAlpha(170),
      PlanMark.rescheduled => AppColors.warningLight.withAlpha(150),
      _ => const Color(0xFFF3F6FB),
    };
    final dot = switch (e.mark) {
      PlanMark.overloaded || PlanMark.overdue => AppColors.danger,
      PlanMark.focus => AppColors.success,
      PlanMark.rescheduled => const Color(0xFFEA7A0C),
      _ => AppColors.primary,
    };
    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 520;
      final time = Text('${f.format(e.start)} – ${f.format(e.end)}',
          style: const TextStyle(fontSize: 13, color: Color(0xFF374151)));
      final estimate = e.unestimated && e.ref.canEdit
          ? Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                onTapUp: (d) => _setEstimate(context, d.globalPosition),
                child: const Text('Set time',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB45309),
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline)),
              ),
            )
          : null;
      final bar = Material(
        color: rowBg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => openTaskRef(context, e.ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(children: [
              Icon(e.mark == PlanMark.focus ? Icons.gps_fixed_rounded : taskIconFor(e.ref),
                  size: 17, color: e.mark == PlanMark.focus ? AppColors.success : AppColors.text),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.mark == PlanMark.focus ? 'Focus: ${e.ref.task.title}' : e.ref.task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
              ),
              if (estimate != null) estimate,
            ]),
          ),
        ),
      );
      final chip = Container(
        width: 96,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
        child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
      );
      final dotW = Container(
          width: 9, height: 9, decoration: BoxDecoration(color: dot, shape: BoxShape.circle));
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: narrow
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 4), child: dotW),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [Expanded(child: time), chip]),
                    const SizedBox(height: 4),
                    bar,
                  ]),
                ),
              ])
            : Row(children: [
                dotW,
                const SizedBox(width: 12),
                SizedBox(width: 160, child: time),
                Expanded(child: bar),
                const SizedBox(width: 10),
                chip,
              ]),
      );
    });
  }
}

class _Suggestions extends StatelessWidget {
  final DayPlan plan;
  final Set<RescueKind> chosen;
  final ValueChanged<Set<RescueKind>> onChanged;
  const _Suggestions({required this.plan, required this.chosen, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    String names(List<TaskRef> l) {
      final n = l.take(2).map((r) => '"${r.task.title}"').join(' and ');
      return l.length > 2 ? '$n and ${l.length - 2} more' : n;
    }

    return DashCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Rescue suggestions',
                    style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                Text('Choose what to apply.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ]),
            ),
            if (plan.suggestions.isNotEmpty)
              TextButton(
                onPressed: () => onChanged({for (final s in plan.suggestions) s.kind}),
                child: const Text('Select all'),
              ),
          ]),
          const SizedBox(height: 8),
          if (plan.suggestions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('Nothing to change. Your day looks good.',
                  style: TextStyle(color: AppColors.textMuted)),
            ),
          for (final s in plan.suggestions)
            Builder(builder: (context) {
              final (IconData icon, Color color, String title, String text, List<String> tags) =
                  switch (s.kind) {
                RescueKind.moveLow => (
                    Icons.arrow_forward_rounded,
                    AppColors.purple,
                    'Move ${s.tasks.length} lower-priority ${s.tasks.length == 1 ? 'task' : 'tasks'} to a later day',
                    'Move ${names(s.tasks)} to your next work day with free time.',
                    ['Low / medium priority', 'Next free work day'],
                  ),
                RescueKind.overdue => (
                    Icons.history_rounded,
                    const Color(0xFFEA7A0C),
                    'Bring ${s.tasks.length} overdue ${s.tasks.length == 1 ? 'task' : 'tasks'} into today',
                    'Give ${names(s.tasks)} a date today so they are not forgotten.',
                    ['Overdue'],
                  ),
                RescueKind.timeBlock => (
                    Icons.gps_fixed_rounded,
                    AppColors.success,
                    'Give every flexible task a time',
                    'Put ${s.tasks.length} ${s.tasks.length == 1 ? 'task' : 'tasks'} in your free time, important work first (a focus block).',
                    ['Focus block', 'Calendar'],
                  ),
              };
              final on = chosen.contains(s.kind);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: on ? AppColors.primaryLight.withAlpha(90) : const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: on ? AppColors.primary.withAlpha(80) : AppColors.border),
                ),
                child: InkWell(
                  onTap: () => onChanged(on ? ({...chosen}..remove(s.kind)) : {...chosen, s.kind}),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: on,
                        onChanged: (v) => onChanged(
                            v == true ? {...chosen, s.kind} : ({...chosen}..remove(s.kind))),
                      ),
                      IconBox(icon: icon, color: color, size: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(text,
                                style: const TextStyle(fontSize: 12.5, color: Color(0xFF4B5563))),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, runSpacing: 4, children: [
                              for (final t in tags)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: color.withAlpha(22),
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Text(t,
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: color,
                                          fontWeight: FontWeight.w600)),
                                ),
                            ]),
                          ],
                        ),
                      ),
                      if (s.saves > 0) ...[
                        const SizedBox(width: 8),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          const Text('Saves',
                              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          Text(formatMinutes(s.saves),
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary)),
                        ]),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final DayPlan plan;
  final Set<RescueKind> chosen;
  const _SummaryCard({required this.plan, required this.chosen});

  @override
  Widget build(BuildContext context) {
    final rows = <(IconData, Color, String, int)>[
      for (final s in plan.suggestions)
        if (chosen.contains(s.kind))
          switch (s.kind) {
            RescueKind.moveLow => (
                Icons.arrow_forward_rounded,
                AppColors.purple,
                '${s.tasks.length} ${s.tasks.length == 1 ? 'task' : 'tasks'} moved to tomorrow',
                s.saves
              ),
            RescueKind.overdue => (
                Icons.history_rounded,
                const Color(0xFFEA7A0C),
                '${s.tasks.length} overdue ${s.tasks.length == 1 ? 'task' : 'tasks'} rescheduled',
                0
              ),
            RescueKind.timeBlock => (
                Icons.gps_fixed_rounded,
                AppColors.success,
                '${s.tasks.length} ${s.tasks.length == 1 ? 'task' : 'tasks'} given a time',
                0
              ),
          },
    ];
    final saved = plan.savedMinutes(chosen);
    return DashCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(children: [
            Icon(Icons.summarize_outlined, color: AppColors.primary),
            SizedBox(width: 10),
            Text('Rescue summary', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Text('Choose a suggestion to see what changes.',
                style: TextStyle(color: AppColors.textMuted)),
          for (final (icon, color, text, mins) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(text)),
                if (mins > 0)
                  Text(formatMinutes(mins),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 15)),
              ]),
            ),
          const Divider(height: 22, color: AppColors.border),
          Row(children: [
            const Icon(Icons.schedule_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            const Expanded(
                child: Text('Time freed today', style: TextStyle(fontWeight: FontWeight.w800))),
            Text(_hm(saved),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
          ]),
        ],
      ),
    );
  }
}

class _WhyCard extends StatelessWidget {
  final VoidCallback onIgnore;
  final VoidCallback onCustomize;
  final VoidCallback? onApply;
  const _WhyCard({required this.onIgnore, required this.onCustomize, required this.onApply});

  @override
  Widget build(BuildContext context) => DashCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(children: [
              Icon(Icons.lightbulb_rounded, color: Color(0xFFF59E0B)),
              SizedBox(width: 10),
              Text('Why this plan?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            for (final t in const [
              'Fits your work into the time you have',
              'Keeps high-priority work today',
              'Meetings and timed tasks never move',
              'Moves flexible, lower-priority work to tomorrow',
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, size: 17, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t, style: const TextStyle(fontSize: 13.5))),
                ]),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton(onPressed: onIgnore, child: const Text('Ignore')),
                OutlinedButton(onPressed: onCustomize, child: const Text('Work hours')),
                FilledButton(onPressed: onApply, child: const Text('Apply plan')),
              ],
            ),
          ],
        ),
      );
}
