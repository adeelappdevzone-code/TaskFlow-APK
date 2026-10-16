import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/approvals.dart';
import '../data/models.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import '../widgets/task_extras.dart';
import 'task_ui.dart';

// Approval Center (inside teams): the list of work sent for approval, the
// review page (deliverables + Approve / Request changes), the feedback page
// with numbered points, and each task's approval history.

String _when(DateTime d) {
  final now = DateTime.now();
  if (isSameDay(d, now)) return 'Today, ${DateFormat('h:mm a').format(d)}';
  if (isSameDay(d, now.subtract(const Duration(days: 1)))) {
    return 'Yesterday, ${DateFormat('h:mm a').format(d)}';
  }
  return DateFormat(d.year == now.year ? 'd MMM, h:mm a' : 'd MMM yyyy').format(d);
}

String _dueText(TaskItem t) {
  final d = t.endAt ?? t.startAt;
  return DateFormat(d.year == DateTime.now().year ? 'd MMM' : 'd MMM yyyy').format(d);
}

(String, IconData, Color, Color) _stateLook(ApprovalState s) => switch (s) {
      ApprovalState.pending => (
          'Awaiting approval',
          Icons.hourglass_top_rounded,
          const Color(0xFFB45309),
          AppColors.warningLight
        ),
      ApprovalState.changes => (
          'Changes requested',
          Icons.replay_rounded,
          AppColors.danger,
          AppColors.dangerLight
        ),
      ApprovalState.approved => (
          'Approved',
          Icons.verified_rounded,
          AppColors.success,
          AppColors.successLight
        ),
    };

class _StateChip extends StatelessWidget {
  final ApprovalState state;
  const _StateChip(this.state);

  @override
  Widget build(BuildContext context) {
    final (label, icon, fg, bg) = _stateLook(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: fg),
        const SizedBox(width: 5),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

Widget _cardTitle(IconData icon, Color color, String text, [String? sub]) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              if (sub != null)
                Text(sub, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
            ]),
          ),
        ],
      ),
    );

/// The page frame used by the approval pages: back button, title, and two
/// columns on a laptop (one on a phone).
class _Frame extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final Widget main;
  final Widget? side;
  final Widget? bottom;
  const _Frame(
      {required this.title,
      required this.subtitle,
      this.actions = const [],
      required this.main,
      this.side,
      this.bottom});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final s = side;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            title: Text(wide ? '' : title),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 0, wide ? 28 : 16, 28),
            children: [
              if (wide) ...[
                PageHeader(title: title, subtitle: subtitle, actions: actions),
                const SizedBox(height: 18),
              ] else if (actions.isNotEmpty) ...[
                Wrap(spacing: 8, runSpacing: 8, children: actions),
                const SizedBox(height: 12),
              ],
              if (s != null && box.maxWidth >= 1100)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: main),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: s),
                  ],
                )
              else ...[
                main,
                if (s != null) ...[const SizedBox(height: 16), s],
              ],
            ],
          ),
          bottomNavigationBar: bottom == null
              ? null
              : SafeArea(
                  child: Container(
                    padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 10, wide ? 28 : 16, 12),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: bottom,
                  ),
                ),
        );
      });
}

// ------------------------------------------------------------ open helpers

void openReview(BuildContext context, Team team, TaskItem task) => Navigator.push(
    context, MaterialPageRoute(builder: (_) => ReviewScreen(teamId: team.id, taskId: task.id)));

void openApprovalHistory(BuildContext context, Team team, TaskItem task) => Navigator.push(context,
    MaterialPageRoute(builder: (_) => ApprovalHistoryScreen(teamId: team.id, taskId: task.id)));

/// Opens the feedback page; true when the feedback was sent.
Future<bool> openRequestChanges(BuildContext context, Team team, TaskItem task) async {
  final sent = await Navigator.push<bool>(context,
      MaterialPageRoute(builder: (_) => RequestChangesScreen(teamId: team.id, taskId: task.id)));
  return sent == true;
}

/// Assignee: cover message + links to the work, then it goes to Review.
Future<void> sendForApprovalDialog(BuildContext context, Team team, TaskItem task) async {
  final note = TextEditingController();
  var links = [...task.links];
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Send for approval'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Your manager will approve it or ask for changes.',
                    style: TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: 14),
                TextField(
                  controller: note,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Message (optional)',
                    hintText: 'What did you do? What should they check?',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Links to the work (Drive, Figma, website...)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                LinksEditor(links: links, onChanged: (l) => setState(() => links = l)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Send'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  TeamStore.instance.submitForApproval(team, task, note: note.text, links: links);
  if (context.mounted) showSnack(context, 'Sent for approval');
}

/// Approve with an optional note.
Future<bool> approveDialog(BuildContext context, Team team, TaskItem task) async {
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Approve work?'),
      content: SizedBox(
        width: 440,
        child: TextField(
          controller: note,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Note for the assignee (optional)'),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.success),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Approve'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  TeamStore.instance.approve(team, task, note: note.text);
  if (context.mounted) showSnack(context, 'Approved "${task.title}"');
  return true;
}

// ----------------------------------------------------------- approval center

enum _Tab { pending, changes, approved, all }

class ApprovalsScreen extends StatefulWidget {
  /// Its own page (phone): shows a back button.
  final bool page;
  const ApprovalsScreen({super.key, this.page = false});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  _Tab _tab = _Tab.pending;
  String? _team;

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final teams = store.teams.where((t) => _team == null || t.id == _team).toList();
        final all = approvalItems(teams, store.tasksOf, store.uid);
        final tasks = [
          for (final team in teams)
            for (final t in store.tasksOf(team.id))
              if (store.isAdmin(team) || t.assigneeId == store.uid) t
        ];
        final now = DateTime.now();
        final month = approvalStats(tasks, since: DateTime(now.year, now.month));
        final ever = approvalStats(tasks);
        int countOf(ApprovalState s) => all.where((i) => i.state == s).length;
        final list = all
            .where((i) => switch (_tab) {
                  _Tab.pending => i.state == ApprovalState.pending,
                  _Tab.changes => i.state == ApprovalState.changes,
                  _Tab.approved => i.state == ApprovalState.approved,
                  _Tab.all => true,
                })
            .toList();
        final anyAdmin = store.teams.any(store.isAdmin);

        return LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final tiles = [
            _Tile(
                Icons.hourglass_top_rounded,
                const Color(0xFFEA7A0C),
                '${countOf(ApprovalState.pending)}',
                anyAdmin ? 'Waiting for review' : 'Waiting for approval'),
            _Tile(Icons.verified_rounded, AppColors.success, '${month.approved}',
                'Approved this month'),
            _Tile(Icons.replay_rounded, AppColors.danger, '${month.changes}', 'Changes this month'),
            _Tile(Icons.timer_outlined, AppColors.primary, approvalTimeText(ever.averageTime),
                'Avg. approval time'),
          ];
          final tabs = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _Tab.values)
                ChoiceChip(
                  label: Text(switch (t) {
                    _Tab.pending => 'Pending (${countOf(ApprovalState.pending)})',
                    _Tab.changes => 'Changes requested',
                    _Tab.approved => 'Approved',
                    _Tab.all => 'All',
                  }),
                  selected: _tab == t,
                  onSelected: (_) => setState(() => _tab = t),
                ),
            ],
          );
          final teamMenu = PopupMenuButton<String>(
            tooltip: 'Team',
            position: PopupMenuPosition.under,
            onSelected: (v) => setState(() => _team = v.isEmpty ? null : v),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                  value: '', checked: _team == null, child: const Text('All teams')),
              for (final t in store.teams)
                CheckedPopupMenuItem(value: t.id, checked: _team == t.id, child: Text(t.name)),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _team == null ? AppColors.border : AppColors.primary),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.groups_outlined, size: 18),
                const SizedBox(width: 6),
                Text(_team == null ? 'All teams' : store.teamById(_team!)?.name ?? 'Team',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              ]),
            ),
          );

          final main = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide) ...[
                const PageHeader(
                    title: 'Approvals',
                    subtitle: 'Review submitted work, approve it or ask for changes.'),
                const SizedBox(height: 18),
                Row(children: [
                  for (final (i, t) in tiles.indexed) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: t),
                  ],
                ]),
              ] else
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.2,
                  children: tiles,
                ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: tabs), const SizedBox(width: 10), teamMenu],
              ),
              const SizedBox(height: 14),
              if (list.isEmpty)
                DashCard(
                  child: EmptyState(
                    icon: Icons.task_alt_rounded,
                    title: _tab == _Tab.pending ? 'Nothing to review' : 'Nothing here',
                    subtitle: anyAdmin
                        ? 'When someone sends work for approval, it shows here.'
                        : 'Use "Send for approval" on your finished team tasks.',
                  ),
                )
              else
                DashCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (final (i, item) in list.indexed) ...[
                      if (i > 0) const Divider(height: 1, color: AppColors.border),
                      _ItemRow(item: item, wide: wide),
                    ],
                  ]),
                ),
            ],
          );
          final side = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DashCard(
                padding: const EdgeInsets.all(16),
                child: _Summary(stats: ever, title: 'Approval summary'),
              ),
              const SizedBox(height: 16),
              DashCard(
                padding: const EdgeInsets.all(16),
                child: _RecentActivity(items: all),
              ),
            ],
          );
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: widget.page
                ? AppBar(backgroundColor: AppColors.background, title: const Text('Approvals'))
                : null,
            body: ListView(
              padding: EdgeInsets.fromLTRB(wide ? 28 : 16, wide ? 22 : 8, wide ? 28 : 16, 28),
              children: [
                if (box.maxWidth >= 1150)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: main),
                      const SizedBox(width: 22),
                      SizedBox(width: 370, child: side),
                    ],
                  )
                else ...[
                  main,
                  const SizedBox(height: 16),
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

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _Tile(this.icon, this.color, this.value, this.label);

  @override
  Widget build(BuildContext context) => DashCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          IconBox(icon: icon, color: color, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                ),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              ],
            ),
          ),
        ]),
      );
}

class _ItemRow extends StatelessWidget {
  final ApprovalItem item;
  final bool wide;
  const _ItemRow({required this.item, required this.wide});

  @override
  Widget build(BuildContext context) {
    final t = item.task;
    final team = item.team;
    final admin = TeamStore.instance.isAdmin(team);
    final sent = item.submission;
    final who = t.assigneeId == null ? 'Unassigned' : team.nameOf(t.assigneeId);
    final meta = [
      team.name,
      who,
      if (item.round > 1) 'Revision ${item.round}',
      if (sent != null) 'sent ${timeAgo(sent.at)}',
    ].join('  •  ');
    final action = item.state == ApprovalState.pending && admin
        ? FilledButton(
            onPressed: () => openReview(context, team, t),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Review'),
          )
        : TextButton(onPressed: () => openReview(context, team, t), child: const Text('View'));
    final info = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _StateChip(item.state),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_today_outlined,
              size: 14, color: t.isOverdue ? AppColors.danger : AppColors.textMuted),
          const SizedBox(width: 4),
          Text(_dueText(t),
              style: TextStyle(
                  fontSize: 12.5, color: t.isOverdue ? AppColors.danger : AppColors.textMuted)),
        ]),
        if (t.links.isNotEmpty)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.link_rounded, size: 15, color: AppColors.textMuted),
            const SizedBox(width: 3),
            Text('${t.links.length}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          ]),
      ],
    );
    return InkWell(
      onTap: () => openReview(context, team, t),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            IconBox(icon: Icons.description_outlined, color: Color(team.color), size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                  if (!wide) ...[
                    const SizedBox(height: 6),
                    Row(children: [Expanded(child: info), action]),
                  ],
                ],
              ),
            ),
            if (wide) ...[
              const SizedBox(width: 12),
              info,
              const SizedBox(width: 12),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

/// Donut (approved / changes / waiting) + average time, revisions, on time.
class _Summary extends StatelessWidget {
  final ApprovalStats stats;
  final String title;
  const _Summary({required this.stats, required this.title});

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final rate = s.onTimeRate;
    Widget metric(String label, String value, {Color? color}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 3),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          ]),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cardTitle(Icons.pie_chart_outline_rounded, AppColors.primary, title),
        Row(
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: DonutRing(
                parts: [
                  (s.approved, AppColors.success),
                  (s.changes, const Color(0xFFF59E0B)),
                  (s.pending, AppColors.purple),
                ],
                total: s.approved + s.changes + s.pending,
                center: '${s.requests}',
                caption: 'Requests',
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (n, label, c) in [
                    (s.approved, 'Approved', AppColors.success),
                    (s.changes, 'Changes requested', const Color(0xFFF59E0B)),
                    (s.pending, 'Waiting', AppColors.purple),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text('$n', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 26, color: AppColors.border),
        Row(children: [
          metric('Avg. approval time', approvalTimeText(s.averageTime)),
          metric('Revisions', '${s.changes}'),
          metric('On-time approvals', rate == null ? '—' : '${(rate * 100).round()}%',
              color: AppColors.success),
        ]),
      ],
    );
  }
}

/// "Ali sent X for approval", "You approved Y"... newest first.
class _RecentActivity extends StatelessWidget {
  final List<ApprovalItem> items;
  const _RecentActivity({required this.items});

  @override
  Widget build(BuildContext context) {
    final me = TeamStore.instance.uid;
    final events = <(ApprovalItem, TaskEvent)>[
      for (final i in items)
        for (final e in approvalTimeline(i.task)) (i, e)
    ]..sort((a, b) => b.$2.at.compareTo(a.$2.at));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cardTitle(Icons.history_rounded, AppColors.primary, 'Recent activity'),
        if (events.isEmpty)
          const Text('No approvals yet.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        for (final (item, e) in events.take(6))
          InkWell(
            onTap: () => openReview(context, item.team, item.task),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  _EventIcon(e, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e.by == me ? 'You' : item.team.nameOf(e.by)} '
                          '${_verb(e)} ${item.task.title}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                        Text('${item.team.name}  •  ${timeAgo(e.at)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _verb(TaskEvent e) => switch (e.kind) {
        HistoryKind.approved => 'approved',
        HistoryKind.changes => 'asked for changes on',
        _ => 'sent for approval',
      };
}

class _EventIcon extends StatelessWidget {
  final TaskEvent e;
  final double size;
  const _EventIcon(this.e, {this.size = 40});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (e.kind) {
      HistoryKind.approved => (Icons.check_rounded, AppColors.success),
      HistoryKind.changes => (Icons.forum_outlined, AppColors.danger),
      _ => (Icons.send_rounded, AppColors.primary),
    };
    return IconBox(icon: icon, color: color, size: size);
  }
}

// ---------------------------------------------------------------- review

/// Base for the pages that show one team task.
abstract class _TaskPage extends StatelessWidget {
  final String teamId;
  final String taskId;
  const _TaskPage({super.key, required this.teamId, required this.taskId});

  Widget buildFor(BuildContext context, Team team, TaskItem task);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: TeamStore.instance,
        builder: (context, _) {
          final team = TeamStore.instance.teamById(teamId);
          final task = team == null ? null : TeamStore.instance.taskById(teamId, taskId);
          if (team == null || task == null) {
            return Scaffold(
              appBar: AppBar(),
              body: const EmptyState(
                icon: Icons.delete_outline_rounded,
                title: 'Task not found',
                subtitle: 'It may have been deleted.',
              ),
            );
          }
          return buildFor(context, team, task);
        },
      );
}

/// Review deliverable: the work (links), the message, Approve / Request
/// changes.
class ReviewScreen extends _TaskPage {
  const ReviewScreen({super.key, required super.teamId, required super.taskId});

  @override
  Widget buildFor(BuildContext context, Team team, TaskItem task) {
    final store = TeamStore.instance;
    final admin = store.isAdmin(team);
    final state = approvalStateOf(task);
    final sent = lastSubmission(task);
    final round = task.history.where(isSubmission).length;
    final canDecide = admin && state == ApprovalState.pending;
    final isMine = task.assigneeId != null && task.assigneeId == store.uid;

    final deliverables = DashCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(Icons.folder_open_rounded, AppColors.primary,
              'Deliverables (${task.links.length})', 'Open each link to check the work.'),
          if (task.links.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('No links attached. Ask for a Drive, Figma or website link.',
                  style: TextStyle(color: AppColors.textMuted)),
            ),
          for (final l in task.links) _LinkTile(link: l),
          if (task.description.isNotEmpty) ...[
            const Divider(height: 28, color: AppColors.border),
            const Text('Task description', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(task.description, style: const TextStyle(height: 1.45)),
          ],
          if (task.checklist.isNotEmpty) ...[
            const Divider(height: 28, color: AppColors.border),
            Text('Checklist (${task.checklistDone}/${task.checklist.length})',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final c in task.checklist)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(c.isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                      size: 19, color: c.isDone ? AppColors.success : AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(c.title)),
                ]),
              ),
          ],
        ],
      ),
    );

    Widget kv(String k, Widget v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 110,
                child: Text(k, style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5))),
            Expanded(child: v),
          ]),
        );
    final who = sent?.by == null ? null : team.nameOf(sent!.by);
    final details = DashCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            IconBox(icon: Icons.description_outlined, color: Color(team.color), size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(task.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text(team.name, style: const TextStyle(color: AppColors.textMuted)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          if (state != null) Align(alignment: Alignment.centerLeft, child: _StateChip(state)),
          const Divider(height: 24, color: AppColors.border),
          if (who != null)
            kv(
                'Submitted by',
                Row(children: [
                  Avatar(name: who, size: 26),
                  const SizedBox(width: 8),
                  Flexible(child: Text(who, style: const TextStyle(fontWeight: FontWeight.w600))),
                ])),
          if (sent != null) kv('Submitted', Text(_when(sent.at))),
          kv('Revision', Text(round <= 1 ? 'First version' : 'Version $round')),
          kv(
              'Due',
              Text(_dueText(task),
                  style: TextStyle(color: task.isOverdue ? AppColors.danger : null))),
          kv('Priority',
              Align(alignment: Alignment.centerLeft, child: PriorityChip(priority: task.priority))),
          if (sent?.note != null) ...[
            const SizedBox(height: 10),
            const Text('Message', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(sent!.note!, style: const TextStyle(height: 1.45)),
            ),
          ],
        ],
      ),
    );

    Widget? bottom;
    if (canDecide) {
      bottom = Align(
          alignment: Alignment.centerRight,
          heightFactor: 1,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final sentBack = await openRequestChanges(context, team, task);
                      if (sentBack && context.mounted) Navigator.maybePop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Request changes'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      final ok = await approveDialog(context, team, task);
                      if (ok && context.mounted) Navigator.maybePop(context);
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Approve work'),
                  ),
                ),
              ])));
    } else if (isMine && task.status == TaskStatus.pending && state != ApprovalState.pending) {
      bottom = FilledButton.icon(
        onPressed: () => sendForApprovalDialog(context, team, task),
        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
        icon: const Icon(Icons.send_rounded, size: 18),
        label: Text(state == ApprovalState.changes ? 'Send new version' : 'Send for approval'),
      );
    }

    return _Frame(
      title: 'Review deliverable',
      subtitle: canDecide
          ? 'Check the submitted work, then approve it or request changes.'
          : 'The submitted work and where it stands.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => openApprovalHistory(context, team, task),
          icon: const Icon(Icons.history_rounded, size: 18),
          label: const Text('Approval history'),
        ),
      ],
      main: deliverables,
      side: details,
      bottom: bottom,
    );
  }
}

class _LinkTile extends StatelessWidget {
  final TaskLink link;
  const _LinkTile({required this.link});

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(link.url)?.host ?? '';
    final (IconData icon, Color color, String kind) = host.contains('figma')
        ? (Icons.design_services_rounded, AppColors.purple, 'Figma')
        : host.contains('docs.google')
            ? (Icons.description_rounded, AppColors.primary, 'Google Docs')
            : host.contains('drive.google')
                ? (Icons.add_to_drive_rounded, AppColors.success, 'Google Drive')
                : host.contains('canva')
                    ? (Icons.palette_rounded, const Color(0xFF0EA5E9), 'Canva')
                    : (Icons.language_rounded, const Color(0xFFEA7A0C), host);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: IconBox(icon: icon, color: color, size: 40),
          title: Text(link.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(kind, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.open_in_new_rounded, size: 20),
          onTap: () => launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication)
              .catchError((_) => false),
        ),
      ),
    );
  }
}

// -------------------------------------------------------- request changes

/// Feedback: a message plus numbered points ("1. Change the headline...").
class RequestChangesScreen extends StatefulWidget {
  final String teamId;
  final String taskId;
  const RequestChangesScreen({super.key, required this.teamId, required this.taskId});

  @override
  State<RequestChangesScreen> createState() => _RequestChangesScreenState();
}

class _RequestChangesScreenState extends State<RequestChangesScreen> {
  final _message = TextEditingController();
  final List<TextEditingController> _points = [TextEditingController()];

  @override
  void dispose() {
    _message.dispose();
    for (final p in _points) {
      p.dispose();
    }
    super.dispose();
  }

  void _send(Team team, TaskItem task) {
    final text = feedbackText(_message.text, [for (final p in _points) p.text]);
    if (text.isEmpty) {
      showSnack(context, 'Write what should be changed.');
      return;
    }
    TeamStore.instance.requestChanges(team, task, text);
    showSnack(context, 'Feedback sent to ${team.nameOf(task.assigneeId)}');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final team = TeamStore.instance.teamById(widget.teamId);
    final task = team == null ? null : TeamStore.instance.taskById(widget.teamId, widget.taskId);
    if (team == null || task == null) {
      return Scaffold(
          appBar: AppBar(),
          body: const EmptyState(
              icon: Icons.delete_outline_rounded,
              title: 'Task not found',
              subtitle: 'It may have been deleted.'));
    }
    final message = DashCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(
              Icons.chat_bubble_outline_rounded, AppColors.primary, 'Your feedback', task.title),
          TextField(
            controller: _message,
            autofocus: true,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
                hintText: 'The overall work looks good! A few changes are needed...'),
          ),
        ],
      ),
    );
    final points = DashCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(
              Icons.format_list_numbered_rounded,
              AppColors.danger,
              'Changes to make (${_points.where((p) => p.text.trim().isNotEmpty).length})',
              'One change per line, so nothing is missed.'),
          for (final (i, c) in _points.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: AppColors.danger,
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: c,
                      minLines: 1,
                      maxLines: 3,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          isDense: true, hintText: 'e.g. Use the brand blue for the button'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: _points.length == 1
                        ? null
                        : () => setState(() => _points.removeAt(i).dispose()),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _points.length >= 20
                  ? null
                  : () => setState(() => _points.add(TextEditingController())),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add another change'),
            ),
          ),
        ],
      ),
    );
    return _Frame(
      title: 'Request changes',
      subtitle: 'Tell ${team.nameOf(task.assigneeId)} what to change. It goes back to In Progress.',
      main: message,
      side: points,
      bottom: Align(
        alignment: Alignment.centerRight,
        heightFactor: 1,
        child: FilledButton.icon(
          onPressed: () => _send(team, task),
          style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text('Send feedback'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- history

/// Every round of one task: sent, changes asked, approved; and its numbers.
class ApprovalHistoryScreen extends _TaskPage {
  const ApprovalHistoryScreen({super.key, required super.teamId, required super.taskId});

  static String _title(TaskEvent e, bool resubmitted) => switch (e.kind) {
        HistoryKind.approved => 'Work approved',
        HistoryKind.changes => 'Changes requested',
        _ => resubmitted ? 'New version submitted' : 'Sent for approval',
      };

  /// The history as plain text (copied for WhatsApp / email).
  static String report(Team team, TaskItem task) {
    final s = approvalStats([task]);
    final lines = <String>[
      'Approval history: ${task.title} (${team.name})',
      '',
    ];
    var seenChanges = false;
    for (final e in approvalTimeline(task)) {
      lines.add('• ${DateFormat('d MMM yyyy, h:mm a').format(e.at)} — '
          '${_title(e, seenChanges && isSubmission(e))} by ${team.nameOf(e.by)}');
      if (e.note != null) lines.add('  ${e.note!.replaceAll('\n', '\n  ')}');
      if (e.kind == HistoryKind.changes) seenChanges = true;
    }
    lines
      ..add('')
      ..add('Requests: ${s.requests}, approved: ${s.approved}, changes: ${s.changes}, '
          'average time: ${approvalTimeText(s.averageTime)}');
    return lines.join('\n');
  }

  @override
  Widget buildFor(BuildContext context, Team team, TaskItem task) {
    final events = approvalTimeline(task);
    final rows = <Widget>[];
    var seenChanges = false;
    final titles = <String>[];
    for (final e in events) {
      titles.add(_title(e, seenChanges && isSubmission(e)));
      if (e.kind == HistoryKind.changes) seenChanges = true;
    }
    for (var i = events.length - 1; i >= 0; i--) {
      final e = events[i];
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EventIcon(e),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titles[i], style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${team.nameOf(e.by)}  •  ${_when(e.at)}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                  if (e.note != null) ...[
                    const SizedBox(height: 6),
                    Text(e.note!, style: const TextStyle(fontSize: 13.5, height: 1.4)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ));
      if (i > 0) rows.add(const Divider(height: 1, color: AppColors.border));
    }
    return _Frame(
      title: 'Approval history',
      subtitle: '${task.title} • ${team.name}',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: report(team, task)));
            showSnack(context, 'Report copied. Paste it in WhatsApp or email.');
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy report'),
        ),
      ],
      main: DashCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardTitle(Icons.timeline_rounded, AppColors.primary, 'Timeline'),
            if (rows.isEmpty)
              const Text('This task has not been sent for approval yet.',
                  style: TextStyle(color: AppColors.textMuted)),
            ...rows,
          ],
        ),
      ),
      side: DashCard(
        padding: const EdgeInsets.all(16),
        child: _Summary(stats: approvalStats([task]), title: 'Summary'),
      ),
    );
  }
}
