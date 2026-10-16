import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../data/task_repository.dart';
import '../data/team_store.dart';
import '../data/time_report.dart';
import '../data/time_tracker.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import 'task_open.dart';
import 'task_ui.dart';

String? get _me => TeamStore.instance.uid ?? AppStore.instance.currentUser?.id;

String _clock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

// ------------------------------------------------------------- edit helpers

/// Adds a session by hand, or changes [row]. Null: cancelled.
Future<void> logTimeDialog(BuildContext context, {TimeRow? row, TaskRef? task}) async {
  final me = _me;
  if (me == null) return;
  final tasks = [
    for (final r in TaskRepository.myTasks())
      if (!r.task.isCancelled && r.canComplete) r
  ];
  TaskRef? ref = row?.ref ?? task;
  if (ref != null && !tasks.any((r) => r.task.id == ref!.task.id)) tasks.insert(0, ref);
  if (tasks.isEmpty) {
    showSnack(context, 'Add a task first.');
    return;
  }
  ref ??= tasks.first;
  final e = row?.entry;
  final now = DateTime.now();
  var day = dateOnly(e?.start ?? now);
  var start = TimeOfDay.fromDateTime(e?.start ?? now.subtract(const Duration(hours: 1)));
  var end = TimeOfDay.fromDateTime(e?.end ?? now);
  var billable = e?.billable ?? true;
  final note = TextEditingController(text: e?.note ?? '');
  String? error;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(row == null ? 'Log time' : 'Edit time entry'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: ref!.task.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Task'),
                  items: [
                    for (final r in tasks)
                      DropdownMenuItem(
                        value: r.task.id,
                        child: Text('${r.task.title}  •  ${r.sourceLabel}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: row != null
                      ? null
                      : (id) => setState(() => ref = tasks.firstWhere((r) => r.task.id == id)),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: Text(DateFormat('EEE, d MMM yyyy').format(day)),
                  onTap: () async {
                    final d = await showDatePicker(
                        context: ctx,
                        initialDate: day,
                        firstDate: DateTime(now.year - 2),
                        lastDate: now);
                    if (d != null) setState(() => day = d);
                  },
                ),
                Row(children: [
                  for (final (label, isStart) in [('Start', true), ('End', false)])
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(isStart ? Icons.play_arrow_rounded : Icons.stop_rounded),
                        title: Text(label, style: const TextStyle(fontSize: 12.5)),
                        subtitle: Text((isStart ? start : end).format(ctx),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
                        onTap: () async {
                          final t = await showTimePicker(
                              context: ctx, initialTime: isStart ? start : end);
                          if (t != null) setState(() => isStart ? start = t : end = t);
                        },
                      ),
                    ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Billable'),
                  subtitle: const Text('Can be charged to the client'),
                  value: billable,
                  onChanged: (v) => setState(() => billable = v),
                ),
                TextField(
                  controller: note,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: AppColors.danger)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final s = DateTime(day.year, day.month, day.day, start.hour, start.minute);
              final en = DateTime(day.year, day.month, day.day, end.hour, end.minute);
              if (!en.isAfter(s)) {
                setState(() => error = 'The end must be after the start.');
                return;
              }
              if (en.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
                setState(() => error = 'You can only log time that has passed.');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final r = ref!;
  final s = DateTime(day.year, day.month, day.day, start.hour, start.minute);
  final en = DateTime(day.year, day.month, day.day, end.hour, end.minute);
  final log = [...r.task.timeLog];
  if (e != null) {
    final i = log.indexWhere((x) => x.by == e.by && x.start == e.start && x.end == e.end);
    if (i >= 0) {
      log[i] = e.copyWith(start: s, end: en, billable: billable, note: note.text.trim());
    }
  } else {
    log.add(TimeEntry(by: me, start: s, end: en, billable: billable, note: note.text.trim()));
  }
  TimeTracker.setLog(r.task, log, team: r.team);
  if (context.mounted) showSnack(context, e == null ? 'Time logged' : 'Entry updated');
}

void _setBillable(TimeRow row, bool v) {
  final e = row.entry;
  final log = [...row.ref.task.timeLog];
  final i = log.indexWhere((x) => x.by == e.by && x.start == e.start && x.end == e.end);
  if (i < 0) return;
  log[i] = e.copyWith(billable: v);
  TimeTracker.setLog(row.ref.task, log, team: row.ref.team);
}

Future<void> _delete(BuildContext context, TimeRow row) async {
  final ok = await confirmDialog(context,
      title: 'Delete this entry?',
      message: '${hm(row.minutes)} on "${row.ref.task.title}" will be removed.',
      confirmLabel: 'Delete',
      danger: true);
  if (!ok) return;
  final e = row.entry;
  final log = [...row.ref.task.timeLog]
    ..removeWhere((x) => x.by == e.by && x.start == e.start && x.end == e.end);
  TimeTracker.setLog(row.ref.task, log, team: row.ref.team);
}

Future<void> _startOn(BuildContext context, TaskRef r) async {
  TimeTracker.start(r.task, team: r.team);
  showSnack(context, 'Timer started: ${r.task.title}');
}

Future<void> _pickAndStart(BuildContext context) async {
  final tasks = [
    for (final r in TaskRepository.myTasks())
      if (r.task.status == TaskStatus.pending && r.canComplete) r
  ];
  if (tasks.isEmpty) {
    showSnack(context, 'No open tasks to time.');
    return;
  }
  final r = await showDialog<TaskRef>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Start a timer on'),
      children: [
        for (final r in tasks.take(30))
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, r),
            child: Row(children: [
              Icon(taskIconFor(r), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child:
                    Text('${r.task.title}  •  ${r.sourceLabel}', overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
      ],
    ),
  );
  if (r != null && context.mounted) _startOn(context, r);
}

// ------------------------------------------------------------------ screen

enum _Tab { mine, team, sheets }

class TimeScreen extends StatefulWidget {
  final bool page;
  const TimeScreen({super.key, this.page = false});

  @override
  State<TimeScreen> createState() => _TimeScreenState();
}

class _TimeScreenState extends State<TimeScreen> {
  _Tab _tab = _Tab.mine;
  DateTime _week = weekStartOf(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppStore.instance, TeamStore.instance]),
      builder: (context, _) {
        final end = _week.add(const Duration(days: 7));
        final refs = timeTasks();
        return LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final weekPicker = Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Previous week',
                onPressed: () => setState(() => _week = _week.subtract(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              const Icon(Icons.calendar_month_outlined, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                    '${DateFormat('d MMM').format(_week)} – '
                    '${DateFormat(wide ? 'd MMM yyyy' : 'd MMM').format(end.subtract(const Duration(days: 1)))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'Next week',
                onPressed: _week == weekStartOf(DateTime.now())
                    ? null
                    : () => setState(() => _week = _week.add(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ]),
          );
          final logBtn = FilledButton.icon(
            onPressed: () => logTimeDialog(context),
            icon: const Icon(Icons.add_rounded, size: 19),
            label: const Text('Log Time'),
          );
          final tabs = Container(
            decoration:
                const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (t, label) in [
                  (_Tab.mine, 'My Time'),
                  (_Tab.team, 'Team'),
                  (_Tab.sheets, 'Timesheet'),
                ])
                  InkWell(
                    onTap: () => setState(() => _tab = t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                              color: _tab == t ? AppColors.primary : Colors.transparent, width: 3),
                        ),
                      ),
                      child: Text(label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: _tab == t ? FontWeight.w700 : FontWeight.w500,
                            color: _tab == t ? AppColors.primary : AppColors.text,
                          )),
                    ),
                  ),
              ]),
            ),
          );
          final body = switch (_tab) {
            _Tab.mine => _MyTime(refs: refs, start: _week, end: end, wide: wide),
            _Tab.team => _TeamTime(start: _week, end: end, wide: wide),
            _Tab.sheets => _Sheet(refs: refs, start: _week),
          };
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: widget.page
                ? AppBar(backgroundColor: AppColors.background, title: const Text('Time Tracking'))
                : null,
            body: ListView(
              padding: EdgeInsets.fromLTRB(wide ? 28 : 16, wide ? 22 : 8, wide ? 28 : 16, 28),
              children: [
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: IconBox(icon: Icons.timer_rounded, color: AppColors.purple),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: PageHeader(
                            title: 'Time Tracking',
                            subtitle: 'Track time, billable hours and timesheets.'),
                      ),
                      weekPicker,
                      const SizedBox(width: 12),
                      logBtn,
                    ],
                  )
                else
                  Wrap(spacing: 10, runSpacing: 10, children: [weekPicker, logBtn]),
                const SizedBox(height: 12),
                tabs,
                const SizedBox(height: 16),
                body,
              ],
            ),
          );
        });
      },
    );
  }
}

Widget _tiles(List<(IconData, Color, String, String)> tiles, bool wide) {
  Widget tile((IconData, Color, String, String) t) => DashCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          IconBox(icon: t.$1, color: t.$2, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child:
                      Text(t.$3, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
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
    childAspectRatio: 2.1,
    children: [for (final t in tiles) tile(t)],
  );
}

// ----------------------------------------------------------------- my time

class _MyTime extends StatelessWidget {
  final List<TaskRef> refs;
  final DateTime start;
  final DateTime end;
  final bool wide;
  const _MyTime({required this.refs, required this.start, required this.end, required this.wide});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final now = DateTime.now();
    final rows = timeRows(refs, start, end, by: _me);
    final totals = timeTotals(rows);
    final work = workMinutesSoFar(start, end, now, store.workStart, store.workEnd);
    final pct = work == 0 ? null : (totals.total * 100 / work).round();
    final today = rows.where((r) => isSameDay(r.entry.start, now)).toList();

    final summary = _TodaySummary(rows: today);
    final recent = _EntriesCard(rows: rows, title: 'Time entries', showWho: false, wide: wide);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tiles([
          (Icons.timer_outlined, AppColors.primary, hm(totals.total), 'Total tracked'),
          (Icons.attach_money_rounded, AppColors.success, hm(totals.billable), 'Billable hours'),
          (
            Icons.money_off_rounded,
            const Color(0xFFEA7A0C),
            hm(totals.nonBillable),
            'Non-billable'
          ),
          (
            Icons.track_changes_rounded,
            AppColors.purple,
            pct == null ? '—' : '$pct%',
            'Of your work hours'
          ),
        ], wide),
        const SizedBox(height: 14),
        const _TimerCard(),
        const SizedBox(height: 14),
        if (MediaQuery.sizeOf(context).width >= 1200 && wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 380, child: summary),
              const SizedBox(width: 14),
              Expanded(child: recent),
            ],
          )
        else ...[
          summary,
          const SizedBox(height: 14),
          recent,
        ],
      ],
    );
  }
}

/// The running timer (ticking), with a note and Stop; or Start.
class _TimerCard extends StatefulWidget {
  const _TimerCard();

  @override
  State<_TimerCard> createState() => _TimerCardState();
}

class _TimerCardState extends State<_TimerCard> {
  Timer? _tick;
  final _note = TextEditingController();

  /// The task paused here, to resume.
  TaskRef? _paused;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && TimeTracker.running().isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _note.dispose();
    super.dispose();
  }

  void _stop(TaskRef r, {bool pause = false}) {
    TimeTracker.stop(r.task, team: r.team, note: _note.text);
    _note.clear();
    setState(() => _paused = pause ? r : null);
  }

  @override
  Widget build(BuildContext context) {
    final running = TimeTracker.running();
    final r = running.isEmpty ? null : TaskRef(running.first.$2, running.first.$1);
    final at = r?.task.timerAt;
    final elapsed = at == null ? Duration.zero : DateTime.now().difference(at);
    final paused = r == null ? _paused : null;
    final shown = r ?? paused;

    Widget round(IconData icon, Color fg, Color bg, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: Material(
            color: bg,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(width: 54, height: 54, child: Icon(icon, color: fg, size: 26)),
            ),
          ),
        );

    final info = shown == null
        ? const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('No timer running', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            SizedBox(height: 3),
            Text('Start a timer on a task, or log time you already did.',
                style: TextStyle(color: AppColors.textMuted)),
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(shown.task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, children: [SourceChip(ref: shown, small: true)]),
            if (r != null) ...[
              const SizedBox(height: 6),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Add a note...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ],
          ]);
    final clock = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration:
          BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_clock(elapsed),
            style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()])),
        Text(r != null ? 'In progress' : (paused != null ? 'Paused' : 'Stopped'),
            style: TextStyle(
                color: r != null ? AppColors.success : AppColors.textMuted,
                fontWeight: FontWeight.w600)),
      ]),
    );
    final buttons = Row(mainAxisSize: MainAxisSize.min, children: [
      if (r != null) ...[
        round(Icons.pause_rounded, AppColors.text, AppColors.background, 'Pause',
            () => _stop(r, pause: true)),
        const SizedBox(width: 10),
        round(Icons.stop_rounded, Colors.white, AppColors.danger, 'Stop and save', () => _stop(r)),
      ] else ...[
        if (paused != null) ...[
          round(Icons.play_arrow_rounded, Colors.white, AppColors.success, 'Resume',
              () => _startOn(context, paused)),
          const SizedBox(width: 10),
        ],
        round(Icons.timer_outlined, AppColors.primary, AppColors.primaryLight, 'Start a timer',
            () => _pickAndStart(context)),
      ],
    ]);
    return DashCard(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(builder: (context, box) {
        final avatar = Avatar(
            name: AppStore.instance.currentUser?.name ?? '?', size: 56, color: AppColors.purple);
        if (box.maxWidth < 620) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [avatar, const SizedBox(width: 14), Expanded(child: info)]),
            const SizedBox(height: 12),
            Row(children: [Expanded(child: clock), const SizedBox(width: 12), buttons]),
          ]);
        }
        return Row(children: [
          avatar,
          const SizedBox(width: 16),
          Expanded(child: info),
          const SizedBox(width: 12),
          clock,
          const SizedBox(width: 16),
          buttons,
        ]);
      }),
    );
  }
}

class _TodaySummary extends StatelessWidget {
  final List<TimeRow> rows;
  const _TodaySummary({required this.rows});

  @override
  Widget build(BuildContext context) {
    final totals = timeTotals(rows);
    final by = minutesBySource(rows);
    return DashCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("Today's summary",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Row(children: [
            SizedBox(
              width: 130,
              height: 130,
              child: DonutRing(
                parts: [for (final (_, m, c) in by) (m, Color(c))],
                total: totals.total,
                center: hm(totals.total),
                caption: 'Total today',
                stroke: 14,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (by.isEmpty)
                    const Text('Nothing tracked yet today.',
                        style: TextStyle(color: AppColors.textMuted)),
                  for (final (label, m, c) in by.take(5))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5))),
                        Text(hm(m), style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 38,
                          child: Text('${(m * 100 / totals.total).round()}%',
                              textAlign: TextAlign.right,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          ]),
          const Divider(height: 24, color: AppColors.border),
          Row(children: [
            Expanded(
              child: Text('Billable  ${hm(totals.billable)}',
                  style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
            ),
            Text('Non-billable  ${hm(totals.nonBillable)}',
                style: const TextStyle(color: Color(0xFFEA7A0C), fontWeight: FontWeight.w600)),
          ]),
        ],
      ),
    );
  }
}

class _EntriesCard extends StatefulWidget {
  final List<TimeRow> rows;
  final String title;
  final bool showWho;
  final bool wide;
  const _EntriesCard(
      {required this.rows, required this.title, required this.showWho, required this.wide});

  @override
  State<_EntriesCard> createState() => _EntriesCardState();
}

class _EntriesCardState extends State<_EntriesCard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final rows = _all ? widget.rows : widget.rows.take(8).toList();
    final f = DateFormat('h:mm a');
    const head = TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w600);
    return DashCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text('${widget.title} (${widget.rows.length})',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            if (widget.rows.length > 8)
              OutlinedButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? 'Show less' : 'View all'),
              ),
          ]),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No time logged this week.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
            )
          else if (widget.wide) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                  color: AppColors.background, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Expanded(flex: 4, child: Text('Task', style: head)),
                if (widget.showWho) const Expanded(flex: 2, child: Text('Person', style: head)),
                const Expanded(flex: 2, child: Text('Project', style: head)),
                const Expanded(flex: 2, child: Text('Day', style: head)),
                const Expanded(flex: 3, child: Text('Time', style: head)),
                const Expanded(flex: 2, child: Text('Duration', style: head)),
                const SizedBox(width: 70, child: Text('Billable', style: head)),
                const SizedBox(width: 90, child: Text('Actions', style: head)),
              ]),
            ),
            for (final row in rows)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border))),
                child: Row(children: [
                  Expanded(
                    flex: 4,
                    child: InkWell(
                      onTap: () => openTaskRef(context, row.ref),
                      child: Row(children: [
                        IconBox(
                            icon: taskIconFor(row.ref),
                            color: Color(row.ref.sourceColor),
                            size: 34),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row.ref.task.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (row.entry.note.isNotEmpty)
                                Text(row.entry.note,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                  if (widget.showWho)
                    Expanded(
                        flex: 2,
                        child: Text(whoOf(row.ref.team, row.entry.by),
                            overflow: TextOverflow.ellipsis)),
                  Expanded(
                      flex: 2, child: Text(row.ref.sourceLabel, overflow: TextOverflow.ellipsis)),
                  Expanded(flex: 2, child: Text(DateFormat('EEE d MMM').format(row.entry.start))),
                  Expanded(
                      flex: 3,
                      child: Text('${f.format(row.entry.start)} – ${f.format(row.entry.end)}')),
                  Expanded(
                      flex: 2,
                      child: Text(hm(row.minutes),
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                  SizedBox(
                    width: 70,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Switch(
                        value: row.entry.billable,
                        onChanged:
                            canEditEntry(row.ref, row.entry) ? (v) => _setBillable(row, v) : null,
                      ),
                    ),
                  ),
                  SizedBox(width: 90, child: _actions(context, row)),
                ]),
              ),
          ] else
            for (final row in rows)
              Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: IconBox(
                        icon: taskIconFor(row.ref), color: Color(row.ref.sourceColor), size: 38),
                    title: Text(row.ref.task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${widget.showWho ? '${whoOf(row.ref.team, row.entry.by)} • ' : ''}'
                        '${DateFormat('EEE d MMM').format(row.entry.start)}, '
                        '${f.format(row.entry.start)} – ${f.format(row.entry.end)}'
                        '${row.entry.billable ? '' : ' • non-billable'}',
                        maxLines: 2),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(hm(row.minutes), style: const TextStyle(fontWeight: FontWeight.w700)),
                      _actions(context, row, compact: true),
                    ]),
                    onTap: () => openTaskRef(context, row.ref),
                  )),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, TimeRow row, {bool compact = false}) {
    final edit = canEditEntry(row.ref, row.entry);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (!compact && row.ref.canComplete && row.ref.task.status == TaskStatus.pending)
        IconButton(
          tooltip: 'Start timer',
          visualDensity: VisualDensity.compact,
          onPressed: () => _startOn(context, row.ref),
          icon: const Icon(Icons.play_circle_outline_rounded),
        ),
      if (edit)
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: (a) {
            if (a == 'edit') logTimeDialog(context, row: row);
            if (a == 'delete') _delete(context, row);
            if (a == 'start') _startOn(context, row.ref);
          },
          itemBuilder: (_) => [
            if (compact && row.ref.canComplete && row.ref.task.status == TaskStatus.pending)
              const PopupMenuItem(value: 'start', child: Text('Start timer')),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(
                value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.danger))),
          ],
        ),
    ]);
  }
}

// -------------------------------------------------------------------- team

class _TeamTime extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final bool wide;
  const _TeamTime({required this.start, required this.end, required this.wide});

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    final teams = store.teams.where(store.isAdmin).toList();
    if (teams.isEmpty) {
      return const DashCard(
        child: EmptyState(
          icon: Icons.groups_outlined,
          title: 'For owners and managers',
          subtitle: 'Team time shows here for the teams you run.',
        ),
      );
    }
    final refs = [
      for (final t in teams)
        for (final task in store.tasksOf(t.id)) TaskRef(task, t)
    ];
    final rows = timeRows(refs, start, end);
    final totals = timeTotals(rows);
    final people = <String, (String, int, int)>{};
    for (final r in rows) {
      final old = people[r.entry.by];
      people[r.entry.by] = (
        whoOf(r.ref.team, r.entry.by),
        (old?.$2 ?? 0) + r.minutes,
        (old?.$3 ?? 0) + (r.entry.billable ? r.minutes : 0)
      );
    }
    final list = people.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
    final top = list.isEmpty ? 1 : list.first.$2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tiles([
          (Icons.timer_outlined, AppColors.primary, hm(totals.total), 'Team tracked'),
          (Icons.attach_money_rounded, AppColors.success, hm(totals.billable), 'Billable'),
          (
            Icons.money_off_rounded,
            const Color(0xFFEA7A0C),
            hm(totals.nonBillable),
            'Non-billable'
          ),
          (Icons.people_outline_rounded, AppColors.purple, '${list.length}', 'People tracking'),
        ], wide),
        const SizedBox(height: 14),
        DashCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Time per person',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (list.isEmpty)
                const Text('Nobody tracked time this week.',
                    style: TextStyle(color: AppColors.textMuted)),
              for (final (name, total, billable) in list)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(children: [
                    Avatar(name: name, size: 34),
                    const SizedBox(width: 10),
                    SizedBox(
                        width: 110,
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: total / top,
                          minHeight: 8,
                          color: AppColors.primary,
                          backgroundColor: const Color(0xFFEEF1F6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 120,
                      child: Text('${hm(total)}  (${hm(billable)} billable)',
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                  ]),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _EntriesCard(rows: rows, title: 'Team entries', showWho: true, wide: wide),
      ],
    );
  }
}

// --------------------------------------------------------------- timesheet

class _Sheet extends StatelessWidget {
  final List<TaskRef> refs;
  final DateTime start;
  const _Sheet({required this.refs, required this.start});

  void _openDay(BuildContext context, SheetRow s, int day) {
    final d = start.add(Duration(days: day));
    final rows = timeRows([s.ref], d, d.add(const Duration(days: 1)), by: _me);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.ref.task.title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text(DateFormat('EEEE, d MMM').format(d),
                  style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 8),
              for (final r in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      '${DateFormat('h:mm a').format(r.entry.start)} – ${DateFormat('h:mm a').format(r.entry.end)}'),
                  subtitle: r.entry.note.isEmpty ? null : Text(r.entry.note),
                  trailing:
                      Text(hm(r.minutes), style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: canEditEntry(r.ref, r.entry)
                      ? () {
                          Navigator.pop(ctx);
                          logTimeDialog(context, row: r);
                        }
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = timeRows(refs, start, start.add(const Duration(days: 7)), by: _me);
    final sheet = timesheet(rows, start);
    final dayTotals = List.generate(7, (i) => sheet.fold(0, (a, s) => a + s.days[i]));
    final total = dayTotals.fold(0, (a, b) => a + b);
    const cellW = 74.0;
    const head = TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w700);
    final now = DateTime.now();

    Widget cell(String text, {bool bold = false, VoidCallback? onTap, Color? color}) => SizedBox(
          width: cellW,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                      color: color ?? (text == '–' ? AppColors.textMuted : AppColors.text))),
            ),
          ),
        );

    return DashCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Expanded(
              child:
                  Text('My timesheet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            Text('Week total: ${hm(total)}',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
          ]),
          const Text('Tap a day to see or fix its entries.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          const SizedBox(height: 12),
          if (sheet.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No time logged this week. Use the timer or "Log Time".',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width - 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      color: AppColors.background,
                      child: Row(children: [
                        const SizedBox(
                            width: 220,
                            child: Padding(
                              padding: EdgeInsets.all(10),
                              child: Text('Task', style: head),
                            )),
                        for (var i = 0; i < 7; i++)
                          SizedBox(
                            width: cellW,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                DateFormat('EEE d').format(start.add(Duration(days: i))),
                                textAlign: TextAlign.center,
                                style: head.copyWith(
                                    color: isSameDay(start.add(Duration(days: i)), now)
                                        ? AppColors.primary
                                        : null),
                              ),
                            ),
                          ),
                        const SizedBox(
                            width: cellW,
                            child: Text('Total', textAlign: TextAlign.center, style: head)),
                      ]),
                    ),
                    for (final s in sheet)
                      Container(
                        decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: AppColors.border))),
                        child: Row(children: [
                          SizedBox(
                            width: 220,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.ref.task.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text(s.ref.sourceLabel,
                                      maxLines: 1,
                                      style: const TextStyle(
                                          fontSize: 12, color: AppColors.textMuted)),
                                ],
                              ),
                            ),
                          ),
                          for (var i = 0; i < 7; i++)
                            cell(s.days[i] == 0 ? '–' : hm(s.days[i]),
                                onTap: s.days[i] == 0 ? null : () => _openDay(context, s, i)),
                          cell(hm(s.total), bold: true),
                        ]),
                      ),
                    Row(children: [
                      const SizedBox(
                          width: 220,
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: Text('Total', style: TextStyle(fontWeight: FontWeight.w800)),
                          )),
                      for (var i = 0; i < 7; i++)
                        cell(dayTotals[i] == 0 ? '–' : hm(dayTotals[i]), bold: true),
                      cell(hm(total), bold: true, color: AppColors.primary),
                    ]),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
