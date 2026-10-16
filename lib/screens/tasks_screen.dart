import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../data/task_repository.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import '../widgets/responsive.dart';
import '../widgets/task_board.dart';
import 'task_open.dart';
import 'task_ui.dart';

part 'tasks_wide.dart';

enum _Tab { all, today, upcoming, overdue, completed }

String _tabLabel(_Tab t) => switch (t) {
      _Tab.all => 'All',
      _Tab.today => 'Today',
      _Tab.upcoming => 'Upcoming',
      _Tab.overdue => 'Overdue',
      _Tab.completed => 'Completed',
    };

const _sortOptions = ['Due date', 'Priority', 'Name', 'Newest'];

/// My Tasks: my whole workload in one list — personal tasks and the team
/// tasks assigned to me (or, with the filter, the ones I gave to others).
class TasksScreen extends StatefulWidget {
  /// true when opened as its own page (e.g. "High Priority" from Home),
  /// false when shown as a tab.
  final bool standalone;
  final Priority? initialPriority;

  const TasksScreen({super.key, this.standalone = false, this.initialPriority});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  _Tab _tab = _Tab.all;
  final _search = TextEditingController();
  bool _searching = false;
  Priority? _priority;

  /// null = everywhere, 'personal', 'team:<id>' or 'project:<id>'.
  String? _source;

  /// Show team tasks I assigned to other people instead of my own.
  bool _assignedByMe = false;
  String _sort = 'Due date';
  bool _board = false;

  void _update(VoidCallback change) => setState(change);

  @override
  void initState() {
    super.initState();
    _priority = widget.initialPriority;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _hasFilter => _priority != null || _source != null || _assignedByMe;

  // ------------------------------------------------------------ saved views

  bool _matches(SavedView v) =>
      v.tab == _tab.name &&
      v.source == _source &&
      v.priority == _priority?.index &&
      v.byMe == _assignedByMe &&
      v.sort == _sort &&
      v.board == _board;

  void _applyView(SavedView v) => setState(() {
        _tab = _Tab.values.firstWhere((t) => t.name == v.tab, orElse: () => _Tab.all);
        _source = v.source;
        _priority = v.priority == null ? null : Priority.values[v.priority!.clamp(0, 2)];
        _assignedByMe = v.byMe;
        _sort = _sortOptions.contains(v.sort) ? v.sort : 'Due date';
        _board = v.board;
      });

  Future<void> _saveView() async {
    final name = await textInputDialog(context,
        title: 'Save this view', hint: 'e.g. Urgent this week', okLabel: 'Save');
    if (name == null || name.trim().isEmpty || !mounted) return;
    AppStore.instance.saveView(SavedView(
      id: newId(),
      name: name.trim(),
      tab: _tab.name,
      source: _source,
      priority: _priority?.index,
      byMe: _assignedByMe,
      sort: _sort,
      board: _board,
    ));
    showSnack(context, 'View "${name.trim()}" saved');
  }

  Future<void> _deleteView(SavedView v) async {
    final ok = await confirmDialog(context,
        title: 'Delete view "${v.name}"?',
        message: 'Your tasks stay; only the saved filter is removed.',
        confirmLabel: 'Delete',
        danger: true);
    if (ok) AppStore.instance.deleteView(v);
  }

  /// Saved filters as chips, and "Save view".
  Widget _viewsBar({EdgeInsets padding = EdgeInsets.zero}) {
    final views = AppStore.instance.savedViews;
    final active = views.where(_matches).map((v) => v.id).toSet();
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(
              child: Icon(Icons.bookmarks_outlined, size: 20, color: AppColors.textMuted),
            ),
          ),
          for (final v in views) ...[
            InputChip(
              label: Text(v.name),
              selected: active.contains(v.id),
              showCheckmark: false,
              selectedColor: AppColors.primaryLight,
              onPressed: () => _applyView(v),
              onDeleted: () => _deleteView(v),
              deleteIcon: const Icon(Icons.close_rounded, size: 16),
              deleteButtonTooltipMessage: 'Delete view',
            ),
            const SizedBox(width: 8),
          ],
          if (active.isEmpty)
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
              label: Text(views.isEmpty ? 'Save this view' : 'Save view',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
              onPressed: _saveView,
            ),
        ],
      ),
    );
  }

  /// Tasks after source, priority and search (all tabs).
  List<TaskRef> _base() {
    final q = _search.text.trim().toLowerCase();
    final all = _assignedByMe ? TaskRepository.assignedByMe() : TaskRepository.myTasks();
    return all.where((r) {
      final t = r.task;
      if (_priority != null && t.priority != _priority) return false;
      final src = _source;
      if (src != null) {
        if (src == 'personal' && r.isTeam) return false;
        if (src.startsWith('team:') && r.team?.id != src.substring(5)) return false;
        if (src.startsWith('project:') && (r.isTeam || t.projectId != src.substring(8))) {
          return false;
        }
      }
      if (q.isNotEmpty &&
          !t.title.toLowerCase().contains(q) &&
          !t.description.toLowerCase().contains(q) &&
          !r.sourceLabel.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
  }

  static bool _inTab(_Tab tab, TaskItem t, DateTime now) {
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    return switch (tab) {
      _Tab.all => true,
      _Tab.today => isSameDay(t.startAt, now),
      _Tab.upcoming => t.status == TaskStatus.pending && !t.startAt.isBefore(tomorrow),
      _Tab.overdue => t.isOverdue,
      _Tab.completed => t.isCompleted,
    };
  }

  List<TaskRef> _sorted(List<TaskRef> list) {
    // Unfinished first, then the chosen order.
    int rank(TaskItem t) => t.status == TaskStatus.pending ? 0 : 1;
    int order(TaskItem a, TaskItem b) => switch (_sort) {
          'Priority' => b.priority.index != a.priority.index
              ? b.priority.index.compareTo(a.priority.index)
              : a.startAt.compareTo(b.startAt),
          'Name' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          'Newest' => b.createdAt.compareTo(a.createdAt),
          _ => a.startAt.compareTo(b.startAt),
        };
    return list
      ..sort((x, y) {
        final r = rank(x.task).compareTo(rank(y.task));
        return r != 0 ? r : order(x.task, y.task);
      });
  }

  /// Everything the page shows, worked out once per build.
  _TasksData _data() {
    final now = DateTime.now();
    final base = _base();
    return _TasksData(
      now: now,
      base: base,
      counts: {for (final t in _Tab.values) t: base.where((r) => _inTab(t, r.task, now)).length},
      list: _sorted(base.where((r) => _inTab(_tab, r.task, now)).toList()),
    );
  }

  // ---------------------------------------------------------------- filter

  Future<void> _openFilter() async {
    var p = _priority;
    var src = _source;
    var byMe = _assignedByMe;
    final teams = TeamStore.instance.teams;
    final projects = AppStore.instance.projects.where((p) => p.deletedAt == null).toList();

    Widget content(StateSetter setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Show', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              ChoiceChip(
                label: const Text('My tasks'),
                selected: !byMe,
                onSelected: (_) => setLocal(() => byMe = false),
              ),
              ChoiceChip(
                label: const Text('Assigned by me'),
                selected: byMe,
                onSelected: (_) => setLocal(() => byMe = true),
              ),
            ]),
            const SizedBox(height: 16),
            const Text('Team / Project', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              ChoiceChip(
                  label: const Text('All'),
                  selected: src == null,
                  onSelected: (_) => setLocal(() => src = null)),
              ChoiceChip(
                  label: const Text('Personal'),
                  selected: src == 'personal',
                  onSelected: (_) => setLocal(() => src = 'personal')),
              for (final t in teams)
                ChoiceChip(
                    avatar: Icon(Icons.groups_rounded, size: 16, color: Color(t.color)),
                    label: Text(t.name),
                    selected: src == 'team:${t.id}',
                    onSelected: (_) => setLocal(() => src = 'team:${t.id}')),
              for (final pr in projects)
                ChoiceChip(
                    avatar: Icon(Icons.folder_rounded, size: 16, color: Color(pr.color)),
                    label: Text(pr.name),
                    selected: src == 'project:${pr.id}',
                    onSelected: (_) => setLocal(() => src = 'project:${pr.id}')),
            ]),
            const SizedBox(height: 16),
            const Text('Priority', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              ChoiceChip(
                  label: const Text('Any'),
                  selected: p == null,
                  onSelected: (_) => setLocal(() => p = null)),
              for (final pr in Priority.values.reversed)
                ChoiceChip(
                    label: Text(pr.label),
                    selected: p == pr,
                    onSelected: (_) => setLocal(() => p = pr)),
            ]),
          ],
        );

    final bool? applied;
    if (isWideScreen(context)) {
      applied = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Filter tasks'),
            content: SizedBox(width: 420, child: SingleChildScrollView(child: content(setLocal))),
            actions: [
              TextButton(
                onPressed: () => setLocal(() {
                  p = null;
                  src = null;
                  byMe = false;
                }),
                child: const Text('Clear'),
              ),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
            ],
          ),
        ),
      );
    } else {
      applied = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.white,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Filter tasks',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  content(setLocal),
                  const SizedBox(height: 22),
                  PrimaryButton(label: 'Apply', onPressed: () => Navigator.pop(ctx, true)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (applied == true) {
      setState(() {
        _priority = p;
        _source = src;
        _assignedByMe = byMe;
      });
    }
  }

  /// Board: moves go to the right store.
  Widget _boardFor(List<TaskRef> list, {EdgeInsetsGeometry? padding}) {
    final byId = {for (final r in list) r.task.id: r};
    return KanbanBoard(
      tasks: [for (final r in list) r.task],
      padding: padding ?? const EdgeInsets.fromLTRB(12, 12, 12, 90),
      canMove: (t) => byId[t.id]?.canComplete ?? false,
      onMove: (t, column) {
        final r = byId[t.id];
        final team = r?.team;
        if (r == null) return;
        if (team == null) {
          AppStore.instance.moveTo(t, column);
        } else {
          TeamStore.instance.moveTo(team, t, column);
        }
      },
      onOpen: (context, t) {
        final r = byId[t.id];
        if (r != null) openTaskRef(context, r);
      },
      trailing: (t) {
        final r = byId[t.id];
        return r == null ? const SizedBox.shrink() : SourceChip(ref: r, small: true);
      },
    );
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppStore.instance, TeamStore.instance]),
      builder: (context, _) {
        final data = _data();
        if (!widget.standalone && isWideScreen(context)) return _buildWide(context, data);
        final body = _buildPhone(context, data);
        return widget.standalone ? Scaffold(body: SafeArea(child: body)) : SafeArea(child: body);
      },
    );
  }

  String get _title =>
      widget.standalone && widget.initialPriority == Priority.high ? 'High Priority' : 'My Tasks';

  Widget _buildPhone(BuildContext context, _TasksData data) {
    final list = data.list;
    final s = _TaskStats(data.base.map((r) => r.task));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ------------------------------------------------------- header
        Padding(
          padding: EdgeInsets.fromLTRB(widget.standalone ? 4 : 16, 10, 8, 0),
          child: Row(
            children: [
              if (widget.standalone)
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              Expanded(
                child: _searching
                    ? TextField(
                        controller: _search,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        decoration: fieldDecoration('Search tasks...', icon: Icons.search_rounded),
                      )
                    : Text(_title,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: 'Search',
                icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _search.clear();
                }),
              ),
              PopupMenuButton<String>(
                tooltip: 'Sort',
                icon: const Icon(Icons.swap_vert_rounded),
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (_) => [
                  for (final o in _sortOptions)
                    CheckedPopupMenuItem(value: o, checked: o == _sort, child: Text(o)),
                ],
              ),
              IconButton(
                tooltip: 'Filter',
                icon: Badge(
                    isLabelVisible: _hasFilter,
                    smallSize: 8,
                    child: const Icon(Icons.tune_rounded)),
                onPressed: _openFilter,
              ),
              IconButton(
                tooltip: _board ? 'List view' : 'Board view',
                icon: Icon(_board ? Icons.view_list_rounded : Icons.view_kanban_outlined),
                onPressed: () => setState(() => _board = !_board),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Text(
              _assignedByMe
                  ? 'Team tasks you assigned to other people.'
                  : 'Your personal tasks and tasks assigned to you.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ),
        const SizedBox(height: 12),
        // -------------------------------------------------------- stats
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final (i, (label, value, color)) in [
                ('Total', s.total, AppColors.primary),
                ('Pending', s.pending, const Color(0xFFEA7A0C)),
                ('Overdue', s.overdue, AppColors.danger),
                ('Done', s.done, AppColors.success),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text('$value',
                            style:
                                TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
                        Text(label,
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        _viewsBar(padding: const EdgeInsets.symmetric(horizontal: 16)),
        const SizedBox(height: 8),
        // --------------------------------------------------------- tabs
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final t in _Tab.values) ...[
                ChoiceChip(
                  label: Text('${_tabLabel(t)} (${data.counts[t]})'),
                  selected: _tab == t,
                  showCheckmark: false,
                  selectedColor: AppColors.primary,
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _tab == t
                          ? Colors.white
                          : (t == _Tab.overdue && (data.counts[t] ?? 0) > 0
                              ? AppColors.danger
                              : AppColors.text)),
                  side: BorderSide(color: _tab == t ? AppColors.primary : AppColors.border),
                  onSelected: (_) => setState(() => _tab = t),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _board
              ? _boardFor(list)
              : list.isEmpty
                  ? ListView(children: [_empty()])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: list.length,
                      itemBuilder: (context, i) => _PhoneTaskCard(ref: list[i], now: data.now),
                    ),
        ),
      ],
    );
  }

  Widget _empty() => EmptyState(
        icon: Icons.inbox_outlined,
        title: _search.text.isNotEmpty || _hasFilter ? 'No matching tasks' : 'No tasks here',
        subtitle: _search.text.isNotEmpty || _hasFilter
            ? 'Try a different search or filter.'
            : 'Use New Task to add one.',
      );
}

class _TasksData {
  final DateTime now;
  final List<TaskRef> base;
  final Map<_Tab, int> counts;
  final List<TaskRef> list;
  const _TasksData(
      {required this.now, required this.base, required this.counts, required this.list});
}

/// Total / pending / overdue / done / in progress.
class _TaskStats {
  int total = 0, pending = 0, overdue = 0, done = 0, inProgress = 0;

  _TaskStats(Iterable<TaskItem> tasks) {
    for (final t in tasks) {
      total++;
      if (t.isCompleted) {
        done++;
      } else if (t.isOverdue) {
        overdue++;
      } else {
        pending++;
        if (t.displayStatus == DisplayStatus.inProgress) inProgress++;
      }
    }
  }

  int pct(int n) => total == 0 ? 0 : (n * 100 / total).round();
}

class _PhoneTaskCard extends StatelessWidget {
  final TaskRef ref;
  final DateTime now;
  const _PhoneTaskCard({required this.ref, required this.now});

  @override
  Widget build(BuildContext context) {
    final t = ref.task;
    final done = t.isCompleted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WhiteCard(
        onTap: () => openTaskRef(context, ref),
        padding: const EdgeInsets.fromLTRB(6, 10, 0, 10),
        child: Row(
          children: [
            TickBox(value: done, onChanged: ref.canComplete ? (v) => ref.setCompleted(v) : null),
            const SizedBox(width: 6),
            IconBox(icon: taskIconFor(ref), color: Color(ref.sourceColor), size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: done ? AppColors.textMuted : AppColors.text,
                        decoration: done ? TextDecoration.lineThrough : null,
                      )),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Flexible(
                        child: Text(dueLabel(t, now),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color:
                                    dueIsUrgent(t, now) ? AppColors.danger : AppColors.textMuted)),
                      ),
                      if (t.priority == Priority.high && !done) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.local_fire_department_rounded,
                            size: 14, color: AppColors.danger),
                      ],
                      const SizedBox(width: 8),
                      Flexible(child: SourceChip(ref: ref, small: true)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            StatusChip(task: t),
            TaskActionsMenu(ref: ref),
          ],
        ),
      ),
    );
  }
}
