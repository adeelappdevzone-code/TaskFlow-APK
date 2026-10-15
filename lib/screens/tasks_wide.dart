part of 'tasks_screen.dart';

// Tasks page on a laptop (wide screen): stats, filters/search/sort, the task
// list (or board) and on the right Today's focus, a progress ring and the
// upcoming tasks. Phones use the layout in tasks_screen.dart.

extension _WideTasks on _TasksScreenState {
  Widget _buildWide(BuildContext context) {
    final store = AppStore.instance;
    final now = DateTime.now();
    final active = store.tasks.where((t) => !t.isCancelled).toList();
    final done = active.where((t) => t.isCompleted).length;
    final overdue = active.where((t) => t.isOverdue).length;
    final pending = active.length - done;
    final list = _filtered(store);
    final today = active
        .where((t) => t.status == TaskStatus.pending && isSameDay(t.startAt, now))
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final tomorrow = dateOnly(now).add(const Duration(days: 1));
    final upcoming = active
        .where((t) => t.status == TaskStatus.pending && !t.startAt.isBefore(tomorrow))
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final screenH = MediaQuery.sizeOf(context).height;

    String tabLabel(_Tab t) => switch (t) {
          _Tab.all => 'All',
          _Tab.pending => 'Pending',
          _Tab.done => 'Done',
          _Tab.overdue => 'Overdue',
        };

    final main = _wideBoard
        ? SizedBox(
            height: (screenH - 330).clamp(420.0, 900.0),
            child: KanbanBoard(
              tasks: list,
              padding: EdgeInsets.zero,
              canMove: (_) => true,
              onMove: (t, column) => store.moveTo(t, column),
              onOpen: openTaskDetail,
              trailing: (t) {
                final cat = store.categoryById(t.categoryId);
                return cat == null
                    ? const SizedBox.shrink()
                    : TagChip(label: cat.name, color: Color(cat.color));
              },
            ),
          )
        : DashCard(
            padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Text('Tasks (${list.length})',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                if (list.isEmpty)
                  EmptyState(
                    icon: Icons.inbox_outlined,
                    title: _search.text.isNotEmpty || _hasFilter
                        ? 'No matching tasks'
                        : 'No tasks here',
                    subtitle: 'Use "New task" to add one.',
                  )
                else
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
                    _WideTaskRow(task: list[i]),
                  ],
              ],
            ),
          );

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
      children: [
        PageHeader(
          title: 'Tasks',
          subtitle: 'Track, organize, and complete your work in one place.',
          actions: [
            Tooltip(
              message: 'Filter (priority, category)',
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _openFilter,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Badge(
                    isLabelVisible: _hasFilter,
                    smallSize: 8,
                    child: const Icon(Icons.tune_rounded),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
                child: StatCard(
                    icon: Icons.list_alt_rounded,
                    color: AppColors.primary,
                    value: active.length,
                    label: 'Total tasks',
                    colorValue: false)),
            const SizedBox(width: 16),
            Expanded(
                child: StatCard(
                    icon: Icons.schedule_rounded,
                    color: AppColors.warning,
                    value: pending,
                    label: 'Pending')),
            const SizedBox(width: 16),
            Expanded(
                child: StatCard(
                    icon: Icons.warning_amber_rounded,
                    color: AppColors.danger,
                    value: overdue,
                    label: 'Overdue')),
            const SizedBox(width: 16),
            Expanded(
                child: StatCard(
                    icon: Icons.check_circle_rounded,
                    color: AppColors.success,
                    value: done,
                    label: 'Done')),
          ],
        ),
        const SizedBox(height: 20),
        DashCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              for (final t in _Tab.values) ...[
                FilterPill(
                  label: tabLabel(t),
                  selected: _tab == t,
                  onTap: () => _update(() => _tab = t),
                ),
                const SizedBox(width: 10),
              ],
              Container(
                  width: 1,
                  height: 32,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: AppColors.border),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => _update(() {}),
                    decoration: fieldDecoration('Search tasks...', icon: Icons.search_rounded)
                        .copyWith(contentPadding: EdgeInsets.zero),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              SortButton(
                options: _sortOptions,
                selected: _sort,
                onSelected: (v) => _update(() => _sort = v),
              ),
              const SizedBox(width: 14),
              ViewToggle(
                board: !_wideBoard,
                onChanged: (list) => _update(() => _wideBoard = !list),
                firstIcon: Icons.view_list_rounded,
                firstTip: 'List view',
                secondIcon: Icons.view_kanban_outlined,
                secondTip: 'Board view',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 7, child: main),
            const SizedBox(width: 18),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SideList(
                    icon: Icons.calendar_today_outlined,
                    title: "Today's focus",
                    subtitle: formatFullDate(now),
                    tasks: today,
                    empty: 'Nothing left for today.',
                    showDay: false,
                  ),
                  const SizedBox(height: 16),
                  ProgressRingCard(done: done, pending: pending, overdue: overdue),
                  const SizedBox(height: 16),
                  _SideList(
                    icon: Icons.schedule_rounded,
                    title: 'Upcoming tasks',
                    tasks: upcoming,
                    empty: 'No upcoming tasks.',
                    showDay: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One task in the laptop list: status, title, when, checklist, category,
/// assignee and a menu.
class _WideTaskRow extends StatelessWidget {
  final TaskItem task;
  const _WideTaskRow({required this.task});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final t = task;
    final done = t.isCompleted || t.isCancelled;
    final cat = store.categoryById(t.categoryId);
    final member = store.memberById(t.assigneeId);
    final late = t.isOverdue;
    final when = t.endAt == null
        ? '${relativeDay(t.startAt)} • ${formatTime(t.startAt)}'
        : '${relativeDay(t.startAt)} • ${formatTime(t.startAt)} - ${formatTime(t.endAt!)}';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => openTaskDetail(context, t),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            StatusCircle(task: t, onTap: () => store.setCompleted(t, !t.isCompleted)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: done ? AppColors.textMuted : AppColors.text,
                        decoration: t.isCompleted ? TextDecoration.lineThrough : null,
                      )),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (late && !done) ...[
                        const Icon(Icons.warning_amber_rounded, size: 15, color: AppColors.danger),
                        const SizedBox(width: 4),
                      ] else if (t.priority == Priority.high && !done) ...[
                        const Icon(Icons.local_fire_department_rounded,
                            size: 15, color: AppColors.danger),
                        const SizedBox(width: 4),
                      ],
                      Text(when,
                          style: TextStyle(
                              fontSize: 13,
                              color: late && !done ? AppColors.danger : AppColors.textMuted)),
                      if (t.checklist.isNotEmpty) ...[
                        const SizedBox(width: 14),
                        const Icon(Icons.checklist_rounded, size: 16, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text('${t.checklistDone}/${t.checklist.length}',
                            style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      ],
                      if (Repeat.isOn(t.repeat)) ...[
                        const SizedBox(width: 12),
                        const Icon(Icons.repeat_rounded, size: 15, color: AppColors.primary),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (cat != null) ...[
              TagChip(label: cat.name, color: Color(cat.color)),
              const SizedBox(width: 18),
            ],
            SizedBox(
              width: 36,
              child: member == null ? null : Avatar(name: member.name, size: 32),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textMuted),
              onSelected: (a) async {
                switch (a) {
                  case 'open':
                    openTaskDetail(context, t);
                  case 'edit':
                    Navigator.push(
                        context, MaterialPageRoute(builder: (_) => TaskFormScreen(task: t)));
                  case 'done':
                    store.setCompleted(t, !t.isCompleted);
                  case 'delete':
                    final ok = await confirmDialog(context,
                        title: 'Delete task?',
                        message: '"${t.title}" will be deleted.',
                        confirmLabel: 'Delete',
                        danger: true);
                    if (ok) store.deleteTask(t);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'open', child: Text('Open')),
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                    value: 'done',
                    child: Text(t.isCompleted ? 'Mark as not done' : 'Mark as done')),
                const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: AppColors.danger))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small card with a few tasks (Today's focus, Upcoming).
class _SideList extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<TaskItem> tasks;
  final String empty;
  final bool showDay;
  const _SideList({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.tasks,
    required this.empty,
    required this.showDay,
  });

  static const _max = 4;

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return DashCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primaryLight,
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                  ],
                ),
              ),
              if (tasks.length > _max)
                Text('+${tasks.length - _max}',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(empty, style: const TextStyle(color: AppColors.textMuted)),
            )
          else
            for (final t in tasks.take(_max))
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => openTaskDetail(context, t),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      StatusCircle(task: t, onTap: () => store.setCompleted(t, true)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              showDay
                                  ? '${relativeDay(t.startAt)} • ${formatTime(t.startAt)}'
                                  : (t.endAt == null
                                      ? formatTime(t.startAt)
                                      : '${formatTime(t.startAt)} - ${formatTime(t.endAt!)}'),
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      if (store.categoryById(t.categoryId) case final cat?)
                        TagChip(label: cat.name, color: Color(cat.color)),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
