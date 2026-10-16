import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../data/task_repository.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../widgets/approval.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import '../widgets/task_extras.dart';
import 'approvals_screen.dart';
import 'main_shell.dart';
import 'task_open.dart';
import 'task_ui.dart';
import 'teams_screen.dart';

/// Notification Center: mentions, assignments, reminders and approvals in
/// one place, with the action right on each one (Reply, View Task, Approve,
/// Snooze...).
class NotificationsScreen extends StatefulWidget {
  /// Opened as its own page (phone, or from Profile).
  final bool page;
  const NotificationsScreen({super.key, this.page = true});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

enum _Tab { all, unread, mentions, assignments, reminders, approvals }

String _tabLabel(_Tab t) => switch (t) {
      _Tab.all => 'All',
      _Tab.unread => 'Unread',
      _Tab.mentions => 'Mentions',
      _Tab.assignments => 'Assignments',
      _Tab.reminders => 'Reminders',
      _Tab.approvals => 'Approvals',
    };

IconData _tabIcon(_Tab t) => switch (t) {
      _Tab.all || _Tab.unread => Icons.notifications_none_rounded,
      _Tab.mentions => Icons.alternate_email_rounded,
      _Tab.assignments => Icons.person_outline_rounded,
      _Tab.reminders => Icons.calendar_today_outlined,
      _Tab.approvals => Icons.check_circle_outline_rounded,
    };

bool _inTab(AppNotification n, _Tab t) => switch (t) {
      _Tab.all => true,
      _Tab.unread => !n.isRead,
      _ => NotifKind.tabOf(n.kind) == t.name,
    };

/// The task a notification is about, if it still exists.
TaskRef? _refOf(AppNotification n) {
  final id = n.taskId;
  if (id == null) return null;
  final teamId = n.teamId;
  if (teamId == null) {
    final t = AppStore.instance.taskById(id);
    if (t != null) return TaskRef(t);
    // Older team notifications did not keep the team.
    for (final team in TeamStore.instance.teams) {
      final tt = TeamStore.instance.taskById(team.id, id);
      if (tt != null) return TaskRef(tt, team);
    }
    return null;
  }
  final team = TeamStore.instance.teamById(teamId);
  final t = team == null ? null : TeamStore.instance.taskById(teamId, id);
  return t == null ? null : TaskRef(t, team);
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  _Tab _tab = _Tab.all;
  String? _teamFilter;

  AppStore get _store => AppStore.instance;

  void _open(AppNotification n, {bool comments = false}) {
    if (!n.isRead) _store.setRead(n, true);
    final ref = _refOf(n);
    if (ref != null) {
      openTaskRef(context, ref, comments: comments);
    } else if (n.kind == NotifKind.invite || n.kind == 'team') {
      _openTeams();
    } else if (n.taskId != null) {
      showSnack(context, 'This task is no longer available.');
    }
  }

  void _openTeams() {
    if (widget.page) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  const Scaffold(backgroundColor: AppColors.background, body: TeamsScreen())));
    } else {
      MainShell.switchTab(context, 4);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_store, TeamStore.instance]),
      builder: (context, _) {
        final now = DateTime.now();
        final all = _store
            .visibleNotifications(now)
            .where((n) => _teamFilter == null || n.teamId == _teamFilter)
            .toList();
        final list = all.where((n) => _inTab(n, _tab)).toList();
        return LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final side = box.maxWidth >= 1150;
          final main = _main(context, all, list, wide, now);
          final body = side
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: main),
                    const SizedBox(width: 22),
                    SizedBox(width: 380, child: _side(context, all, now)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    main,
                    if (wide) ...[const SizedBox(height: 18), _side(context, all, now)],
                  ],
                );
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: widget.page && !wide
                ? AppBar(
                    backgroundColor: AppColors.background,
                    title: const Text('Notifications'),
                    actions: [
                      IconButton(
                        tooltip: 'Mark all as read',
                        onPressed: _store.unreadCount == 0 ? null : _store.markAllRead,
                        icon: const Icon(Icons.done_all_rounded),
                      ),
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: () => _settingsSheet(context),
                        icon: const Icon(Icons.tune_rounded),
                      ),
                    ],
                  )
                : (widget.page
                    ? AppBar(backgroundColor: AppColors.background, toolbarHeight: 44)
                    : null),
            body: ListView(
              padding: EdgeInsets.fromLTRB(wide ? 28 : 16, wide ? 22 : 4, wide ? 28 : 16, 32),
              children: [body],
            ),
          );
        });
      },
    );
  }

  // ------------------------------------------------------------- main list

  Widget _main(BuildContext context, List<AppNotification> all, List<AppNotification> list,
      bool wide, DateTime now) {
    final unread = all.where((n) => !n.isRead).length;
    final tabs = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in _Tab.values)
          _TabButton(
            label: _tabLabel(t),
            icon: t == _Tab.all ? null : _tabIcon(t),
            count: t == _Tab.unread ? unread : 0,
            active: _tab == t,
            onTap: () => setState(() => _tab = t),
          ),
      ],
    );
    final teams = TeamStore.instance.teams;
    final tools = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: unread == 0 ? null : _store.markAllRead,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Mark all as read'),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'Filter',
          position: PopupMenuPosition.under,
          onSelected: (v) async {
            if (v == '__clear') {
              final ok = await confirmDialog(context,
                  title: 'Clear notifications?',
                  message: 'All notifications will be removed.',
                  confirmLabel: 'Clear',
                  danger: true);
              if (ok) await _store.clearNotifications();
              return;
            }
            setState(() => _teamFilter = v.isEmpty ? null : v);
          },
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
                value: '', checked: _teamFilter == null, child: const Text('All teams')),
            for (final t in teams)
              CheckedPopupMenuItem(value: t.id, checked: _teamFilter == t.id, child: Text(t.name)),
            const PopupMenuDivider(),
            const PopupMenuItem(
                value: '__clear',
                child: Text('Clear all notifications', style: TextStyle(color: AppColors.danger))),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _teamFilter == null ? AppColors.border : AppColors.primary),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.filter_alt_outlined, size: 18),
              SizedBox(width: 6),
              Text('Filter', style: TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ],
    );

    // Group by day.
    final groups = <String, List<AppNotification>>{};
    for (final n in list) {
      groups.putIfAbsent(_groupOf(n.shownAt, now), () => []).add(n);
    }
    final approvals =
        _tab == _Tab.approvals ? TeamStore.instance.awaitingMyApproval : const <(Team, TaskItem)>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide) ...[
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: IconBox(icon: Icons.notifications_rounded, color: AppColors.primary),
              ),
              SizedBox(width: 14),
              Expanded(
                child: PageHeader(
                    title: 'Notifications',
                    subtitle: 'Mentions, assignments, reminders and approvals in one place.'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: tabs), const SizedBox(width: 12), tools],
          ),
        ] else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final t in _Tab.values) ...[
                _TabButton(
                  label: _tabLabel(t),
                  icon: null,
                  count: t == _Tab.unread ? unread : 0,
                  active: _tab == t,
                  onTap: () => setState(() => _tab = t),
                ),
                const SizedBox(width: 8),
              ],
            ]),
          ),
        const SizedBox(height: 16),
        if (_tab == _Tab.approvals) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => widget.page || !wide
                  ? Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const ApprovalsScreen(page: true)))
                  : MainShell.switchTab(context, 7),
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Open Approval Center'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (approvals.isNotEmpty) ...[
          _ApprovalQueue(items: approvals),
          const SizedBox(height: 16),
        ],
        if (list.isEmpty)
          DashCard(
            child: EmptyState(
              icon: Icons.notifications_off_outlined,
              title: _tab == _Tab.unread ? 'All read' : 'No notifications',
              subtitle: "You're all caught up.",
            ),
          )
        else
          for (final e in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 0, 8),
              child: Text(e.key, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            DashCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, n) in e.value.indexed) ...[
                    if (i > 0) const Divider(height: 1, color: AppColors.border),
                    _NotifRow(
                      n: n,
                      wide: wide,
                      now: now,
                      onOpen: () => _open(n),
                      onReply: () => _open(n, comments: true),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
      ],
    );
  }

  static String _groupOf(DateTime d, DateTime now) {
    final today = dateOnly(now);
    final day = dateOnly(d);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    if (day.isAfter(today.subtract(const Duration(days: 7)))) return 'Earlier this week';
    return 'Older';
  }

  // ------------------------------------------------------------ right side

  Widget _side(BuildContext context, List<AppNotification> all, DateTime now) {
    // Approvals: what is waiting for me now; the rest: unread.
    int unreadIn(_Tab t) => t == _Tab.approvals
        ? TeamStore.instance.awaitingMyApproval.length
        : all.where((n) => !n.isRead && _inTab(n, t)).length;
    final tiles = [
      (_Tab.unread, Icons.mail_outline_rounded, AppColors.primary, 'Unread'),
      (_Tab.mentions, Icons.alternate_email_rounded, AppColors.purple, 'Mentions'),
      (_Tab.reminders, Icons.calendar_today_rounded, AppColors.danger, 'Reminders'),
      (_Tab.approvals, Icons.check_circle_rounded, AppColors.success, 'Approvals'),
    ];
    final upcoming = TaskRepository.myTasks()
        .where((r) =>
            r.task.status == TaskStatus.pending &&
            !r.task.isAllDay &&
            r.task.startAt.isAfter(now) &&
            r.task.startAt.isBefore(now.add(const Duration(days: 7))))
        .toList()
      ..sort((a, b) => a.task.startAt.compareTo(b.task.startAt));

    Widget title(IconData icon, Color color, String text, [String? sub]) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(text, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                  if (sub != null)
                    Text(sub, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                ]),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title(Icons.notifications_none_rounded, AppColors.primary, 'Unread overview'),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.75,
                children: [
                  for (final (tab, icon, color, label) in tiles)
                    Material(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => _tab = tab),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              IconBox(icon: icon, color: color, size: 40),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${unreadIn(tab)}',
                                        style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                            color: color)),
                                    Text(label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 13, color: AppColors.textMuted)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DashCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title(Icons.settings_rounded, AppColors.primary, 'Notification settings',
                  'Choose what you want to be notified about.'),
              const _SettingsList(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DashCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title(Icons.lightbulb_rounded, const Color(0xFFF59E0B), 'Upcoming reminders',
                  'Your next tasks with a start time.'),
              if (upcoming.isEmpty)
                const Text('Nothing in the next 7 days.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              for (final r in upcoming.take(4))
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => openTaskRef(context, r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        const IconBox(
                            icon: Icons.calendar_today_rounded, color: AppColors.danger, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.task.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                  '${dueLabel(r.task, now)}${isSameDay(r.task.startAt, now) || isSameDay(r.task.startAt, now.add(const Duration(days: 1))) ? '' : ', ${formatTime(r.task.startAt)}'} • ${r.sourceLabel}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(_inText(r.task.startAt, now),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: r.task.startAt.difference(now).inHours < 2
                                    ? AppColors.danger
                                    : AppColors.textMuted)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _inText(DateTime at, DateTime now) {
    final d = at.difference(now);
    if (d.inMinutes < 60) return 'in ${d.inMinutes.clamp(1, 59)} min';
    if (d.inHours < 24) return 'in ${d.inHours} h';
    final days = dateOnly(at).difference(dateOnly(now)).inDays;
    return 'in $days ${days == 1 ? 'day' : 'days'}';
  }

  void _settingsSheet(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.white,
        showDragHandle: true,
        builder: (_) => const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Notification settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              SizedBox(height: 12),
              _SettingsList(),
            ],
          ),
        ),
      );
}

class _SettingsList extends StatelessWidget {
  const _SettingsList();

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Column(
        children: [
          for (final (key, icon, color, title, sub) in const [
            (
              'assign',
              Icons.person_outline_rounded,
              AppColors.primary,
              'Task assignments',
              "When you're assigned to a task"
            ),
            (
              'due',
              Icons.calendar_today_rounded,
              AppColors.danger,
              'Due reminders',
              'Reminders before your tasks start'
            ),
            (
              'approvals',
              Icons.check_circle_rounded,
              AppColors.success,
              'Approvals',
              'When tasks need your approval, or yours are reviewed'
            ),
            (
              'comments',
              Icons.forum_outlined,
              AppColors.purple,
              'Comments & mentions',
              'Replies on your tasks and @mentions'
            ),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  IconBox(icon: icon, color: color, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(sub,
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  Switch(
                    value: store.notifOn(key),
                    onChanged: (v) => store.setNotif(key, v),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final int count;
  final bool active;
  final VoidCallback onTap;
  const _TabButton(
      {required this.label,
      required this.icon,
      required this.count,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: active ? AppColors.primaryLight : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: active ? AppColors.primaryLight : AppColors.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: active ? AppColors.primary : AppColors.text),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: TextStyle(
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? AppColors.primary : AppColors.text)),
              if (count > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                      color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                  child: Text('$count',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
        ),
      );
}

/// Tasks waiting in Review in the teams I run, with Approve right there.
class _ApprovalQueue extends StatelessWidget {
  final List<(Team, TaskItem)> items;
  const _ApprovalQueue({required this.items});

  @override
  Widget build(BuildContext context) => DashCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.hourglass_top_rounded, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Waiting for your approval (${items.length})',
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 6),
            for (final (team, t) in items.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 6,
                  spacing: 10,
                  children: [
                    InkWell(
                      onTap: () => openTaskRef(context, TaskRef(t, team)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                              '${t.assigneeId == null ? 'Unassigned' : team.nameOf(t.assigneeId)} • ${team.name}',
                              style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    Wrap(spacing: 4, runSpacing: 4, children: [
                      TextButton(
                        onPressed: () => openRequestChanges(context, team, t),
                        child: const Text('Request changes'),
                      ),
                      _ApproveButton(onPressed: () => approveTask(context, team, t)),
                    ]),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _ApproveButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ApproveButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.successLight,
          foregroundColor: AppColors.success,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: const Icon(Icons.check_rounded, size: 18),
        label: const Text('Approve'),
      );
}

// --------------------------------------------------------------------- row

class _NotifRow extends StatelessWidget {
  final AppNotification n;
  final bool wide;
  final DateTime now;
  final VoidCallback onOpen;
  final VoidCallback onReply;
  const _NotifRow(
      {required this.n,
      required this.wide,
      required this.now,
      required this.onOpen,
      required this.onReply});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final ref = _refOf(n);
    final team = ref?.team ?? (n.teamId == null ? null : TeamStore.instance.teamById(n.teamId!));
    final (IconData icon, Color color) = switch (n.kind) {
      NotifKind.mention => (Icons.alternate_email_rounded, AppColors.purple),
      NotifKind.comment => (Icons.chat_bubble_outline_rounded, AppColors.purple),
      NotifKind.assigned => (Icons.person_add_alt_1_rounded, AppColors.primary),
      NotifKind.reminder => (Icons.calendar_today_rounded, AppColors.danger),
      NotifKind.approval || NotifKind.approved => (Icons.check_circle_rounded, AppColors.success),
      NotifKind.changes => (Icons.replay_rounded, AppColors.warning),
      NotifKind.invite || 'team' => (Icons.groups_rounded, AppColors.primary),
      'completed' => (Icons.check_circle_rounded, AppColors.success),
      'cancelled' => (Icons.cancel_rounded, AppColors.danger),
      'project' => (Icons.folder_rounded, AppColors.primary),
      _ => (Icons.info_outline_rounded, AppColors.textMuted),
    };
    final personal = n.kind == NotifKind.mention || n.kind == NotifKind.comment;
    final leading = personal && n.actorName != null
        ? Avatar(name: n.actorName!, size: 44, color: color)
        : Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withAlpha(28), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22),
          );

    // ---- actions
    final buttons = <Widget>[];
    Widget soft(String label, VoidCallback onTap) => TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: AppColors.primaryLight,
            foregroundColor: AppColors.primary,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(label),
        );
    switch (n.kind) {
      case NotifKind.mention || NotifKind.comment:
        if (ref != null) {
          buttons.add(n.kind == NotifKind.mention
              ? FilledButton(
                  onPressed: onReply,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Reply'))
              : soft('Reply', onReply));
          if (n.kind == NotifKind.mention) buttons.add(soft('View Task', onOpen));
        }
      case NotifKind.reminder:
        buttons
          ..add(PopupMenuButton<int>(
            tooltip: 'Snooze',
            position: PopupMenuPosition.under,
            onSelected: (m) => store.snooze(n, Duration(minutes: m)),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 10, child: Text('10 minutes')),
              PopupMenuItem(value: 60, child: Text('1 hour')),
              PopupMenuItem(value: 24 * 60, child: Text('Tomorrow')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.snooze_rounded, size: 17),
                SizedBox(width: 6),
                Text('Snooze'),
              ]),
            ),
          ))
          ..add(OutlinedButton(
            onPressed: () => store.deleteNotification(n),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: AppColors.text,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Dismiss'),
          ));
      case NotifKind.approval:
        final t = ref?.task;
        if (ref != null &&
            t != null &&
            ref.team != null &&
            awaitingApproval(t) &&
            TeamStore.instance.isAdmin(ref.team!)) {
          buttons.add(_ApproveButton(onPressed: () {
            store.setRead(n, true);
            approveTask(context, ref.team!, t);
          }));
        } else if (t != null && t.isCompleted) {
          buttons.add(const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('Approved', style: TextStyle(color: AppColors.success)),
          ));
        }
        if (ref != null) buttons.add(soft('View Task', onOpen));
      case NotifKind.invite || 'team':
        buttons.add(soft('Open Teams', onOpen));
      default:
        if (ref != null) buttons.add(soft('View Task', onOpen));
    }
    final menu = PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      onSelected: (a) {
        if (a == 'read') store.setRead(n, !n.isRead);
        if (a == 'delete') store.deleteNotification(n);
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'read', child: Text(n.isRead ? 'Mark as unread' : 'Mark as read')),
        const PopupMenuItem(
            value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.danger))),
      ],
    );

    final body = n.body.isEmpty
        ? null
        : (team != null && n.kind == NotifKind.mention
            ? MentionText(
                text: n.body,
                team: team,
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF4B5563), height: 1.35))
            : Text(n.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF4B5563), height: 1.35)));
    final ctxLine = ref == null
        ? null
        : Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                n.kind == NotifKind.mention || n.kind == NotifKind.comment
                    ? Icons.chat_bubble_outline_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 15,
                color: AppColors.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text('${ref.task.title}  •  ${ref.sourceLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            ),
          ]);
    final time = Text(_timeText(n.shownAt, now),
        style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted));

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(n.title,
            style: TextStyle(
                fontSize: 14.5, fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w700)),
        if (body != null) ...[const SizedBox(height: 3), body],
        if (ctxLine != null) ...[const SizedBox(height: 5), ctxLine],
        if (!wide) ...[const SizedBox(height: 4), time],
        if (!wide && buttons.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: buttons),
        ],
      ],
    );

    return InkWell(
      onTap: onOpen,
      child: Container(
        color: n.isRead ? null : AppColors.primaryLight.withAlpha(60),
        padding: const EdgeInsets.fromLTRB(10, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 16,
              height: 44,
              child: n.isRead
                  ? null
                  : Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration:
                            const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      ),
                    ),
            ),
            leading,
            const SizedBox(width: 12),
            Expanded(child: content),
            const SizedBox(width: 8),
            if (wide)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  time,
                  if (wide && buttons.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      for (final (i, b) in buttons.indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        b,
                      ],
                    ]),
                  ],
                ],
              ),
            menu,
          ],
        ),
      ),
    );
  }

  static String _timeText(DateTime d, DateTime now) {
    final day = dateOnly(d);
    final today = dateOnly(now);
    if (day == today) return DateFormat('h:mm a').format(d);
    if (day == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, ${DateFormat('h:mm a').format(d)}';
    }
    return DateFormat(d.year == now.year ? 'EEE, d MMM, h:mm a' : 'd MMM yyyy').format(d);
  }
}
