import 'package:flutter/material.dart';
import '../data/images.dart';
import '../widgets/images.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../data/task_repository.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../data/time_tracker.dart';
import '../widgets/approval.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import '../widgets/responsive.dart';
import '../widgets/task_extras.dart';
import 'approvals_screen.dart';
import 'create_task_dialog.dart';
import 'task_comments.dart';
import 'task_form_screen.dart';
import 'task_ui.dart';

/// Opens a personal task: over the page on a laptop (side menu stays),
/// otherwise as a new page.
void openTaskDetail(BuildContext context, TaskItem task) =>
    _open(context, PanelTarget(task.id), () => TaskPage(taskId: task.id));

/// Opens a team task the same way.
void openTeamTask(BuildContext context, Team team, TaskItem task, {bool comments = false}) => _open(
    context,
    PanelTarget(task.id, teamId: team.id, comments: comments),
    () => TaskPage(taskId: task.id, teamId: team.id, comments: comments));

void _open(BuildContext context, PanelTarget target, Widget Function() page) {
  final host = DetailPanelHost.of(context);
  if (host != null) {
    host.show(target);
  } else {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page()));
  }
}

enum _Tab { details, subtasks, comments, links, activity }

/// One task, personal or team: header, tabs (details, subtasks, comments,
/// links, activity) and on a laptop the subtasks, comments and activity on
/// the right.
class TaskPage extends StatefulWidget {
  final String taskId;
  final String? teamId;

  /// Set when shown over a page on a laptop: "Back to tasks" closes it.
  final VoidCallback? onClose;

  /// Start on the Comments tab.
  final bool comments;

  const TaskPage(
      {super.key, required this.taskId, this.teamId, this.onClose, this.comments = false});

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  late _Tab _tab = widget.comments && widget.teamId != null ? _Tab.comments : _Tab.details;

  void _back() {
    final close = widget.onClose;
    if (close != null) {
      close();
    } else {
      Navigator.maybePop(context);
    }
  }

  TaskRef? _resolve() {
    final teamId = widget.teamId;
    if (teamId == null) {
      final t = AppStore.instance.taskById(widget.taskId);
      return t == null ? null : TaskRef(t);
    }
    final team = TeamStore.instance.teamById(teamId);
    final t = team == null ? null : TeamStore.instance.taskById(teamId, widget.taskId);
    return t == null ? null : TaskRef(t, team);
  }

  String _nameOf(TaskRef r, String? uid) {
    final me = r.isTeam ? TeamStore.instance.uid : AppStore.instance.currentUser?.id;
    if (uid == null || uid == me || !r.isTeam) return 'You';
    return r.team!.nameOf(uid);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppStore.instance, TeamStore.instance]),
      builder: (context, _) {
        final ref = _resolve();
        if (ref == null) {
          return Scaffold(
            appBar: AppBar(leading: BackButton(onPressed: _back)),
            body: const EmptyState(
              icon: Icons.delete_outline_rounded,
              title: 'Task not found',
              subtitle: 'It may have been deleted.',
            ),
          );
        }
        if (!ref.isTeam && _tab == _Tab.comments) _tab = _Tab.details;
        return LayoutBuilder(
          builder: (context, box) {
            return box.maxWidth >= kWideLayout
                ? _wide(context, ref, box.maxWidth)
                : _phone(context, ref);
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------- layouts

  Widget _wide(BuildContext context, TaskRef ref, double width) {
    final side = width >= 1150;
    final right = [
      _SubtasksCard(ref: ref, onEdit: ref.canEdit ? () => _edit(ref) : null, menu: _menu(ref)),
      if (ref.isTeam) ...[
        const SizedBox(height: 18),
        DashCard(
          padding: const EdgeInsets.all(18),
          child: TaskComments(
            key: ValueKey('c-${ref.task.id}'),
            team: ref.team!,
            task: ref.task,
            limit: 3,
            onViewAll: () => setState(() => _tab = _Tab.comments),
          ),
        ),
      ],
      const SizedBox(height: 18),
      DashCard(
        padding: const EdgeInsets.all(18),
        child: _Activity(
            ref: ref,
            nameOf: (id) => _nameOf(ref, id),
            limit: 4,
            onViewAll: () => setState(() => _tab = _Tab.activity)),
      ),
    ];
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(ref: ref, wide: true),
        const SizedBox(height: 14),
        MoveRequestBar(ref: ref),
        ApprovalBar(ref: ref),
        _tabs(ref),
        const SizedBox(height: 14),
        DashCard(padding: const EdgeInsets.all(22), child: _tabBody(ref)),
      ],
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(28, 14, 28, 32),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _back,
              style: TextButton.styleFrom(foregroundColor: AppColors.text),
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              label: const Text('Back to tasks', style: TextStyle(fontSize: 15)),
            ),
          ),
          const SizedBox(height: 6),
          if (side)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: main),
                const SizedBox(width: 22),
                SizedBox(
                  width: 400,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right),
                ),
              ],
            )
          else ...[
            main,
            const SizedBox(height: 18),
            ...right,
          ],
        ],
      ),
    );
  }

  Widget _phone(BuildContext context, TaskRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: BackButton(onPressed: _back),
        title: Text(ref.sourceLabel, style: const TextStyle(fontSize: 15)),
        actions: [_menu(ref)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _Header(ref: ref, wide: false),
          const SizedBox(height: 12),
          MoveRequestBar(ref: ref),
          ApprovalBar(ref: ref),
          _tabs(ref),
          const SizedBox(height: 12),
          DashCard(padding: const EdgeInsets.all(16), child: _tabBody(ref)),
        ],
      ),
      bottomNavigationBar: ref.task.isCancelled ||
              !ref.canComplete ||
              (ref.sendsForReview && (ref.task.isCompleted || ref.task.stage == TaskStage.review))
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: ref.sendsForReview
                    ? PrimaryButton(
                        label: 'Send for review',
                        icon: Icons.send_rounded,
                        onPressed: () => sendForApprovalDialog(context, ref.team!, ref.task),
                      )
                    : ref.task.isCompleted
                        ? PrimaryButton(
                            label: 'Mark as not done',
                            icon: Icons.undo_rounded,
                            color: AppColors.textMuted,
                            onPressed: () => ref.setCompleted(false),
                          )
                        : PrimaryButton(
                            label: 'Mark as Done',
                            icon: Icons.check_rounded,
                            onPressed: () => _markDone(ref),
                          ),
              ),
            ),
    );
  }

  // ------------------------------------------------------------------- tabs

  Widget _tabs(TaskRef ref) {
    final t = ref.task;
    String label(_Tab tab) => switch (tab) {
          _Tab.details => 'Details',
          _Tab.subtasks => 'Subtasks (${t.checklistDone}/${t.checklist.length})',
          _Tab.comments => 'Comments',
          _Tab.links => 'Links (${t.links.length})',
          _Tab.activity => 'Activity',
        };
    final tabs = [
      for (final tab in _Tab.values)
        if (tab != _Tab.comments || ref.isTeam) tab
    ];
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tab in tabs)
              InkWell(
                onTap: () => setState(() => _tab = tab),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: _tab == tab ? AppColors.primary : Colors.transparent, width: 3),
                    ),
                  ),
                  child: Text(label(tab),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: _tab == tab ? FontWeight.w700 : FontWeight.w500,
                        color: _tab == tab ? AppColors.primary : AppColors.text,
                      )),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tabBody(TaskRef ref) => switch (_tab) {
        _Tab.details => _Details(ref: ref, nameOf: (id) => _nameOf(ref, id)),
        _Tab.subtasks => _Subtasks(ref: ref),
        _Tab.comments =>
          TaskComments(key: ValueKey('cf-${ref.task.id}'), team: ref.team!, task: ref.task),
        _Tab.links => _Links(ref: ref),
        _Tab.activity => _Activity(ref: ref, nameOf: (id) => _nameOf(ref, id)),
      };

  // ---------------------------------------------------------------- actions

  void _edit(TaskRef ref) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => TaskFormScreen(task: ref.task, team: ref.team)));

  Future<void> _markDone(TaskRef ref) async {
    final t = ref.task;
    final open = t.checklist.length - t.checklistDone;
    if (open > 0) {
      final ok = await confirmDialog(context,
          title: 'Finish task?',
          message: '$open subtask(s) are still open. Mark the task as done anyway?',
          confirmLabel: 'Mark done');
      if (!ok) return;
    }
    ref.setCompleted(true);
  }

  Widget _menu(TaskRef ref) {
    final t = ref.task;
    final team = ref.team;
    final canStop = t.timerRunning && (team == null || TeamStore.instance.canStopTimer(team, t));
    final canStart = ref.canComplete && t.status == TaskStatus.pending && !t.timerRunning;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (a) async {
        switch (a) {
          case 'edit':
            _edit(ref);
          case 'done':
            t.isCompleted ? ref.setCompleted(false) : await _markDone(ref);
          case 'review':
            await sendForApprovalDialog(context, team!, t);
          case 'start':
            TimeTracker.start(t, team: team);
          case 'stop':
            await stopTimerWithCheck(context, t, team: team);
          case 'gcal':
            launchUrl(googleCalendarLink(t), mode: LaunchMode.externalApplication)
                .catchError((_) => false);
          case 'cancel':
            final ok = await confirmDialog(context,
                title: 'Cancel task?',
                message: 'The task will be marked as cancelled. You can restore it later.',
                confirmLabel: 'Cancel task',
                danger: true);
            if (!ok) return;
            team == null
                ? await AppStore.instance.cancelTask(t)
                : TeamStore.instance.cancelTask(team, t);
          case 'restore':
            team == null
                ? await AppStore.instance.restoreTask(t)
                : TeamStore.instance.cancelTask(team, t, restore: true);
          case 'delete':
            final ok = await confirmDialog(context,
                title: 'Delete task?',
                message: team == null
                    ? 'This task will be deleted.'
                    : 'This task will be deleted for everyone in ${team.name}.',
                confirmLabel: 'Delete',
                danger: true);
            if (!ok) return;
            team == null
                ? await AppStore.instance.deleteTask(t)
                : TeamStore.instance.deleteTask(team, t);
            if (mounted) _back();
        }
      },
      itemBuilder: (_) => [
        if (ref.canEdit) const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (ref.canFinish && !t.isCancelled)
          PopupMenuItem(
              value: 'done', child: Text(t.isCompleted ? 'Mark as not done' : 'Mark as done'))
        else if (ref.sendsForReview &&
            !t.isCancelled &&
            !t.isCompleted &&
            t.stage != TaskStage.review)
          const PopupMenuItem(value: 'review', child: Text('Send for review')),
        if (canStop) const PopupMenuItem(value: 'stop', child: Text('Stop timer')),
        if (canStart) const PopupMenuItem(value: 'start', child: Text('Start timer')),
        const PopupMenuItem(value: 'gcal', child: Text('Add to Google Calendar')),
        if (ref.canEdit)
          t.isCancelled
              ? const PopupMenuItem(value: 'restore', child: Text('Restore task'))
              : const PopupMenuItem(value: 'cancel', child: Text('Cancel task')),
        if (ref.canEdit)
          const PopupMenuItem(
              value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.danger))),
      ],
    );
  }
}

// ===================================================================== header

class _Header extends StatelessWidget {
  final TaskRef ref;
  final bool wide;
  const _Header({required this.ref, required this.wide});

  @override
  Widget build(BuildContext context) {
    final t = ref.task;
    final when = '${relativeDay(t.startAt)} · ${timeRangeText(t.startAt, t.endAt)}';
    return DashCard(
      padding: EdgeInsets.all(wide ? 20 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBox(icon: taskIconFor(ref), color: Color(ref.sourceColor), size: wide ? 76 : 52),
          SizedBox(width: wide ? 20 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title,
                    style: TextStyle(
                      fontSize: wide ? 28 : 21,
                      fontWeight: FontWeight.w800,
                      decoration: t.isCancelled ? TextDecoration.lineThrough : null,
                    )),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusChip(task: t),
                    PriorityChip(priority: t.priority),
                    if (Repeat.isOn(t.repeat))
                      TagChip(label: Repeat.label(t.repeat), color: AppColors.primary),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 18, color: AppColors.textMuted),
                        const SizedBox(width: 8),
                        Text(when,
                            style: TextStyle(
                                fontSize: wide ? 16 : 14,
                                color: dueIsUrgent(t, DateTime.now())
                                    ? AppColors.danger
                                    : AppColors.text)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (wide &&
              ref.sendsForReview &&
              !t.isCancelled &&
              !t.isCompleted &&
              t.stage != TaskStage.review) ...[
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => sendForApprovalDialog(context, ref.team!, t),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Send for review'),
            ),
          ],
          if (wide && ref.canFinish && !t.isCancelled) ...[
            const SizedBox(width: 12),
            t.isCompleted
                ? OutlinedButton.icon(
                    onPressed: () => ref.setCompleted(false),
                    icon: const Icon(Icons.undo_rounded, size: 18),
                    label: const Text('Mark not done'),
                  )
                : FilledButton.icon(
                    onPressed: () => ref.setCompleted(true),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Mark done'),
                  ),
          ],
        ],
      ),
    );
  }
}

// ==================================================================== details

class _Details extends StatelessWidget {
  final TaskRef ref;
  final String Function(String? id) nameOf;
  const _Details({required this.ref, required this.nameOf});

  @override
  Widget build(BuildContext context) {
    final t = ref.task;
    final store = AppStore.instance;
    final cat = ref.isTeam ? null : store.categoryById(t.categoryId);
    final assignee = assigneeNameOf(ref);
    const label = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);
    const value = TextStyle(fontSize: 15.5, color: Color(0xFF374151));

    Widget cell(String title, Widget child) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(title, style: label), const SizedBox(height: 10), child],
          ),
        );

    final statusCell = ref.canComplete && !t.isCancelled
        ? PopupMenuButton<String>(
            tooltip: 'Change status',
            position: PopupMenuPosition.under,
            onSelected: ref.moveTo,
            itemBuilder: (_) => [
              for (final s in [...TaskStage.all, if (ref.canFinish) TaskStage.boardDone])
                PopupMenuItem(
                    value: s, child: Text(s == TaskStage.boardDone ? 'Done' : TaskStage.label(s))),
            ],
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              StatusChip(task: t),
              const Icon(Icons.expand_more_rounded, color: AppColors.textMuted),
            ]),
          )
        : StatusChip(task: t);

    final cells = <Widget>[
      cell(
          'Team / Project',
          Row(children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color(ref.sourceColor).withAlpha(30),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(initials(ref.sourceLabel),
                  style: TextStyle(
                      color: Color(ref.sourceColor), fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(width: 10),
            Flexible(child: Text(ref.sourceLabel, style: value)),
          ])),
      cell(
          'Assignee',
          Row(children: [
            Avatar(name: assignee, size: 34),
            const SizedBox(width: 10),
            Flexible(child: Text(assignee, style: value)),
          ])),
      cell(
          'Due date',
          Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 20, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Text(DateFormat('d MMM yyyy').format(t.startAt), style: value),
          ])),
      cell(
          'Time',
          Row(children: [
            const Icon(Icons.schedule_rounded, size: 20, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Text(timeRangeText(t.startAt, t.endAt), style: value),
          ])),
      cell('Priority', PriorityChip(priority: t.priority)),
      cell('Status', statusCell),
    ];

    return LayoutBuilder(builder: (context, box) {
      final two = box.maxWidth >= 520;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Description', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(t.description.isEmpty ? 'No description.' : t.description,
              style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: t.description.isEmpty ? AppColors.textMuted : const Color(0xFF4B5563))),
          const SizedBox(height: 12),
          const Divider(height: 1),
          if (two)
            for (var i = 0; i < cells.length; i += 2) ...[
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: cells[i]),
                    const VerticalDivider(width: 32),
                    Expanded(child: cells[i + 1]),
                  ],
                ),
              ),
              const Divider(height: 1),
            ]
          else
            for (final c in cells) ...[c, const Divider(height: 1)],
          // -------------------------------------------------------- label
          if (!ref.isTeam)
            cell(
              'Label',
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (cat != null) TagChip(label: cat.name, color: Color(cat.color)),
                _AddButton(
                  tooltip: cat == null ? 'Add label' : 'Change label',
                  onTap: () async {
                    final picked = await _pickLabel(context, t.categoryId);
                    if (picked != null) store.setCategory(t, picked.isEmpty ? null : picked);
                  },
                ),
              ]),
            ),
          if (!ref.isTeam) const Divider(height: 1),
          // ------------------------------------------------------- links
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              children: [
                const Expanded(child: Text('Links & images', style: label)),
                if (ref.canComplete) ...[
                  IconButton(
                    tooltip: 'Add image',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => addTaskImage(context, ref),
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final l = await linkDialog(context);
                      if (l != null) ref.setLinks([...t.links, l]);
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add link'),
                  ),
                ],
              ],
            ),
          ),
          if (t.links.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('No links or images yet.', style: TextStyle(color: AppColors.textMuted)),
            )
          else
            _LinkList(ref: ref),
          const SizedBox(height: 8),
          TimeTrackerCard(
              task: t,
              team: ref.team,
              me: ref.isTeam ? TeamStore.instance.uid : store.currentUser?.id,
              nameOf: nameOf),
        ],
      );
    });
  }
}

/// Personal labels (categories). Returns '' for "no label", null if closed.
Future<String?> _pickLabel(BuildContext context, String? current) {
  final store = AppStore.instance;
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Label'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, ''),
          child: const Text('No label'),
        ),
        for (final c in store.categories)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, c.id),
            child: Row(children: [
              Icon(Icons.label_rounded, color: Color(c.color), size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(c.name)),
              if (c.id == current) const Icon(Icons.check_rounded, color: AppColors.primary),
            ]),
          ),
        SimpleDialogOption(
          onPressed: () async {
            final name = await textInputDialog(ctx, title: 'New label', hint: 'Label name');
            if (name == null || !ctx.mounted) return;
            final c = await store.addCategory(
                name, kPaletteColors[store.categories.length % kPaletteColors.length]);
            if (ctx.mounted) Navigator.pop(ctx, c.id);
          },
          child: const Text('+ New label',
              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

class _AddButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;
  const _AddButton({required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 34,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.add_rounded, size: 20),
          ),
        ),
      );
}

// ===================================================================== links

/// Pick and upload a photo, then add it to the task's links.
Future<void> addTaskImage(BuildContext context, TaskRef ref) async {
  final url = await pickAndUploadImage(context);
  if (url == null) return;
  ref.setLinks([...ref.task.links, TaskLink(title: 'Image', url: url)]);
  if (context.mounted) showSnack(context, 'Image added');
}

class _LinkList extends StatelessWidget {
  final TaskRef ref;
  const _LinkList({required this.ref});

  @override
  Widget build(BuildContext context) {
    final links = ref.task.links;
    final images = [
      for (final (i, l) in links.indexed)
        if (isImageUrl(l.url)) (i, l)
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (i, l) in images)
                ImageThumb(
                  url: l.url,
                  onRemove: ref.canComplete
                      ? () async {
                          final ok = await confirmDialog(context,
                              title: 'Remove this image?',
                              message: 'It is removed from the task.',
                              confirmLabel: 'Remove',
                              danger: true);
                          if (ok) ref.setLinks([...links]..removeAt(i));
                        }
                      : null,
                ),
            ]),
          ),
        for (final (i, l) in links.indexed)
          if (!isImageUrl(l.url))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Material(
                color: Colors.white,
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(color: Color(0xFFEEF1F6)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () => openLink(context, l.url),
                  leading: IconBox(icon: linkIcon(l.url), color: AppColors.primary, size: 40),
                  title: Text(l.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(l.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'More',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (a) async {
                      switch (a) {
                        case 'open':
                          openLink(context, l.url);
                        case 'copy':
                          Clipboard.setData(ClipboardData(text: l.url));
                          showSnack(context, 'Link copied');
                        case 'edit':
                          final n = await linkDialog(context, initial: l);
                          if (n != null) ref.setLinks([...links]..[i] = n);
                        case 'remove':
                          ref.setLinks([...links]..removeAt(i));
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'open', child: Text('Open')),
                      const PopupMenuItem(value: 'copy', child: Text('Copy link')),
                      if (ref.canComplete) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (ref.canComplete)
                        const PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove', style: TextStyle(color: AppColors.danger))),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _Links extends StatelessWidget {
  final TaskRef ref;
  const _Links({required this.ref});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
                child: Text('Links', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            if (ref.canComplete) ...[
              OutlinedButton.icon(
                onPressed: () => addTaskImage(context, ref),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Image'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final l = await linkDialog(context);
                  if (l != null) ref.setLinks([...ref.task.links, l]);
                },
                icon: const Icon(Icons.add_link_rounded),
                label: const Text('Add link'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        const Text('Photos and screenshots, or Google Drive, Docs, Sheets and website links.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        if (ref.task.links.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child:
                Center(child: Text('No links yet.', style: TextStyle(color: AppColors.textMuted))),
          )
        else
          _LinkList(ref: ref),
      ],
    );
  }
}

// ================================================================== subtasks

/// Checklist with progress; tick, add, rename and remove (assignee or
/// owner/manager for team tasks).
class _Subtasks extends StatefulWidget {
  final TaskRef ref;
  final bool compact;
  const _Subtasks({required this.ref, this.compact = false});

  @override
  State<_Subtasks> createState() => _SubtasksState();
}

class _SubtasksState extends State<_Subtasks> {
  final _new = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _new.dispose();
    super.dispose();
  }

  List<ChecklistItem> _copy() => [
        for (final c in widget.ref.task.checklist)
          ChecklistItem(
            id: c.id,
            taskId: c.taskId,
            title: c.title,
            isDone: c.isDone,
            sortOrder: c.sortOrder,
            createdAt: c.createdAt,
            updatedAt: c.updatedAt,
          ),
      ];

  void _add() {
    final text = _new.text.trim();
    if (text.isEmpty) return;
    final now = DateTime.now();
    widget.ref.setChecklist([
      ..._copy(),
      ChecklistItem(
        id: newId(),
        taskId: widget.ref.task.id,
        title: text,
        isDone: false,
        sortOrder: widget.ref.task.checklist.length,
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    _new.clear();
  }

  void _toggle(int i) {
    final list = _copy();
    list[i]
      ..isDone = !list[i].isDone
      ..updatedAt = DateTime.now();
    widget.ref.setChecklist(list);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ref.task;
    final canChange = widget.ref.canComplete && !t.isCancelled;
    final total = t.checklist.length;
    final done = t.checklistDone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.compact) ...[
          Text('Subtasks ($done/$total)',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
        ],
        if (total > 0)
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: done / total,
                    minHeight: 7,
                    backgroundColor: const Color(0xFFE6EAF0),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text('${(done * 100 / total).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        const SizedBox(height: 6),
        if (total == 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No subtasks yet.', style: TextStyle(color: AppColors.textMuted)),
          ),
        for (final (i, c) in t.checklist.indexed)
          Row(
            children: [
              Checkbox(value: c.isDone, onChanged: canChange ? (_) => _toggle(i) : null),
              Expanded(
                child: Text(c.title,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: c.isDone ? AppColors.textMuted : AppColors.text,
                      decoration: c.isDone ? TextDecoration.lineThrough : null,
                    )),
              ),
              if (canChange)
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textMuted, size: 20),
                  onSelected: (a) async {
                    final list = _copy();
                    if (a == 'rename') {
                      final name = await textInputDialog(context,
                          title: 'Rename subtask', initial: c.title, okLabel: 'Save');
                      if (name == null) return;
                      list[i].title = name;
                    } else {
                      list.removeAt(i);
                    }
                    widget.ref.setChecklist(list);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove', style: TextStyle(color: AppColors.danger))),
                  ],
                ),
            ],
          ),
        if (canChange) ...[
          const SizedBox(height: 8),
          if (_adding)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _new,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: [LengthLimitingTextInputFormatter(200)],
                    decoration: fieldDecoration('New subtask'),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _add, icon: const Icon(Icons.add_rounded)),
                IconButton(
                  onPressed: () => setState(() => _adding = false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            )
          else
            Material(
              color: const Color(0xFFF2F6FD),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _adding = true),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, color: AppColors.primary, size: 20),
                      SizedBox(width: 8),
                      Text('Add subtask',
                          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _SubtasksCard extends StatelessWidget {
  final TaskRef ref;
  final VoidCallback? onEdit;
  final Widget menu;
  const _SubtasksCard({required this.ref, required this.onEdit, required this.menu});

  @override
  Widget build(BuildContext context) {
    final t = ref.task;
    return DashCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Subtasks', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Expanded(
                child: Text('${t.checklistDone} of ${t.checklist.length} completed',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ),
              if (onEdit != null)
                FilledButton.tonalIcon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Edit'),
                ),
              menu,
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _Subtasks(ref: ref, compact: true),
          ),
        ],
      ),
    );
  }
}

// ================================================================== activity

class _Activity extends StatelessWidget {
  final TaskRef ref;
  final String Function(String? id) nameOf;
  final int? limit;
  final VoidCallback? onViewAll;
  const _Activity({required this.ref, required this.nameOf, this.limit, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final all = ref.task.historyOrDerived.reversed.toList();
    final shown = limit == null ? all : all.take(limit!).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
                child:
                    Text('Activity', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            if (onViewAll != null && all.length > shown.length)
              TextButton(onPressed: onViewAll, child: const Text('View all')),
          ],
        ),
        const SizedBox(height: 8),
        for (final (i, e) in shown.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 34,
                  child: Column(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _color(e.kind).withAlpha(26),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(historyIcon(e.kind), size: 16, color: _color(e.kind)),
                      ),
                      if (i < shown.length - 1)
                        Expanded(
                          child: Container(
                              width: 2,
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              color: const Color(0xFFE6EAF0)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 14, top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(historyText(e, nameOf), style: const TextStyle(fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(_ago(e.at),
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
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

  static Color _color(String kind) => switch (kind) {
        HistoryKind.created => AppColors.success,
        HistoryKind.done || HistoryKind.approved => AppColors.success,
        HistoryKind.cancelled => AppColors.danger,
        HistoryKind.changes => AppColors.warning,
        HistoryKind.assigned || HistoryKind.unassigned => AppColors.purple,
        _ => AppColors.primary,
      };
}

/// "Just now", "5 min ago", "2 hours ago", "3 days ago", "17 Oct".
String _ago(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} ${diff.inHours == 1 ? 'hour' : 'hours'} ago';
  if (diff.inDays < 7) return '${diff.inDays} ${diff.inDays == 1 ? 'day' : 'days'} ago';
  return DateFormat('d MMM').format(d);
}
