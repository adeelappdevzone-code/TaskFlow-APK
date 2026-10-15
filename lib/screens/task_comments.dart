import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import '../widgets/task_extras.dart';

/// Comments on a team task: everyone in the team can read and write them,
/// type "@" to tag someone. [limit] shows only the newest few (with
/// [onViewAll] to see the rest).
class TaskComments extends StatefulWidget {
  final Team team;
  final TaskItem task;
  final int? limit;
  final VoidCallback? onViewAll;
  final bool showTitle;

  const TaskComments({
    super.key,
    required this.team,
    required this.task,
    this.limit,
    this.onViewAll,
    this.showTitle = true,
  });

  @override
  State<TaskComments> createState() => _TaskCommentsState();
}

class _TaskCommentsState extends State<TaskComments> {
  final _text = TextEditingController();
  late Stream<List<TaskComment>> _stream;
  ({int start, String query})? _mention;

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
    _text.value = TextEditingValue(
        text: next, selection: TextSelection.collapsed(offset: m.start + name.length + 2));
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

  String _author(TaskComment c) =>
      c.authorName.isEmpty ? widget.team.nameOf(c.authorId) : c.authorName;

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    final myName = AppStore.instance.currentUser?.name ?? 'Me';
    return StreamBuilder<List<TaskComment>>(
      stream: _stream,
      builder: (context, snap) {
        final all = snap.data ?? const <TaskComment>[];
        final limit = widget.limit;
        final shown = limit != null && all.length > limit ? all.sublist(all.length - limit) : all;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showTitle)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(all.isEmpty ? 'Comments' : 'Comments (${all.length})',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                    if (widget.onViewAll != null && all.length > shown.length)
                      TextButton(onPressed: widget.onViewAll, child: const Text('View all')),
                  ],
                ),
              ),
            if (snap.hasError)
              const Text('Comments need internet the first time.',
                  style: TextStyle(color: AppColors.textMuted))
            else if (all.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('No comments yet. Post an update for the team.',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
            for (final (i, c) in shown.indexed) ...[
              if (i > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Avatar(
                        name: _author(c),
                        size: 40,
                        color: c.authorId == store.uid ? AppColors.primary : AppColors.purple),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(c.authorId == store.uid ? 'You' : _author(c),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              ),
                              const SizedBox(width: 8),
                              Text(timeAgo(c.createdAt),
                                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            ],
                          ),
                          const SizedBox(height: 3),
                          MentionText(
                              text: c.text,
                              team: widget.team,
                              style: const TextStyle(
                                  fontSize: 14, height: 1.4, color: Color(0xFF4B5563))),
                        ],
                      ),
                    ),
                    if (store.canDeleteComment(widget.team, c))
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textMuted),
                        onSelected: (_) => _delete(c),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete', style: TextStyle(color: AppColors.danger))),
                        ],
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
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
                Avatar(name: myName, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: [LengthLimitingTextInputFormatter(2000)],
                    decoration: fieldDecoration('Add a comment...',
                        suffix: IconButton(
                          tooltip: 'Tag a member',
                          icon: const Icon(Icons.alternate_email_rounded,
                              size: 20, color: AppColors.textMuted),
                          onPressed: _insertAt,
                        )),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton.filled(
                    tooltip: 'Send',
                    onPressed: _send,
                    icon: const Icon(Icons.send_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
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
