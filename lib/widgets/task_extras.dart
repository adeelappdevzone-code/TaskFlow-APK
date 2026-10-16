import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../data/time_tracker.dart';
import 'common.dart';

// Parts of the task screens shared by personal and team tasks: links,
// history, the work timer and "@name" text.

Widget _sectionTitle(String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
              child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          if (trailing != null) trailing,
        ],
      ),
    );

// ------------------------------------------------------------------ links

Future<void> openLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Could not open the link.'), behavior: SnackBarBehavior.floating));
  }
}

IconData linkIcon(String url) {
  final u = url.toLowerCase();
  if (u.contains('docs.google.com/spreadsheets')) return Icons.table_chart_outlined;
  if (u.contains('docs.google.com/presentation')) return Icons.slideshow_outlined;
  if (u.contains('docs.google.com')) return Icons.description_outlined;
  if (u.contains('drive.google.com')) return Icons.folder_shared_outlined;
  if (u.contains('youtube.com') || u.contains('youtu.be')) return Icons.play_circle_outline;
  if (u.contains('figma.com')) return Icons.design_services_outlined;
  return Icons.link_rounded;
}

/// The task's links; tap opens, long-press copies.
class TaskLinksView extends StatelessWidget {
  final List<TaskLink> links;
  const TaskLinksView({super.key, required this.links});

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _sectionTitle('Links (${links.length})'),
        for (final l in links)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => openLink(context, l.url),
                onLongPress: () {
                  Clipboard.setData(ClipboardData(text: l.url));
                  showSnack(context, 'Link copied');
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(linkIcon(l.url), color: AppColors.primary, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            if (l.title.trim().isNotEmpty)
                              Text(l.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
      ],
    );
  }
}

/// Asks for a link (address + optional title). Returns null when cancelled.
Future<TaskLink?> linkDialog(BuildContext context, {TaskLink? initial}) {
  final url = TextEditingController(text: initial?.url ?? '');
  final title = TextEditingController(text: initial?.title ?? '');
  String? error;
  return showDialog<TaskLink>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void save() {
          final u = TaskLink.normalizeUrl(url.text);
          if (u == null) {
            setState(() => error = 'Paste a web address, e.g. https://drive.google.com/...');
            return;
          }
          Navigator.pop(ctx, TaskLink(title: title.text.trim(), url: u));
        }

        return AlertDialog(
          title: Text(initial == null ? 'Add link' : 'Edit link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: url,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: fieldDecoration('Link (Drive, Docs, website)', icon: Icons.link_rounded)
                    .copyWith(errorText: error, errorMaxLines: 2),
                inputFormatters: [LengthLimitingTextInputFormatter(2000)],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: title,
                textCapitalization: TextCapitalization.sentences,
                decoration: fieldDecoration('Title (optional)', icon: Icons.title_rounded),
                inputFormatters: [LengthLimitingTextInputFormatter(200)],
                onSubmitted: (_) => save(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: save, child: const Text('Save')),
          ],
        );
      },
    ),
  );
}

/// Links in the task form: add, edit, remove.
class LinksEditor extends StatelessWidget {
  final List<TaskLink> links;
  final ValueChanged<List<TaskLink>> onChanged;
  const LinksEditor({super.key, required this.links, required this.onChanged});

  static const maxLinks = 20;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < links.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(linkIcon(links[i].url), size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final l = await linkDialog(context, initial: links[i]);
                      if (l != null) onChanged([...links]..[i] = l);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(links[i].label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textMuted),
                  onPressed: () => onChanged([...links]..removeAt(i)),
                ),
              ],
            ),
          ),
        if (links.length < maxLinks)
          OutlinedButton.icon(
            onPressed: () async {
              final l = await linkDialog(context);
              if (l != null) onChanged([...links, l]);
            },
            icon: const Icon(Icons.add_link_rounded),
            label: const Text('Add link (Drive, Docs, website)'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- history

/// "Ali moved it to In progress" etc. [nameOf] turns a uid (or a personal
/// contact id) into a name, "You" for me.
String historyText(TaskEvent e, String Function(String? id) nameOf) {
  final who = e.by == null ? 'Someone' : nameOf(e.by);
  return switch (e.kind) {
    HistoryKind.created => '$who created the task',
    HistoryKind.edited => '$who edited the task',
    HistoryKind.assigned =>
      e.to == e.by ? '$who took the task' : '$who assigned it to ${nameOf(e.to)}',
    HistoryKind.unassigned => '$who removed the assignee',
    HistoryKind.stage => e.to == TaskStage.boardDone
        ? '$who marked it done'
        : '$who moved it to ${TaskStage.label(e.to ?? '')}',
    HistoryKind.done => '$who marked it done',
    HistoryKind.reopened => '$who reopened it',
    HistoryKind.cancelled => '$who cancelled it',
    HistoryKind.restored => '$who restored it',
    HistoryKind.approved => '$who approved it',
    HistoryKind.changes => '$who asked for changes',
    _ => '$who changed the task',
  };
}

IconData historyIcon(String kind) => switch (kind) {
      HistoryKind.created => Icons.add_circle_outline_rounded,
      HistoryKind.edited => Icons.edit_outlined,
      HistoryKind.assigned || HistoryKind.unassigned => Icons.person_outline_rounded,
      HistoryKind.stage => Icons.view_kanban_outlined,
      HistoryKind.done => Icons.check_circle_outline_rounded,
      HistoryKind.approved => Icons.verified_outlined,
      HistoryKind.changes => Icons.replay_rounded,
      HistoryKind.reopened || HistoryKind.restored => Icons.undo_rounded,
      HistoryKind.cancelled => Icons.cancel_outlined,
      _ => Icons.history_rounded,
    };

String _when(DateTime d) {
  final now = DateTime.now();
  final day = isSameDay(d, now)
      ? 'Today'
      : isSameDay(d, now.subtract(const Duration(days: 1)))
          ? 'Yesterday'
          : DateFormat(d.year == now.year ? 'd MMM' : 'd MMM yyyy').format(d);
  return '$day, ${formatTime(d)}';
}

/// The task's history, newest first; long lists are folded.
class TaskHistoryView extends StatefulWidget {
  final TaskItem task;
  final String Function(String? id) nameOf;
  const TaskHistoryView({super.key, required this.task, required this.nameOf});

  @override
  State<TaskHistoryView> createState() => _TaskHistoryViewState();
}

class _TaskHistoryViewState extends State<TaskHistoryView> {
  bool _all = false;
  static const _folded = 5;

  @override
  Widget build(BuildContext context) {
    final events = widget.task.historyOrDerived.reversed.toList();
    final shown = _all ? events : events.take(_folded).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _sectionTitle('History'),
        for (var i = 0; i < shown.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 28,
                  child: Column(
                    children: [
                      Icon(historyIcon(shown[i].kind), size: 18, color: AppColors.primary),
                      if (i < shown.length - 1)
                        Expanded(
                          child: Container(
                              width: 2,
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              color: AppColors.border),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(historyText(shown[i], widget.nameOf),
                            style: const TextStyle(fontSize: 13.5)),
                        Text(_when(shown[i].at),
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (events.length > _folded)
          TextButton(
            onPressed: () => setState(() => _all = !_all),
            child: Text(_all ? 'Show less' : 'Show all (${events.length})'),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ timer

/// Asks how long someone really worked when a timer ran very long
/// (forgotten). Returns the end time to save, or null to keep it running.
Future<DateTime?> _confirmLongTimer(BuildContext context, DateTime start, DateTime now) async {
  final ran = now.difference(start);
  final hours = TextEditingController();
  String? error;
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Long timer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The timer ran for ${formatDuration(ran)}. If you forgot to stop it, '
                'enter the hours you actually worked.'),
            const SizedBox(height: 12),
            TextField(
              controller: hours,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: fieldDecoration('Hours worked, e.g. 1.5', icon: Icons.timer_outlined)
                  .copyWith(errorText: error),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final h = double.tryParse(hours.text.trim().replaceAll(',', '.'));
              if (h == null || h <= 0 || h * 60 > ran.inMinutes + 1) {
                setState(() => error = 'Between 0 and ${formatDuration(ran)}');
                return;
              }
              Navigator.pop(ctx, start.add(Duration(minutes: (h * 60).round())));
            },
            child: const Text('Save hours'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, now),
            child: Text('Save ${formatDuration(ran)}'),
          ),
        ],
      ),
    ),
  );
}

/// Stops a running timer, asking first when it ran over 4 hours.
Future<void> stopTimerWithCheck(BuildContext context, TaskItem task, {Team? team}) async {
  final start = task.timerAt;
  if (start == null) return;
  final now = DateTime.now();
  var end = now;
  if (now.difference(start) > const Duration(hours: 4)) {
    final picked = await _confirmLongTimer(context, start, now);
    if (picked == null) return;
    end = picked;
  }
  TimeTracker.stop(task, team: team, end: end);
}

/// Time tracked on a task, with Start / Stop.
class TimeTrackerCard extends StatefulWidget {
  final TaskItem task;

  /// Team tasks: names, and who may start/stop.
  final Team? team;

  /// Uid of the logged-in user ("You").
  final String? me;
  final String Function(String? id) nameOf;

  const TimeTrackerCard(
      {super.key, required this.task, this.team, required this.me, required this.nameOf});

  @override
  State<TimeTrackerCard> createState() => _TimeTrackerCardState();
}

class _TimeTrackerCardState extends State<TimeTrackerCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(TimeTrackerCard old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.task.timerRunning) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final team = widget.team;
    final now = DateTime.now();
    final running = task.timerRunning;
    final canStart = !running &&
        task.status == TaskStatus.pending &&
        (team == null || TeamStore.instance.canComplete(team, task));
    final canStop = running && (team == null || TeamStore.instance.canStopTimer(team, task));
    final total = task.timeSpent(now: now);
    final people = task.timeByPerson;
    if (!running && !canStart && total == Duration.zero) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: running ? AppColors.primaryLight : AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(running ? Icons.timer_rounded : Icons.timer_outlined,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Time tracked',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    Text(formatDuration(total),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              if (canStart)
                FilledButton.icon(
                  onPressed: () => TimeTracker.start(task, team: team),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start'),
                )
              else if (canStop)
                FilledButton.icon(
                  onPressed: () => stopTimerWithCheck(context, task, team: team),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(formatClock(now.difference(task.timerAt!))),
                ),
            ],
          ),
          if (running && (team != null && task.timerBy != widget.me || !canStop)) ...[
            const SizedBox(height: 6),
            Text(
                '${widget.nameOf(task.timerBy)} ${task.timerBy == widget.me ? 'are' : 'is'} working on it • '
                '${formatClock(now.difference(task.timerAt!))}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.primary)),
          ],
          if (team != null && people.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final p in people)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Avatar(name: team.nameOf(p.key), size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(widget.nameOf(p.key),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13))),
                    Text(formatDuration(p.value),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- mentions

/// Comment text with "@Name" of team members shown in bold blue.
class MentionText extends StatelessWidget {
  final String text;
  final Team team;
  final TextStyle style;
  const MentionText({super.key, required this.text, required this.team, required this.style});

  @override
  Widget build(BuildContext context) {
    final names = <String>{
      for (final uid in team.memberIds) ...[
        mentionName(team, uid),
        mentionName(team, uid).split(RegExp(r'\s+')).first,
      ],
    }.where((n) => n.isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (names.isEmpty || !text.contains('@')) return Text(text, style: style);
    final pattern = RegExp(
        '(?<![\\p{L}\\p{N}_.])@(${names.map(RegExp.escape).join('|')})(?![\\p{L}\\p{N}_])',
        caseSensitive: false,
        unicode: true);
    final spans = <TextSpan>[];
    var pos = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > pos) spans.add(TextSpan(text: text.substring(pos, m.start)));
      spans.add(TextSpan(
          text: m.group(0),
          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)));
      pos = m.end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

/// The "@abc" being typed just before the cursor, or null.
({int start, String query})? mentionQuery(TextEditingValue v) {
  final cursor = v.selection.baseOffset;
  if (cursor < 0 || cursor > v.text.length) return null;
  final before = v.text.substring(0, cursor);
  final at = before.lastIndexOf('@');
  if (at < 0) return null;
  if (at > 0 && !RegExp(r'\s').hasMatch(before[at - 1])) return null;
  final query = before.substring(at + 1);
  if (query.length > 30 || query.contains('\n') || query.contains('  ')) return null;
  return (start: at, query: query);
}

/// A running timer on the home page: task, ticking clock and Stop.
class RunningTimerBanner extends StatefulWidget {
  final TaskItem task;
  final Team? team;
  final VoidCallback onOpen;
  const RunningTimerBanner({super.key, required this.task, this.team, required this.onOpen});

  @override
  State<RunningTimerBanner> createState() => _RunningTimerBannerState();
}

class _RunningTimerBannerState extends State<RunningTimerBanner> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final at = widget.task.timerAt;
    if (at == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                const Icon(Icons.timer_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                      Text(
                          '${widget.team?.name ?? 'Personal'} • ${formatClock(DateTime.now().difference(at))}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => stopTimerWithCheck(context, widget.task, team: widget.team),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Stop'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
