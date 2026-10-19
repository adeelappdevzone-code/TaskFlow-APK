import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../data/planner.dart' show taskMinutes;
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../data/workload.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import 'create_task_dialog.dart';
import 'task_open.dart';
import 'task_ui.dart';

String _h(int minutes) {
  final h = minutes / 60;
  return h == h.roundToDouble() ? '${h.round()}h' : '${h.toStringAsFixed(1)}h';
}

Color _loadColor(double r) => r > 1
    ? AppColors.danger
    : r >= 0.85
        ? const Color(0xFFEA7A0C)
        : r >= 0.5
            ? AppColors.primary
            : AppColors.success;

enum _View { workload, tasks, capacity }

/// Team Workload: who has how much work against their hours, and where to
/// move work so nobody is overloaded.
class WorkloadScreen extends StatefulWidget {
  final bool page;
  const WorkloadScreen({super.key, this.page = false});

  @override
  State<WorkloadScreen> createState() => _WorkloadScreenState();
}

class _WorkloadScreenState extends State<WorkloadScreen> {
  WorkloadPeriod _period = WorkloadPeriod.thisWeek;
  String? _teamId;
  _View _view = _View.workload;

  Future<void> _editHours(Team team) async {
    final c = TextEditingController(text: '${team.weekHours}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hours per week in ${team.name}'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              suffixText: 'hours', helperText: 'Work time per person per week (1–100)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (v == null) return;
    if (v < 1 || v > 100) {
      if (mounted) showSnack(context, 'Enter 1 to 100 hours.');
      return;
    }
    TeamStore.instance.setWeekHours(team, v);
  }

  void _reassign(Rebalance r) {
    final team = r.task.team!;
    final t = r.task.task;
    final before = t.assigneeId;
    t.assigneeId = r.to.uid;
    TeamStore.instance.saveTask(team, t, t.checklist, isNew: false, previousAssigneeId: before);
    showSnack(context, '"${t.title}" given to ${r.to.name}');
  }

  void _showPerson(MemberLoad m) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Row(children: [
                Avatar(name: m.name, size: 40, uid: m.uid),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(
                        '${_h(m.totalMinutes)} of ${_h(m.capacityMinutes)} • ${m.open.length} open tasks'
                        '${m.elsewhereMinutes > 0 ? ' • ${_h(m.elsewhereMinutes)} busy elsewhere' : ''}',
                        style: const TextStyle(color: AppColors.textMuted)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              if (m.open.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No open tasks in this period.',
                      style: TextStyle(color: AppColors.textMuted)),
                ),
              for (final r in m.open)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(taskIconFor(r)),
                  title: Text(r.task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle:
                      Text('${r.sourceLabel} • ${DateFormat('EEE d MMM').format(r.task.startAt)}'
                          '${r.task.isOverdue ? ' • Overdue' : ''}'),
                  trailing: Text(
                    taskMinutes(r.task).$2 ? 'no estimate' : formatShort(taskMinutes(r.task).$1),
                    style: TextStyle(
                        color:
                            taskMinutes(r.task).$2 ? const Color(0xFFB45309) : AppColors.textMuted),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    openTaskRef(context, r);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String formatShort(int m) => m < 60 ? '${m}m' : _h(m);

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final allTeams = store.teams;
        if (_teamId != null && store.teamById(_teamId!) == null) _teamId = null;
        final teams = _teamId == null ? allTeams : [store.teamById(_teamId!)!];
        final report = buildWorkload(teams, store.tasksOf, _period, DateTime.now());
        final adminTeams = allTeams.where(store.isAdmin).toList();
        final selected = _teamId == null ? null : store.teamById(_teamId!);

        return LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final controls = Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Menu<WorkloadPeriod>(
                label: periodLabel(_period),
                icon: Icons.date_range_rounded,
                items: {for (final p in WorkloadPeriod.values) p: periodLabel(p)},
                onSelected: (p) => setState(() => _period = p),
              ),
              _Menu<String>(
                label: selected?.name ?? 'All Teams',
                icon: Icons.groups_outlined,
                items: {'': 'All Teams', for (final t in allTeams) t.id: t.name},
                onSelected: (id) => setState(() => _teamId = id.isEmpty ? null : id),
              ),
              if (selected != null && selected.ownerId == store.uid)
                OutlinedButton.icon(
                  onPressed: () => _editHours(selected),
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text('${selected.weekHours}h / week'),
                ),
              if (adminTeams.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => showCreateTask(context,
                      team: selected != null && store.isAdmin(selected)
                          ? selected
                          : (adminTeams.length == 1 ? adminTeams.first : null)),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Assign Task'),
                ),
            ],
          );

          final tiles = [
            (
              Icons.person_outline_rounded,
              AppColors.primary,
              '${report.members.length}',
              'Total members'
            ),
            (Icons.view_in_ar_rounded, AppColors.purple, '${report.openTasks}', 'Open tasks'),
            (
              Icons.work_outline_rounded,
              const Color(0xFFEA7A0C),
              _h(report.totalMinutes),
              'Estimated workload'
            ),
            (
              Icons.speed_rounded,
              AppColors.success,
              '${(report.averageRatio * 100).round()}%',
              'Avg. capacity used'
            ),
          ];
          Widget tile((IconData, Color, String, String) t) => DashCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  IconBox(icon: t.$1, color: t.$2, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(t.$3,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        ),
                        Text(t.$4,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ]),
              );

          final overview = DashCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Team Capacity Overview',
                    style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                Text(
                    '${DateFormat('d MMM').format(report.start)} – '
                    '${DateFormat('d MMM').format(report.end.subtract(const Duration(days: 1)))}'
                    '  •  tap a person to see their tasks',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                const SizedBox(height: 10),
                if (report.members.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('Create or join a team to see its workload.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
                  ),
                for (final m in report.members) _PersonRow(m: m, onTap: () => _showPerson(m)),
              ],
            ),
          );

          final chart = DashCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<_View>(
                  segments: const [
                    ButtonSegment(value: _View.workload, label: Text('Workload')),
                    ButtonSegment(value: _View.tasks, label: Text('Tasks')),
                    ButtonSegment(value: _View.capacity, label: Text('Capacity')),
                  ],
                  selected: {_view},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _view = s.first),
                ),
                const SizedBox(height: 16),
                _Chart(report: report, view: _view),
              ],
            ),
          );

          final balance = _BalanceCard(
            report: report,
            canReassign: (r) => store.isAdmin(r.task.team!),
            onReassign: _reassign,
          );

          final body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                PageHeader(
                  title: 'Team Workload',
                  subtitle: 'Team capacity, task distribution and who is overloaded.',
                  actions: [controls],
                )
              else
                controls,
              const SizedBox(height: 18),
              if (wide)
                Row(children: [
                  for (final (i, t) in tiles.indexed) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: tile(t)),
                  ],
                ])
              else
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.1,
                  children: [for (final t in tiles) tile(t)],
                ),
              const SizedBox(height: 16),
              if (box.maxWidth >= 1100)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: overview),
                    const SizedBox(width: 16),
                    Expanded(child: chart),
                  ],
                )
              else ...[
                overview,
                const SizedBox(height: 16),
                chart,
              ],
              const SizedBox(height: 16),
              balance,
            ],
          );
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: widget.page
                ? AppBar(backgroundColor: AppColors.background, title: const Text('Team Workload'))
                : null,
            body: ListView(
              padding: EdgeInsets.fromLTRB(wide ? 28 : 16, wide ? 22 : 8, wide ? 28 : 16, 28),
              children: [body],
            ),
          );
        });
      },
    );
  }
}

class _Menu<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final Map<T, String> items;
  final ValueChanged<T> onSelected;
  const _Menu(
      {required this.label, required this.icon, required this.items, required this.onSelected});

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
        position: PopupMenuPosition.under,
        onSelected: onSelected,
        itemBuilder: (_) => [
          for (final e in items.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ]),
        ),
      );
}

class _PersonRow extends StatelessWidget {
  final MemberLoad m;
  final VoidCallback onTap;
  const _PersonRow({required this.m, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _loadColor(m.ratio);
    final me = m.uid == TeamStore.instance.uid;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(
          children: [
            Avatar(
                name: m.name,
                size: 38,
                uid: m.uid,
                color: me ? AppColors.primary : AppColors.purple),
            const SizedBox(width: 12),
            SizedBox(
              width: 104,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(me ? '${m.name} (me)' : m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(m.role,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                          '${m.open.length} tasks'
                          '${m.elsewhereMinutes > 0 ? ' • +${_h(m.elsewhereMinutes)} elsewhere' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                    ),
                    Flexible(
                      child: Text('${_h(m.totalMinutes)} / ${_h(m.capacityMinutes)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  // Work here in the load color; busy elsewhere behind it.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(children: [
                      LinearProgressIndicator(
                        value: m.ratio.clamp(0, 1).toDouble(),
                        minHeight: 8,
                        color: _elsewhereColor,
                        backgroundColor: const Color(0xFFEEF1F6),
                      ),
                      LinearProgressIndicator(
                        value: (m.capacityMinutes == 0 ? 0 : m.minutes / m.capacityMinutes)
                            .clamp(0, 1)
                            .toDouble(),
                        minHeight: 8,
                        color: color,
                        backgroundColor: Colors.transparent,
                      ),
                    ]),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 46,
              child: Text('${(m.ratio * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.w800, color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bars per person: hours vs capacity, task counts, or % of capacity.
class _Chart extends StatelessWidget {
  final WorkloadReport report;
  final _View view;
  const _Chart({required this.report, required this.view});

  @override
  Widget build(BuildContext context) {
    final members = report.members.take(8).toList();
    if (members.isEmpty) {
      return const SizedBox(
          height: 120,
          child: Center(child: Text('No data yet.', style: TextStyle(color: AppColors.textMuted))));
    }
    // Each group: bars (value, color); the axis max and unit.
    final groups = <List<(double, Color)>>[];
    double top;
    String unit;
    List<(Color, String)> legend;
    switch (view) {
      case _View.workload:
        final elsewhere = members.any((m) => m.elsewhereMinutes > 0);
        for (final m in members) {
          groups.add([
            (m.minutes / 60, AppColors.primary),
            if (elsewhere) (m.elsewhereMinutes / 60, _elsewhereColor),
            (m.capacityMinutes / 60, const Color(0xFFC7D2FE)),
          ]);
        }
        top = members.fold(
            0.0, (a, m) => max(a, max(max(m.minutes, m.elsewhereMinutes), m.capacityMinutes) / 60));
        unit = 'h';
        legend = [
          (AppColors.primary, 'Task hours'),
          if (elsewhere) (_elsewhereColor, 'Busy elsewhere'),
          (const Color(0xFFC7D2FE), 'Capacity'),
        ];
      case _View.tasks:
        for (final m in members) {
          groups.add([
            ((m.open.length - m.overdueCount).toDouble(), AppColors.primary),
            (m.overdueCount.toDouble(), AppColors.danger),
            (m.doneCount.toDouble(), AppColors.success),
          ]);
        }
        top = members.fold(
            0.0,
            (a, m) => max(
                a,
                [m.open.length - m.overdueCount, m.overdueCount, m.doneCount]
                    .reduce(max)
                    .toDouble()));
        unit = '';
        legend = [
          (AppColors.primary, 'Open'),
          (AppColors.danger, 'Overdue'),
          (AppColors.success, 'Done')
        ];
      case _View.capacity:
        for (final m in members) {
          groups.add([(m.ratio * 100, _loadColor(m.ratio))]);
        }
        top = max(100, members.fold(0.0, (a, m) => max(a, m.ratio * 100)));
        unit = '%';
        legend = [
          (AppColors.success, 'Free'),
          (AppColors.primary, 'Busy'),
          (AppColors.danger, 'Over 100%')
        ];
    }
    if (top <= 0) top = 1;
    // A round axis: four equal steps of a "nice" size.
    final quarter = [1, 2, 5, 10, 15, 20, 25, 50, 100, 200, 500]
        .firstWhere((q) => q * 4 >= top, orElse: () => (top / 4).ceil())
        .toDouble();
    final axisMax = quarter * 4;
    const chartH = 200.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: 14, runSpacing: 6, children: [
          for (final (c, l) in legend)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              Text(l, style: const TextStyle(fontSize: 12.5)),
            ]),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: chartH + 56,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 36,
                height: chartH,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 4; i >= 0; i--)
                      Text('${(axisMax * i / 4).round()}$unit',
                          style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Stack(
                  children: [
                    for (var i = 0; i <= 4; i++)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: chartH * i / 4,
                        child: Container(height: 1, color: const Color(0xFFEEF1F6)),
                      ),
                    if (view == _View.capacity)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: chartH * (1 - 100 / axisMax),
                        child: Container(height: 1.5, color: AppColors.danger.withAlpha(120)),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (i, m) in members.indexed)
                          Expanded(
                            child: Column(
                              children: [
                                SizedBox(
                                  height: chartH,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      for (final (v, c) in groups[i])
                                        Tooltip(
                                          message: '${m.name}: ${v.round()}$unit',
                                          child: Container(
                                            width: 14,
                                            margin: const EdgeInsets.symmetric(horizontal: 2),
                                            height: (chartH * v / axisMax).clamp(2, chartH),
                                            decoration: BoxDecoration(
                                              color: c,
                                              borderRadius: const BorderRadius.vertical(
                                                  top: Radius.circular(4)),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Avatar(name: m.name, size: 24),
                                const SizedBox(height: 2),
                                Text(m.name.split(' ').first,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final WorkloadReport report;
  final bool Function(Rebalance) canReassign;
  final ValueChanged<Rebalance> onReassign;
  const _BalanceCard({required this.report, required this.canReassign, required this.onReassign});

  @override
  Widget build(BuildContext context) {
    final moves = report.rebalances();
    final over = report.overloaded;
    final unest = report.members.fold(0, (s, m) => s + m.unestimated);
    return DashCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(over.isEmpty ? Icons.balance_rounded : Icons.warning_amber_rounded,
                color: over.isEmpty ? AppColors.success : AppColors.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  over.isEmpty
                      ? 'Workload is balanced'
                      : '${over.length} ${over.length == 1 ? 'person is' : 'people are'} overloaded',
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 8),
          for (final m in over)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                  '• ${m.name}: ${_h(m.totalMinutes)} of work for ${_h(m.capacityMinutes)} '
                  '(${(m.ratio * 100).round()}%)',
                  style: const TextStyle(color: Color(0xFF4B5563))),
            ),
          for (final r in moves)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const IconBox(
                        icon: Icons.swap_horiz_rounded, color: AppColors.primary, size: 38),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Give "${r.task.task.title}" to ${r.to.name}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                            '${r.from.name} ${(r.from.ratio * 100).round()}% to '
                            '${r.to.name} ${(r.to.ratio * 100).round()}%  •  ${r.task.sourceLabel}',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                      ]),
                    ),
                  ]),
                  if (canReassign(r))
                    FilledButton.tonal(
                        onPressed: () => onReassign(r), child: const Text('Reassign')),
                ],
              ),
            ),
          if (report.unassigned.isNotEmpty) ...[
            const Divider(height: 26, color: AppColors.border),
            Text(
                '${report.unassigned.length} unassigned ${report.unassigned.length == 1 ? 'task' : 'tasks'} in this period',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in report.unassigned.take(6))
                ActionChip(
                  avatar: const Icon(Icons.person_off_outlined, size: 16),
                  label: Text(r.task.title, overflow: TextOverflow.ellipsis),
                  onPressed: () => openTaskRef(context, r),
                ),
            ]),
          ],
          if (unest > 0) ...[
            const SizedBox(height: 12),
            Text(
                '$unest ${unest == 1 ? 'task has' : 'tasks have'} no estimate and count as 30 min. '
                'Add estimates in the task form for a truer picture.',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFFB45309))),
          ],
        ],
      ),
    );
  }
}

/// Work a person has outside the teams shown (personal, other teams).
const _elsewhereColor = Color(0xFFB4A7F5);
