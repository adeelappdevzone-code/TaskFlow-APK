import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';
import '../widgets/task_extras.dart';
import 'task_form_screen.dart';

/// Opens a team task: in the side panel on a wide screen, otherwise as a
/// new page.
void openTeamTask(BuildContext context, Team team, TaskItem task) {
  final panel = DetailPanelHost.of(context);
  if (panel != null) {
    panel.show(PanelTarget(task.id, teamId: team.id));
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => TeamTaskDetailScreen(teamId: team.id, taskId: task.id)),
  );
}

/// A team task. Owner/managers can edit, cancel and delete it; the person it
/// is assigned to can tick the checklist and mark it done.
class TeamTaskDetailScreen extends StatelessWidget {
  final String teamId;
  final String taskId;

  /// Set when shown in the side panel (wide screens): closes the panel.
  final VoidCallback? onClose;

  const TeamTaskDetailScreen({super.key, required this.teamId, required this.taskId, this.onClose});

  Future<void> _onMenu(BuildContext context, String action, Team team, TaskItem task) async {
    final store = TeamStore.instance;
    switch (action) {
      case 'edit':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => TaskFormScreen(task: task, team: team)));
        break;
      case 'cancel':
        final ok = await confirmDialog(context,
            title: 'Cancel task?',
            message: 'The task will be marked as cancelled for everyone. You can restore it later.',
            confirmLabel: 'Cancel task',
            danger: true);
        if (ok) store.cancelTask(team, task);
        break;
      case 'restore':
        store.cancelTask(team, task, restore: true);
        break;
      case 'delete':
        final ok = await confirmDialog(context,
            title: 'Delete task?',
            message: 'This task will be deleted for everyone in ${team.name}.',
            confirmLabel: 'Delete',
            danger: true);
        if (ok) {
          store.deleteTask(team, task);
          if (onClose != null) {
            onClose!();
          } else if (context.mounted) {
            Navigator.pop(context);
          }
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final team = store.teamById(teamId);
        final task = team == null ? null : store.taskById(teamId, taskId);
        if (team == null || task == null) {
          return Scaffold(
            appBar: AppBar(
              leading: onClose == null
                  ? null
                  : IconButton(icon: const Icon(Icons.close_rounded), onPressed: onClose),
              automaticallyImplyLeading: onClose == null,
            ),
            body: const EmptyState(
              icon: Icons.delete_outline_rounded,
              title: 'Task not found',
              subtitle: 'It may have been deleted.',
            ),
          );
        }
        final canEdit = store.canEdit(team, task);
        final canComplete = store.canComplete(team, task);
        final priorityColor = switch (task.priority) {
          Priority.low => AppColors.success,
          Priority.medium => AppColors.primary,
          Priority.high => AppColors.danger,
        };
        String nameOf(String? uid) => uid == store.uid ? 'You' : team.nameOf(uid);
        final timeText = task.endAt == null
            ? formatTime(task.startAt)
            : '${formatTime(task.startAt)} - ${formatTime(task.endAt!)}';

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            leading: onClose == null
                ? null
                : IconButton(icon: const Icon(Icons.close_rounded), onPressed: onClose),
            automaticallyImplyLeading: onClose == null,
            title: Text(team.name, style: const TextStyle(fontSize: 15)),
            actions: [
              if (canEdit)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (a) => _onMenu(context, a, team, task),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit / reassign')),
                    if (task.isCancelled)
                      const PopupMenuItem(value: 'restore', child: Text('Restore task'))
                    else
                      const PopupMenuItem(value: 'cancel', child: Text('Cancel task')),
                    const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete', style: TextStyle(color: AppColors.danger))),
                  ],
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(task.title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    decoration: task.isCancelled ? TextDecoration.lineThrough : null,
                  )),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _statusChip(task),
                if (Repeat.isOn(task.repeat))
                  TagChip(label: Repeat.label(task.repeat), color: AppColors.primary),
              ]),
              if (canComplete && task.status == TaskStatus.pending) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (final st in TaskStage.all) ...[
                      if (st != TaskStage.todo) const SizedBox(width: 6),
                      TabPill(
                        label: TaskStage.label(st),
                        active: task.stage == st,
                        onTap: () => store.moveTo(team, task, st),
                      ),
                    ],
                  ],
                ),
              ],
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(task.description,
                    style: const TextStyle(color: Color(0xFF374151), fontSize: 14.5, height: 1.5)),
              ],
              const SizedBox(height: 20),
              _InfoRow(
                icon: Icons.calendar_today_outlined,
                child: Text('${formatFullDate(task.startAt)}  •  $timeText',
                    style: const TextStyle(fontSize: 14)),
              ),
              _InfoRow(
                icon: Icons.local_fire_department_rounded,
                iconColor: priorityColor,
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Priority: ', style: TextStyle(fontSize: 14)),
                  TextSpan(
                      text: task.priority.label,
                      style: TextStyle(
                          fontSize: 14, color: priorityColor, fontWeight: FontWeight.w700)),
                ])),
              ),
              _person('Assigned to',
                  task.assigneeId == null ? 'Nobody yet' : team.nameOf(task.assigneeId)),
              if (task.assignedBy != null) _person('Assigned by', team.nameOf(task.assignedBy)),
              if (task.isCompleted && task.completedAt != null)
                _InfoRow(
                  icon: Icons.check_circle_rounded,
                  iconColor: AppColors.success,
                  child: Text(
                      'Completed ${relativeDay(task.completedAt!)} at ${formatTime(task.completedAt!)}',
                      style: const TextStyle(fontSize: 14)),
                ),
              TimeTrackerCard(task: task, team: team, me: store.uid, nameOf: nameOf),
              TaskLinksView(links: task.links),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Text('Checklist',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  if (task.checklist.isNotEmpty)
                    Text('${task.checklistDone}/${task.checklist.length} done',
                        style: const TextStyle(
                            color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              if (task.checklist.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No checklist items.', style: TextStyle(color: AppColors.textMuted)),
                )
              else
                for (final c in task.checklist)
                  Row(
                    children: [
                      Checkbox(
                        value: c.isDone,
                        onChanged: canComplete && !task.isCancelled
                            ? (_) => store.toggleChecklistItem(team, task, c)
                            : null,
                      ),
                      Expanded(
                        child: Text(c.title,
                            style: TextStyle(
                              fontSize: 14,
                              color: c.isDone ? AppColors.textMuted : AppColors.text,
                              decoration: c.isDone ? TextDecoration.lineThrough : null,
                            )),
                      ),
                    ],
                  ),
              const SizedBox(height: 14),
              TaskHistoryView(task: task, nameOf: nameOf),
              const SizedBox(height: 14),
              _CommentsSection(team: team, task: task),
            ],
          ),
          bottomNavigationBar: task.isCancelled || !canComplete
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: task.isCompleted
                        ? PrimaryButton(
                            label: 'Mark as not done',
                            icon: Icons.undo_rounded,
                            color: AppColors.textMuted,
                            onPressed: () => store.setCompleted(team, task, false),
                          )
                        : PrimaryButton(
                            label: 'Mark as Done',
                            icon: Icons.check_rounded,
                            onPressed: () async {
                              final open = task.checklist.length - task.checklistDone;
                              if (open > 0) {
                                final ok = await confirmDialog(context,
                                    title: 'Finish task?',
                                    message:
                                        '$open checklist item(s) are still open. Mark the task as done anyway?',
                                    confirmLabel: 'Mark done');
                                if (!ok) return;
                              }
                              store.setCompleted(team, task, true);
                            },
                          ),
                  ),
                ),
        );
      },
    );
  }

  Widget _person(String label, String name) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Avatar(name: name, size: 36),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                Text(name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      );

  Widget _statusChip(TaskItem t) => switch (t.displayStatus) {
        DisplayStatus.completed => const TagChip(label: 'Completed', color: AppColors.success),
        DisplayStatus.inProgress => t.stage == TaskStage.review
            ? const TagChip(label: 'In review', color: AppColors.warning)
            : const TagChip(label: 'In progress', color: AppColors.purple),
        DisplayStatus.cancelled => const TagChip(label: 'Cancelled', color: AppColors.danger),
        DisplayStatus.pending => t.isOverdue
            ? const TagChip(label: 'Overdue', color: AppColors.danger)
            : const TagChip(label: 'Pending', color: AppColors.warning),
      };
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final Widget child;
  const _InfoRow({required this.icon, required this.child, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor ?? AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Comments on a team task: everyone in the team can read and write them
/// (e.g. "50% done, waiting for content").
class _CommentsSection extends StatefulWidget {
  final Team team;
  final TaskItem task;
  const _CommentsSection({required this.team, required this.task});

  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  final _text = TextEditingController();
  late Stream<List<TaskComment>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = TeamStore.instance.commentsOf(widget.team.id, widget.task.id);
    _text.addListener(_onTyping);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  ({int start, String query})? _mention;

  void _onTyping() {
    final m = mentionQuery(_text.value);
    if (m?.start != _mention?.start || m?.query != _mention?.query) setState(() => _mention = m);
  }

  /// Members matching the "@abc" being typed (not me).
  List<String> get _suggestions {
    final m = _mention;
    if (m == null) return const [];
    final q = m.query.toLowerCase();
    bool matches(String name) {
      final n = name.toLowerCase();
      return n.isNotEmpty &&
          (n.startsWith(q) || n.split(RegExp(r'\s+')).any((w) => w.startsWith(q)));
    }

    return [
      for (final uid in widget.team.sortedMemberIds)
        if (uid != TeamStore.instance.uid && matches(mentionName(widget.team, uid))) uid,
    ];
  }

  void _pickMention(String uid) {
    final m = _mention;
    if (m == null) return;
    final name = mentionName(widget.team, uid);
    final text = _text.text;
    final end = m.start + 1 + m.query.length;
    final next = '${text.substring(0, m.start)}@$name ${text.substring(end)}';
    final cursor = m.start + name.length + 2;
    _text.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: cursor));
  }

  void _insertAt() {
    final v = _text.value;
    final pos = v.selection.baseOffset < 0 ? v.text.length : v.selection.baseOffset;
    final needsSpace = pos > 0 && !RegExp(r'\s').hasMatch(v.text[pos - 1]);
    final insert = needsSpace ? ' @' : '@';
    _text.value = TextEditingValue(
      text: v.text.replaceRange(pos, pos, insert),
      selection: TextSelection.collapsed(offset: pos + insert.length),
    );
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    TeamStore.instance.addComment(widget.team, widget.task, text);
    _text.clear();
    FocusScope.of(context).unfocus();
  }

  Future<void> _delete(TaskComment c) async {
    final ok = await confirmDialog(context,
        title: 'Delete comment?', message: c.text, confirmLabel: 'Delete', danger: true);
    if (ok) TeamStore.instance.deleteComment(widget.team, c);
  }

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    return StreamBuilder<List<TaskComment>>(
      stream: _stream,
      builder: (context, snap) {
        final comments = snap.data ?? const <TaskComment>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(comments.isEmpty ? 'Comments' : 'Comments (${comments.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (snap.hasError)
              const Text('Comments need internet the first time.',
                  style: TextStyle(color: AppColors.textMuted))
            else if (comments.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('No comments yet. Post an update for the team.',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
            for (final c in comments)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  onLongPress: store.canDeleteComment(widget.team, c) ? () => _delete(c) : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Avatar(
                          name:
                              c.authorName.isEmpty ? widget.team.nameOf(c.authorId) : c.authorName,
                          size: 32,
                          color: c.authorId == store.uid ? AppColors.primary : AppColors.purple),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      c.authorId == store.uid
                                          ? 'You'
                                          : (c.authorName.isEmpty
                                              ? widget.team.nameOf(c.authorId)
                                              : c.authorName),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700, fontSize: 13),
                                    ),
                                  ),
                                  Text(timeAgo(c.createdAt),
                                      style: const TextStyle(
                                          fontSize: 11.5, color: AppColors.textMuted)),
                                ],
                              ),
                              const SizedBox(height: 3),
                              MentionText(
                                  text: c.text,
                                  team: widget.team,
                                  style: const TextStyle(
                                      fontSize: 14, height: 1.35, color: AppColors.text)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 4),
            if (_suggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final uid in _suggestions.take(8))
                      ActionChip(
                        avatar: Avatar(name: widget.team.nameOf(uid), size: 22),
                        label: Text(mentionName(widget.team, uid)),
                        onPressed: () => _pickMention(uid),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: fieldDecoration('Write a comment... (@ to tag)',
                        suffix: IconButton(
                          tooltip: 'Tag a member',
                          icon: const Icon(Icons.alternate_email_rounded,
                              size: 20, color: AppColors.textMuted),
                          onPressed: _insertAt,
                        )),
                    inputFormatters: [LengthLimitingTextInputFormatter(2000)],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _send,
                  icon: const Icon(Icons.send_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
