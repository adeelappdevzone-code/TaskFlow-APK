import 'dart:math' show max;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../data/app_store.dart';
import '../data/reports.dart';
import '../data/models.dart';
import '../data/team_store.dart';
import '../data/time_report.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import 'task_open.dart';
import 'task_ui.dart';

enum _Tab { overview, team, projects, time }

String _rangeText(DateTime s, DateTime e) =>
    '${DateFormat('d MMM yyyy').format(s)} - ${DateFormat('d MMM yyyy').format(e.subtract(const Duration(days: 1)))}';

/// Reports Center: tasks, people, projects and time for a date range, and a
/// PDF to share.
class ReportsScreen extends StatefulWidget {
  final bool page;
  const ReportsScreen({super.key, this.page = false});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _Tab _tab = _Tab.overview;
  ReportRange? _preset = ReportRange.thisMonth;
  DateTimeRange? _custom;
  bool _exporting = false;

  (DateTime, DateTime) get _range {
    final c = _custom;
    if (_preset == null && c != null) {
      return (c.start, DateTime(c.end.year, c.end.month, c.end.day + 1));
    }
    return rangeDates(_preset ?? ReportRange.thisMonth, DateTime.now());
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _custom,
    );
    if (r != null) {
      setState(() {
        _custom = r;
        _preset = null;
      });
    }
  }

  Future<void> _export(ReportData d) async {
    setState(() => _exporting = true);
    try {
      final (s, e) = _range;
      final rows = timeRows(timeTasks(), s, e);
      final bytes = await buildReportPdf(d, rows,
          by: AppStore.instance.currentUser?.name ?? '', range: _rangeText(s, e));
      final name = 'TaskFlow report ${DateFormat('yyyy-MM-dd').format(s)}.pdf';
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
        fileNameOverrides: [name],
        subject: 'TaskFlow report',
      ));
    } catch (e) {
      if (mounted) showSnack(context, 'Could not make the PDF: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppStore.instance, TeamStore.instance]),
      builder: (context, _) {
        final (s, e) = _range;
        final now = DateTime.now();
        final data = buildReport(reportTasks(), s, e, now);
        return LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final rangeMenu = PopupMenuButton<Object>(
            tooltip: 'Date range',
            position: PopupMenuPosition.under,
            onSelected: (v) {
              if (v is ReportRange) {
                setState(() {
                  _preset = v;
                  _custom = null;
                });
              } else {
                _pickCustom();
              }
            },
            itemBuilder: (_) => [
              for (final r in ReportRange.values)
                CheckedPopupMenuItem(value: r, checked: _preset == r, child: Text(rangeLabel(r))),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(
                  value: 'custom', checked: _preset == null, child: const Text('Custom range...')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.calendar_month_outlined, size: 19),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(_rangeText(s, e),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded),
              ]),
            ),
          );
          final exportBtn = FilledButton.icon(
            onPressed: _exporting ? null : () => _export(data),
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download_rounded, size: 19),
            label: const Text('Export PDF'),
          );
          final tabs = Container(
            decoration:
                const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (t, label) in [
                  (_Tab.overview, 'Overview'),
                  (_Tab.team, 'Team'),
                  (_Tab.projects, 'Projects'),
                  (_Tab.time, 'Time Tracking'),
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
            _Tab.overview => _Overview(d: data, wide: box.maxWidth >= 1100),
            _Tab.team => _PeopleCard(d: data, all: true),
            _Tab.projects => _ProjectsTable(d: data),
            _Tab.time => _TimeTab(start: s, end: e, wide: wide),
          };
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: widget.page
                ? AppBar(backgroundColor: AppColors.background, title: const Text('Reports'))
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
                        child: IconBox(icon: Icons.bar_chart_rounded, color: AppColors.primary),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: PageHeader(
                          title: 'Reports Center',
                          subtitle: 'Task progress, team performance, projects and time.',
                        ),
                      ),
                      ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320), child: rangeMenu),
                      const SizedBox(width: 12),
                      exportBtn,
                    ],
                  )
                else
                  Wrap(spacing: 10, runSpacing: 10, children: [rangeMenu, exportBtn]),
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

// ---------------------------------------------------------------- overview

class _Overview extends StatelessWidget {
  final ReportData d;
  final bool wide;
  const _Overview({required this.d, required this.wide});

  @override
  Widget build(BuildContext context) {
    final n = d.numbers, p = d.previous;
    final tiles = [
      (
        Icons.person_outline_rounded,
        AppColors.primary,
        n.total,
        'Total tasks',
        changePct(p.total, n.total),
        true
      ),
      (
        Icons.check_circle_outline_rounded,
        AppColors.success,
        n.completed,
        'Completed',
        changePct(p.completed, n.completed),
        true
      ),
      (
        Icons.error_outline_rounded,
        AppColors.danger,
        n.overdue,
        'Overdue',
        changePct(p.overdue, n.overdue),
        false
      ),
      (
        Icons.upload_rounded,
        AppColors.primary,
        n.inProgress,
        'In progress',
        changePct(p.inProgress, n.inProgress),
        true
      ),
    ];
    Widget tile((IconData, Color, int, String, int?, bool) t) {
      final ch = t.$5;
      final good = ch == null ? true : (t.$6 ? ch >= 0 : ch <= 0);
      return DashCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(children: [
          IconBox(icon: t.$1, color: t.$2, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t.$3}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              Text(t.$4,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted)),
            ]),
          ),
          if (ch != null)
            Tooltip(
              message: 'Compared with the period before',
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(ch >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    size: 16, color: good ? AppColors.success : AppColors.danger),
                Text('${ch.abs()}%',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: good ? AppColors.success : AppColors.danger)),
              ]),
            ),
        ]),
      );
    }

    final tileWidgets = [for (final t in tiles) tile(t)];
    final trend = DashCard(padding: const EdgeInsets.all(18), child: _TrendChart(points: d.trend));
    final projects = DashCard(padding: const EdgeInsets.all(18), child: _ByProject(d: d));
    final people = _PeopleCard(d: d, all: false);
    final upcoming = _Upcoming(d: d);
    final narrowTiles = MediaQuery.sizeOf(context).width < 900;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!narrowTiles)
          Row(children: [
            for (final (i, t) in tileWidgets.indexed) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: t),
            ],
          ])
        else
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.9,
            children: tileWidgets,
          ),
        const SizedBox(height: 16),
        if (wide) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: trend),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: projects),
          ]),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: people),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: upcoming),
          ]),
        ] else ...[
          trend,
          const SizedBox(height: 16),
          projects,
          const SizedBox(height: 16),
          people,
          const SizedBox(height: 16),
          upcoming,
        ],
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<TrendPoint> points;
  const _TrendChart({required this.points});

  static const _created = Color(0xFF22C55E);
  static const _done = AppColors.primary;
  static const _late = AppColors.danger;

  @override
  Widget build(BuildContext context) {
    final top = points.fold(0, (a, p) => max(a, max(p.created, max(p.completed, p.overdue))));
    final axis = top <= 4 ? 4 : ((top + 3) ~/ 4) * 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 8,
          children: [
            const Text('Task progress trend',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Wrap(spacing: 14, children: [
              for (final (c, l) in [
                (_done, 'Completed'),
                (_created, 'Created'),
                (_late, 'Overdue')
              ])
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(l, style: const TextStyle(fontSize: 13)),
                ]),
            ]),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 230,
          child: points.length < 2
              ? const Center(
                  child: Text('Not enough days yet.', style: TextStyle(color: AppColors.textMuted)))
              : CustomPaint(
                  painter: _LinePainter(points, axis.toDouble()),
                  child: const SizedBox.expand(),
                ),
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<TrendPoint> pts;
  final double axis;
  _LinePainter(this.pts, this.axis);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0, bottom = 22.0;
    final w = size.width - left - 6, h = size.height - bottom - 6;
    final grid = Paint()
      ..color = const Color(0xFFEEF1F6)
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= 4; i++) {
      final y = 6 + h - h * i / 4;
      canvas.drawLine(Offset(left, y), Offset(left + w, y), grid);
      tp.text = TextSpan(
          text: '${(axis * i / 4).round()}',
          style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted));
      tp.layout();
      tp.paint(canvas, Offset(left - tp.width - 6, y - tp.height / 2));
    }
    double x(int i) => left + w * i / (pts.length - 1);
    double y(int v) => 6 + h - h * v / axis;
    // Dates along the bottom (about 5).
    final every = max(1, (pts.length / 5).ceil());
    for (var i = 0; i < pts.length; i += every) {
      tp.text = TextSpan(
          text: DateFormat('d MMM').format(pts[i].day),
          style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted));
      tp.layout();
      tp.paint(canvas, Offset(x(i) - tp.width / 2, 6 + h + 6));
    }
    void series(int Function(TrendPoint) v, Color c) {
      final path = Path()..moveTo(x(0), y(v(pts[0])));
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(x(i), y(v(pts[i])));
      }
      final area = Path.from(path)
        ..lineTo(x(pts.length - 1), y(0))
        ..lineTo(x(0), y(0))
        ..close();
      canvas.drawPath(area, Paint()..color = c.withAlpha(22));
      canvas.drawPath(
          path,
          Paint()
            ..color = c
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4);
      final dot = Paint()..color = c;
      for (var i = 0; i < pts.length; i += every) {
        canvas.drawCircle(Offset(x(i), y(v(pts[i]))), 3.2, dot);
      }
    }

    series((p) => p.created, _TrendChart._created);
    series((p) => p.completed, _TrendChart._done);
    series((p) => p.overdue, _TrendChart._late);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.pts != pts || old.axis != axis;
}

class _ByProject extends StatelessWidget {
  final ReportData d;
  const _ByProject({required this.d});

  @override
  Widget build(BuildContext context) {
    final total = d.inRange.length;
    final top = d.byProject.isEmpty ? 1 : d.byProject.first.$3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Tasks by project', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (d.byProject.isEmpty)
          const Text('No tasks in this range.', style: TextStyle(color: AppColors.textMuted)),
        for (final (label, color, n, _) in d.byProject.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              SizedBox(
                width: 130,
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: n / top,
                    minHeight: 10,
                    color: Color(color),
                    backgroundColor: const Color(0xFFEEF1F6),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 70,
                child: Text('$n (${(n * 100 / total).round()}%)',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ]),
          ),
      ],
    );
  }
}

class _PeopleCard extends StatelessWidget {
  final ReportData d;
  final bool all;
  const _PeopleCard({required this.d, required this.all});

  @override
  Widget build(BuildContext context) {
    final people = all ? d.people : d.people.take(6).toList();
    const head = TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w600);
    return DashCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Team performance',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const Text('Team tasks due in this range, per person.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          const SizedBox(height: 12),
          if (people.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('No team tasks in this range.',
                  style: TextStyle(color: AppColors.textMuted)),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 600),
                child: Column(children: [
                  Container(
                    color: AppColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    child: const Row(children: [
                      SizedBox(width: 28, child: Text('#', style: head)),
                      SizedBox(width: 190, child: Text('Team member', style: head)),
                      SizedBox(width: 70, child: Text('Assigned', style: head)),
                      SizedBox(width: 80, child: Text('Completed', style: head)),
                      SizedBox(width: 80, child: Text('In progress', style: head)),
                      SizedBox(width: 70, child: Text('Overdue', style: head)),
                      SizedBox(width: 150, child: Text('Completion rate', style: head)),
                    ]),
                  ),
                  for (final (i, p) in people.indexed)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: AppColors.border))),
                      child: Row(children: [
                        SizedBox(width: 28, child: Text('${i + 1}')),
                        SizedBox(
                          width: 190,
                          child: Row(children: [
                            Avatar(name: p.name, size: 32),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text(p.role,
                                      style: const TextStyle(
                                          fontSize: 12, color: AppColors.textMuted)),
                                ],
                              ),
                            ),
                          ]),
                        ),
                        SizedBox(width: 70, child: Text('${p.assigned}')),
                        SizedBox(width: 80, child: Text('${p.completed}')),
                        SizedBox(width: 80, child: Text('${p.inProgress}')),
                        SizedBox(
                            width: 70,
                            child: Text('${p.overdue}',
                                style: TextStyle(color: p.overdue > 0 ? AppColors.danger : null))),
                        SizedBox(
                          width: 150,
                          child: Row(children: [
                            SizedBox(
                                width: 40,
                                child: Text('${(p.rate * 100).round()}%',
                                    style: const TextStyle(fontWeight: FontWeight.w700))),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: p.rate,
                                  minHeight: 8,
                                  color: p.rate >= 0.8 ? AppColors.success : AppColors.primary,
                                  backgroundColor: const Color(0xFFEEF1F6),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _Upcoming extends StatelessWidget {
  final ReportData d;
  const _Upcoming({required this.d});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return DashCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Upcoming deadlines',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (d.upcoming.isEmpty)
            const Text('Nothing coming up.', style: TextStyle(color: AppColors.textMuted)),
          for (final r in d.upcoming)
            InkWell(
              onTap: () => openTaskRef(context, r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  IconBox(icon: taskIconFor(r), color: Color(r.sourceColor), size: 38),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${r.sourceLabel}  •  ${dueLabel(r.task, now)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    ]),
                  ),
                  PriorityChip(priority: r.task.priority),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProjectsTable extends StatelessWidget {
  final ReportData d;
  const _ProjectsTable({required this.d});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return DashCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Projects and teams',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (d.byProject.isEmpty)
            const Text('No tasks in this range.', style: TextStyle(color: AppColors.textMuted)),
          for (final (label, color, n, done) in d.byProject)
            Builder(builder: (context) {
              final late = d.inRange
                  .where((r) =>
                      r.sourceLabel == label &&
                      !r.task.isCompleted &&
                      (r.task.endAt ?? r.task.startAt).isBefore(now))
                  .length;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  IconBox(icon: Icons.folder_rounded, color: Color(color), size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          Flexible(
                            child: Text('$done/$n done${late > 0 ? '  •  $late overdue' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: late > 0 ? AppColors.danger : AppColors.textMuted)),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: n == 0 ? 0 : done / n,
                            minHeight: 8,
                            color: Color(color),
                            backgroundColor: const Color(0xFFEEF1F6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 44,
                    child: Text('${n == 0 ? 0 : (done * 100 / n).round()}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ]),
              );
            }),
        ],
      ),
    );
  }
}

class _TimeTab extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final bool wide;
  const _TimeTab({required this.start, required this.end, required this.wide});

  @override
  Widget build(BuildContext context) {
    final rows = timeRows(timeTasks(), start, end);
    final totals = timeTotals(rows);
    final bySource = minutesBySource(rows);
    final people = <String, int>{};
    for (final r in rows) {
      final k = whoOf(r.ref.team, r.entry.by);
      people[k] = (people[k] ?? 0) + r.minutes;
    }
    final peopleList = people.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    Widget list(String title, List<(String, int, int?)> items) => DashCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (items.isEmpty)
                const Text('No time logged in this range.',
                    style: TextStyle(color: AppColors.textMuted)),
              for (final (label, m, color) in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    SizedBox(
                        width: 130,
                        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: totals.total == 0 ? 0 : m / totals.total,
                          minHeight: 9,
                          color: color == null ? AppColors.primary : Color(color),
                          backgroundColor: const Color(0xFFEEF1F6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                        width: 64,
                        child: Text(hm(m),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w600))),
                  ]),
                ),
            ],
          ),
        );
    final a = list('Time by project', [for (final (l, m, c) in bySource) (l, m, c)]);
    final b = list('Time by person', [for (final e in peopleList) (e.key, e.value, null)]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final (label, v, c) in [
            ('Total tracked', hm(totals.total), AppColors.primary),
            ('Billable', hm(totals.billable), AppColors.success),
            ('Non-billable', hm(totals.nonBillable), const Color(0xFFEA7A0C)),
          ])
            SizedBox(
              width: 200,
              child: DashCard(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c)),
                  Text(label, style: const TextStyle(color: AppColors.textMuted)),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 16),
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: a),
            const SizedBox(width: 16),
            Expanded(child: b),
          ])
        else ...[
          a,
          const SizedBox(height: 16),
          b,
        ],
      ],
    );
  }
}

// --------------------------------------------------------------------- PDF

/// The report as a PDF (plain text only: the built-in PDF font has no
/// special characters).
Future<Uint8List> buildReportPdf(ReportData d, List<TimeRow> time,
    {required String by, required String range}) async {
  String clean(String s) => s.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
  final doc = pw.Document(title: 'TaskFlow report', author: clean(by));
  final n = d.numbers;
  final totals = timeTotals(time);
  const blue = pdf.PdfColor.fromInt(0xFF1F6FEB);
  pw.Widget h(String s) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
        child: pw.Text(s,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: blue)),
      );
  pw.Widget table(List<String> head, List<List<String>> rows) => pw.TableHelper.fromTextArray(
        headers: head,
        data: rows,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
        cellStyle: const pw.TextStyle(fontSize: 10),
        headerDecoration: const pw.BoxDecoration(color: pdf.PdfColor.fromInt(0xFFF1F5F9)),
        cellAlignment: pw.Alignment.centerLeft,
      );
  doc.addPage(pw.MultiPage(
    pageFormat: pdf.PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (_) => [
      pw.Text('TaskFlow report',
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: blue)),
      pw.Text(clean('$range${by.isEmpty ? '' : '  |  by $by'}'),
          style: const pw.TextStyle(fontSize: 11, color: pdf.PdfColors.grey700)),
      h('Summary'),
      table([
        'Total tasks',
        'Completed',
        'Overdue',
        'In progress',
        'Completion'
      ], [
        [
          '${n.total}',
          '${n.completed}',
          '${n.overdue}',
          '${n.inProgress}',
          '${(n.rate * 100).round()}%'
        ]
      ]),
      if (d.byProject.isNotEmpty) ...[
        h('Tasks by project'),
        table([
          'Project / team',
          'Tasks',
          'Done',
          'Progress'
        ], [
          for (final (l, _, c, done) in d.byProject)
            [clean(l), '$c', '$done', '${c == 0 ? 0 : (done * 100 / c).round()}%']
        ]),
      ],
      if (d.people.isNotEmpty) ...[
        h('Team performance'),
        table([
          'Member',
          'Assigned',
          'Completed',
          'In progress',
          'Overdue',
          'Rate'
        ], [
          for (final p in d.people)
            [
              clean(p.name),
              '${p.assigned}',
              '${p.completed}',
              '${p.inProgress}',
              '${p.overdue}',
              '${(p.rate * 100).round()}%'
            ]
        ]),
      ],
      h('Time tracked'),
      table([
        'Total',
        'Billable',
        'Non-billable'
      ], [
        [hm(totals.total), hm(totals.billable), hm(totals.nonBillable)]
      ]),
      if (time.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: table([
            'Project / team',
            'Time'
          ], [
            for (final (l, m, _) in minutesBySource(time)) [clean(l), hm(m)]
          ]),
        ),
      if (d.upcoming.isNotEmpty) ...[
        h('Upcoming deadlines'),
        table([
          'Task',
          'Where',
          'Due',
          'Priority'
        ], [
          for (final r in d.upcoming)
            [
              clean(r.task.title),
              clean(r.sourceLabel),
              DateFormat('d MMM yyyy').format(r.task.startAt),
              r.task.priority.label
            ]
        ]),
      ],
      pw.SizedBox(height: 20),
      pw.Text('Made with TaskFlow on ${DateFormat('d MMM yyyy, HH:mm').format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 9, color: pdf.PdfColors.grey600)),
    ],
  ));
  return doc.save();
}
