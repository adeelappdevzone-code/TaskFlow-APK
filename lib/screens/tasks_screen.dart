import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../core/utils.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import '../widgets/responsive.dart';
import '../widgets/task_board.dart';
import 'task_detail_screen.dart';
import 'task_form_screen.dart';

part 'tasks_wide.dart';

enum _Tab { all, pending, done, overdue }

const _sortOptions = ['Due time', 'Priority', 'Name', 'Newest'];

class TasksScreen extends StatefulWidget {
  /// true when opened as its own page (e.g. "High Priority" from Home),
  /// false when shown as a bottom-nav tab.
  final bool standalone;
  final Priority? initialPriority;

  const TasksScreen({super.key, this.standalone = false, this.initialPriority});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  _Tab _tab = _Tab.all;
  bool _searching = false;
  final _search = TextEditingController();
  Priority? _priority;
  String? _categoryId;
  String _sort = 'Due time';

  // Laptop layout (tasks_wide.dart).
  bool _wideBoard = false;

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

  List<TaskItem> _filtered(AppStore store) {
    final q = _search.text.trim().toLowerCase();
    final list = store.tasks.where((t) {
      switch (_tab) {
        case _Tab.pending:
          if (t.status != TaskStatus.pending) return false;
          break;
        case _Tab.done:
          if (!t.isCompleted) return false;
          break;
        case _Tab.overdue:
          if (!t.isOverdue) return false;
          break;
        case _Tab.all:
          break;
      }
      if (_priority != null && t.priority != _priority) return false;
      if (_categoryId != null && t.categoryId != _categoryId) return false;
      if (q.isNotEmpty &&
          !t.title.toLowerCase().contains(q) &&
          !t.description.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();

    // Unfinished first, then by the chosen order.
    int rank(TaskItem t) => t.status == TaskStatus.pending ? 0 : (t.isCompleted ? 1 : 2);
    int order(TaskItem a, TaskItem b) => switch (_sort) {
          'Priority' => b.priority.index != a.priority.index
              ? b.priority.index.compareTo(a.priority.index)
              : a.startAt.compareTo(b.startAt),
          'Name' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          'Newest' => b.createdAt.compareTo(a.createdAt),
          _ => a.startAt.compareTo(b.startAt),
        };
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return order(a, b);
    });
    return list;
  }

  bool get _hasFilter => _priority != null || _categoryId != null;

  Future<void> _openFilter() async {
    final store = AppStore.instance;
    Priority? p = _priority;
    String? c = _categoryId;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filter tasks',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 18),
                const Text('Priority', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Any'),
                      selected: p == null,
                      onSelected: (_) => setLocal(() => p = null),
                    ),
                    for (final pr in Priority.values)
                      ChoiceChip(
                        label: Text(pr.label),
                        selected: p == pr,
                        onSelected: (_) => setLocal(() => p = pr),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text('Category', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    ChoiceChip(
                      label: const Text('Any'),
                      selected: c == null,
                      onSelected: (_) => setLocal(() => c = null),
                    ),
                    for (final cat in store.categories)
                      ChoiceChip(
                        label: Text(cat.name),
                        selected: c == cat.id,
                        onSelected: (_) => setLocal(() => c = cat.id),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                PrimaryButton(label: 'Apply', onPressed: () => Navigator.pop(ctx, true)),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied == true) {
      setState(() {
        _priority = p;
        _categoryId = c;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    if (!widget.standalone && isWideScreen(context)) {
      return ListenableBuilder(listenable: store, builder: (context, _) => _buildWide(context));
    }
    final body = ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list = _filtered(store);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---------------------------------------------------- header
            Padding(
              padding: EdgeInsets.fromLTRB(widget.standalone ? 8 : 20, 12, 12, 0),
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
                            decoration:
                                fieldDecoration('Search tasks...', icon: Icons.search_rounded),
                          )
                        : Text(
                            widget.standalone && widget.initialPriority == Priority.high
                                ? 'High Priority'
                                : 'Tasks',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
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
                    icon: Badge(
                      isLabelVisible: _hasFilter,
                      smallSize: 8,
                      child: const Icon(Icons.tune_rounded),
                    ),
                    onPressed: _openFilter,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // ------------------------------------------------------ tabs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  TabPill(
                      label: 'All',
                      active: _tab == _Tab.all,
                      onTap: () => setState(() => _tab = _Tab.all)),
                  const SizedBox(width: 8),
                  TabPill(
                      label: 'Pending',
                      active: _tab == _Tab.pending,
                      onTap: () => setState(() => _tab = _Tab.pending)),
                  const SizedBox(width: 8),
                  TabPill(
                      label: 'Done',
                      active: _tab == _Tab.done,
                      onTap: () => setState(() => _tab = _Tab.done)),
                  const SizedBox(width: 8),
                  TabPill(
                      label: 'Overdue',
                      active: _tab == _Tab.overdue,
                      onTap: () => setState(() => _tab = _Tab.overdue)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: list.isEmpty
                  ? ListView(children: [
                      EmptyState(
                        icon: Icons.inbox_outlined,
                        title: _search.text.isNotEmpty || _hasFilter
                            ? 'No matching tasks'
                            : 'No tasks yet',
                        subtitle: _search.text.isNotEmpty || _hasFilter
                            ? 'Try a different search or filter.'
                            : 'Tap the + button to create your first task.',
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      itemCount: list.length,
                      itemBuilder: (context, i) => TaskTile(
                        task: list[i],
                        onTap: () => openTaskDetail(context, list[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );

    if (widget.standalone) {
      return Scaffold(body: SafeArea(child: body));
    }
    return SafeArea(child: body);
  }
}
