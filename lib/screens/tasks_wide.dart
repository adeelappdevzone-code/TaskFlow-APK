part of 'tasks_screen.dart';

// My Tasks on a laptop: stats, tabs/search/filter/sort, the task table (or
// board) and on the right Today's focus, progress and upcoming tasks.

extension _WideTasks on _TasksScreenState {
  Widget _buildWide(BuildContext context, _TasksData data) {
    final s = _TaskStats(data.base.map((r) => r.task));
    final now = data.now;
    final todayFocus = data.base
        .where((r) => r.task.status == TaskStatus.pending && isSameDay(r.task.startAt, now))
        .toList()
      ..sort((a, b) => a.task.startAt.compareTo(b.task.startAt));
    final upcoming = TaskRepository.upcoming(data.base, now, limit: 4);
    final screenH = MediaQuery.sizeOf(context).height;

    return LayoutBuilder(builder: (context, box) {
      final withSide = box.maxWidth >= 1180;
      final side = [
        _FocusCard(items: todayFocus, now: now),
        const SizedBox(height: 18),
        _ProgressCard(stats: s),
        const SizedBox(height: 18),
        _UpcomingCard(items: upcoming, onViewAll: () => _update(() => _tab = _Tab.upcoming)),
      ];

      final main = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              _assignedByMe
                  ? 'Team tasks you assigned to other people.'
                  : 'All your personal tasks and tasks assigned to you.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 15)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                  child: _StatTile(
                      icon: Icons.assignment_turned_in_outlined,
                      color: AppColors.primary,
                      value: s.total,
                      label: 'Total tasks')),
              const SizedBox(width: 16),
              Expanded(
                  child: _StatTile(
                      icon: Icons.person_outline_rounded,
                      color: const Color(0xFFE11D48),
                      value: s.pending,
                      label: 'Pending')),
              const SizedBox(width: 16),
              Expanded(
                  child: _StatTile(
                      icon: Icons.warning_amber_rounded,
                      color: AppColors.danger,
                      value: s.overdue,
                      label: 'Overdue')),
              const SizedBox(width: 16),
              Expanded(
                  child: _StatTile(
                      icon: Icons.check_box_rounded,
                      color: AppColors.success,
                      value: s.done,
                      label: 'Done')),
            ],
          ),
          const SizedBox(height: 16),
          _viewsBar(),
          const SizedBox(height: 12),
          _toolbar(data),
          const SizedBox(height: 16),
          if (_board)
            SizedBox(
              height: (screenH - 330).clamp(440.0, 900.0),
              child: _boardFor(data.list, padding: EdgeInsets.zero),
            )
          else
            _TaskTable(list: data.list, now: now, empty: _empty()),
        ],
      );

      return ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
        children: [
          if (withSide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: main),
                const SizedBox(width: 20),
                SizedBox(
                  width: 360,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: side),
                ),
              ],
            )
          else ...[
            main,
            const SizedBox(height: 20),
            ...side,
          ],
        ],
      );
    });
  }

  Widget _toolbar(_TasksData data) {
    Widget tab(_Tab t) {
      final selected = _tab == t;
      final red = t == _Tab.overdue && (data.counts[t] ?? 0) > 0;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _update(() => _tab = t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color:
                selected ? AppColors.primary : (red ? const Color(0xFFFFF1F1) : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('${_tabLabel(t)} (${data.counts[t]})',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: selected ? Colors.white : (red ? AppColors.danger : AppColors.text),
              )),
        ),
      );
    }

    final box = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE6EAF0)),
    );

    return LayoutBuilder(builder: (context, c) {
      // Narrow: search becomes a button, tabs scroll sideways if needed.
      final roomy = c.maxWidth >= 1080;
      return Row(
        children: [
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: box,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final t in _Tab.values) tab(t),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (roomy)
            SizedBox(
              width: 170,
              height: 46,
              child: TextField(
                controller: _search,
                onChanged: (_) => _update(() {}),
                decoration: fieldDecoration('Search tasks...', icon: Icons.search_rounded)
                    .copyWith(contentPadding: EdgeInsets.zero),
              ),
            )
          else
            _ToolButton(
              icon: _search.text.isEmpty ? Icons.search_rounded : Icons.search_off_rounded,
              label: '',
              dot: _search.text.isNotEmpty,
              onTap: () async {
                if (_search.text.isNotEmpty) return _update(_search.clear);
                final q = await textInputDialog(context,
                    title: 'Search tasks', hint: 'Title or description', initial: _search.text);
                if (q != null) _update(() => _search.text = q);
              },
            ),
          const SizedBox(width: 10),
          _ToolButton(
            icon: Icons.filter_alt_outlined,
            label: 'Filter',
            dot: _hasFilter,
            onTap: _openFilter,
          ),
          const SizedBox(width: 10),
          PopupMenuButton<String>(
            tooltip: 'Sort',
            position: PopupMenuPosition.under,
            onSelected: (v) => _update(() => _sort = v),
            itemBuilder: (_) => [
              for (final o in _sortOptions)
                CheckedPopupMenuItem(value: o, checked: o == _sort, child: Text(o)),
            ],
            child: const _ToolButton(
                icon: Icons.swap_vert_rounded, label: 'Sort', trailing: Icons.expand_more_rounded),
          ),
          const SizedBox(width: 10),
          ViewToggle(
            board: !_board,
            onChanged: (list) => _update(() => _board = !list),
            firstIcon: Icons.format_list_bulleted_rounded,
            firstTip: 'List view',
            secondIcon: Icons.grid_view_rounded,
            secondTip: 'Board view',
          ),
        ],
      );
    });
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final IconData? trailing;
  final bool dot;
  final VoidCallback? onTap;
  const _ToolButton(
      {required this.icon, required this.label, this.trailing, this.dot = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final child = Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EAF0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Badge(isLabelVisible: dot, smallSize: 8, child: Icon(icon, size: 19)),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          if (trailing != null) ...[const SizedBox(width: 2), Icon(trailing, size: 18)],
        ],
      ),
    );
    return onTap == null
        ? child
        : InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: child);
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int value;
  final String label;
  const _StatTile(
      {required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: color.withAlpha(28), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 27),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$value',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: AppColors.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------- table

class _TaskTable extends StatelessWidget {
  final List<TaskRef> list;
  final DateTime now;
  final Widget empty;
  const _TaskTable({required this.list, required this.now, required this.empty});

  @override
  Widget build(BuildContext context) {
    return DashCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(builder: (context, box) {
        final full = box.maxWidth >= 860;
        const head =
            TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
              child: Row(
                children: [
                  const SizedBox(width: 40),
                  const Expanded(flex: 5, child: Text('Title', style: head)),
                  const Expanded(flex: 3, child: Text('Team / Project', style: head)),
                  const SizedBox(width: 120, child: Text('Due Date', style: head)),
                  if (full) const SizedBox(width: 110, child: Text('Priority', style: head)),
                  const SizedBox(width: 120, child: Text('Status', style: head)),
                  if (full) const SizedBox(width: 74, child: Text('Assignee', style: head)),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            const Divider(height: 1),
            if (list.isEmpty)
              empty
            else
              for (final (i, r) in list.indexed) ...[
                if (i > 0) const Divider(height: 1),
                _TableRow(ref: r, now: now, full: full),
              ],
          ],
        );
      }),
    );
  }
}

class _TableRow extends StatelessWidget {
  final TaskRef ref;
  final DateTime now;
  final bool full;
  const _TableRow({required this.ref, required this.now, required this.full});

  @override
  Widget build(BuildContext context) {
    final t = ref.task;
    final done = t.isCompleted;
    final assignee = assigneeNameOf(ref);
    return InkWell(
      onTap: () => openTaskRef(context, ref),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Align(
                alignment: Alignment.centerLeft,
                child: TickBox(
                    value: done, onChanged: ref.canComplete ? (v) => ref.setCompleted(v) : null),
              ),
            ),
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  IconBox(icon: taskIconFor(ref), color: Color(ref.sourceColor), size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: done ? AppColors.textMuted : AppColors.text,
                          decoration: done ? TextDecoration.lineThrough : null,
                        )),
                  ),
                  if (t.timerRunning)
                    const Padding(
                      padding: EdgeInsets.only(left: 6, right: 8),
                      child: Icon(Icons.timer_rounded, size: 16, color: AppColors.primary),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Icon(
                      ref.isTeam
                          ? Icons.groups_outlined
                          : (t.projectId != null
                              ? Icons.folder_outlined
                              : Icons.person_outline_rounded),
                      size: 18,
                      color: Color(ref.sourceColor)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(ref.sourceLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, color: Color(0xFF4B5563))),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(dueLabel(t, now),
                  style: TextStyle(
                      fontSize: 14,
                      color: dueIsUrgent(t, now) ? AppColors.danger : const Color(0xFF4B5563))),
            ),
            if (full)
              SizedBox(
                width: 110,
                child: Align(
                    alignment: Alignment.centerLeft, child: PriorityChip(priority: t.priority)),
              ),
            SizedBox(
              width: 120,
              child: Align(alignment: Alignment.centerLeft, child: StatusChip(task: t)),
            ),
            if (full)
              SizedBox(
                width: 74,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Tooltip(message: assignee, child: Avatar(name: assignee, size: 36)),
                ),
              ),
            SizedBox(width: 44, child: TaskActionsMenu(ref: ref)),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- side cards

Widget _cardTitle(IconData icon, String title, {Widget? trailing}) => Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 26),
        const SizedBox(width: 12),
        Expanded(
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        if (trailing != null) trailing,
      ],
    );

class _FocusCard extends StatelessWidget {
  final List<TaskRef> items;
  final DateTime now;
  const _FocusCard({required this.items, required this.now});

  @override
  Widget build(BuildContext context) {
    return DashCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(Icons.track_changes_rounded, "Today's Focus",
              trailing: Text(DateFormat('EEE, d MMM yyyy').format(now),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13))),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child:
                  Text('Nothing left for today. 🎉', style: TextStyle(color: AppColors.textMuted)),
            ),
          for (final (i, r) in items.take(4).indexed) ...[
            if (i > 0) const Divider(height: 1),
            InkWell(
              onTap: () => openTaskRef(context, r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: r.canComplete ? () => r.setCompleted(true) : null,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFC5CBD5), width: 1.6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.task.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          Text(timeRangeText(r.task.startAt, r.task.endAt),
                              style: TextStyle(
                                  fontSize: 13.5,
                                  color: (r.task.endAt ?? r.task.startAt).isBefore(now)
                                      ? AppColors.danger
                                      : AppColors.textMuted)),
                        ],
                      ),
                    ),
                    SourceChip(ref: r, small: true),
                  ],
                ),
              ),
            ),
          ],
          if (items.length > 4)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('+${items.length - 4} more today',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final _TaskStats stats;
  const _ProgressCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final s = stats;
    Widget legend(Color color, int n, String label) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Text('$n ', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, color: Color(0xFF4B5563))),
              ),
            ],
          ),
        );
    return DashCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(Icons.insights_rounded, 'Task Progress'),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: DonutRing(
                  parts: [
                    (s.done, AppColors.success),
                    (s.pending, AppColors.primary),
                    (s.overdue, AppColors.danger),
                  ],
                  total: s.total,
                  center: '${s.pct(s.done)}%',
                  caption: 'Completed',
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    legend(AppColors.success, s.done, 'Completed'),
                    legend(AppColors.primary, s.pending, 'Pending'),
                    legend(AppColors.danger, s.overdue, 'Overdue'),
                    legend(const Color(0xFFD1D5DB), s.total, 'Total'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  final List<TaskRef> items;
  final VoidCallback onViewAll;
  const _UpcomingCard({required this.items, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return DashCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(Icons.calendar_month_outlined, 'Upcoming Tasks',
              trailing: TextButton(onPressed: onViewAll, child: const Text('View all'))),
          const SizedBox(height: 6),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No upcoming tasks.', style: TextStyle(color: AppColors.textMuted)),
            ),
          for (final r in items)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => openTaskRef(context, r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    IconBox(icon: taskIconFor(r), color: Color(r.sourceColor), size: 44),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.task.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          Text(
                              '${dueLabel(r.task, DateTime.now()) == 'Tomorrow' ? 'Tomorrow' : DateFormat('EEE, d MMM').format(r.task.startAt)}'
                              ' • ${r.task.isAllDay ? 'All day' : formatTime(r.task.startAt)}',
                              style: const TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
