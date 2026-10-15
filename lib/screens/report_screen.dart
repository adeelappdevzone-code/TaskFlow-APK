import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../data/weekly_report.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';

void openWeeklyReport(BuildContext context, Team team) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => WeeklyReportScreen(teamId: team.id)),
  );
}

/// A team's week on one card, shareable as an image or as text.
class WeeklyReportScreen extends StatefulWidget {
  final String teamId;
  const WeeklyReportScreen({super.key, required this.teamId});

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  final _cardKey = GlobalKey();
  int _weeksBack = 0;
  bool _sharing = false;

  Future<void> _shareImage(WeeklyReport r) async {
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('no image data');
      final name = 'TaskFlow-${r.team.name}-${formatShortDate(r.start)}.png'
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(data.buffer.asUint8List(), mimeType: 'image/png', name: name)],
        fileNameOverrides: [name],
        text: '${r.team.name} — weekly report (${r.rangeLabel})',
      ));
    } catch (e) {
      if (mounted) showSnack(context, 'Could not share the image: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareText(WeeklyReport r) async {
    try {
      await SharePlus.instance.share(ShareParams(text: r.toText()));
    } catch (e) {
      if (mounted) showSnack(context, 'Could not share: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final team = store.teamById(widget.teamId);
        if (team == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
                icon: Icons.groups_rounded,
                title: 'Team not found',
                subtitle: 'It may have been deleted.'),
          );
        }
        final r = WeeklyReport.compute(team, store.tasksOf(team.id), DateTime.now(),
            weeksBack: _weeksBack);
        return Scaffold(
          appBar: AppBar(title: const Text('Weekly report')),
          body: CenteredContent(maxWidth: 720, child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous week',
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => setState(() => _weeksBack++),
                  ),
                  Expanded(
                    child: Text(
                      _weeksBack == 0
                          ? 'This week'
                          : (_weeksBack == 1 ? 'Last week' : '$_weeksBack weeks ago'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next week',
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: _weeksBack == 0 ? null : () => setState(() => _weeksBack--),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              RepaintBoundary(key: _cardKey, child: ReportCard(report: r)),
              const SizedBox(height: 18),
              PrimaryButton(
                label: 'Share as image',
                icon: Icons.image_outlined,
                loading: _sharing,
                onPressed: () => _shareImage(r),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _shareText(r),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Share as text (WhatsApp)'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ],
          )),
        );
      },
    );
  }
}

/// The report itself (also what goes into the shared image).
class ReportCard extends StatelessWidget {
  final WeeklyReport report;
  const ReportCard({super.key, required this.report});

  static const _maxItems = 8;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final color = Color(r.team.color);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: color,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.team.name,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('Weekly report • ${r.rangeLabel}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _num('Done', r.done.length, AppColors.success),
                    _num('Late', r.late.length, AppColors.danger),
                    _num('Due this week', r.dueThisWeek, AppColors.primary),
                    if (r.totalTime > Duration.zero)
                      Expanded(
                        child: Column(
                          children: [
                            Text(formatDuration(r.totalTime),
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.purple)),
                            const Text('Time tracked',
                                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('People', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final m in r.members)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Avatar(name: m.name, size: 26),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(m.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5))),
                        Text('${m.done} done',
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.success,
                                fontWeight: FontWeight.w600)),
                        if (m.late > 0) ...[
                          const SizedBox(width: 10),
                          Text('${m.late} late',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.w600)),
                        ],
                        if (m.time > Duration.zero) ...[
                          const SizedBox(width: 10),
                          Text(formatDuration(m.time),
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.purple,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  ),
                ..._list(
                    'Done', r.done, AppColors.success, (t) => '${t.title} — ${r.assigneeName(t)}'),
                ..._list(
                    'Late',
                    r.late,
                    AppColors.danger,
                    (t) =>
                        '${t.title} — ${r.assigneeName(t)}, due ${relativeDay(t.endAt ?? t.startAt)}'),
                if (r.done.isEmpty && r.late.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('No finished or late tasks this week.',
                        style: TextStyle(color: AppColors.textMuted)),
                  ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('TaskFlow',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _num(String label, int value, Color color) => Expanded(
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ],
        ),
      );

  List<Widget> _list(
      String title, List<TaskItem> items, Color color, String Function(TaskItem) line) {
    if (items.isEmpty) return const [];
    return [
      const SizedBox(height: 12),
      Text('$title (${items.length})', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
      const SizedBox(height: 6),
      for (final t in items.take(_maxItems))
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(line(t), style: const TextStyle(fontSize: 13))),
            ],
          ),
        ),
      if (items.length > _maxItems)
        Text('…and ${items.length - _maxItems} more',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
    ];
  }
}
