import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../widgets/common.dart';
import 'task_detail_screen.dart';
import 'task_form_screen.dart';

/// Dialog to create or edit a project (name + color).
Future<void> showProjectDialog(BuildContext context, {Project? project}) async {
  final store = AppStore.instance;
  final name = TextEditingController(text: project?.name ?? '');
  int color = project?.color ??
      kPaletteColors[store.projects.length % kPaletteColors.length];

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(project == null ? 'New project' : 'Edit project'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: fieldDecoration('Project name'),
            ),
            const SizedBox(height: 16),
            const Text('Color', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ColorPickerRow(selected: color, onChanged: (c) => setLocal(() => color = c)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final n = name.text.trim();
              if (n.isEmpty) return;
              if (project == null) {
                await store.addProject(n, color);
              } else {
                project.name = n;
                project.color = color;
                await store.updateProject(project);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  bool _searching = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: fieldDecoration('Search projects...'),
              )
            : const Text('Projects'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _search.clear();
            }),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton.filled(
              icon: const Icon(Icons.add_rounded),
              onPressed: () => showProjectDialog(context),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final q = _search.text.trim().toLowerCase();
          final list = store.projects
              .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
              .toList();
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.folder_open_rounded,
              title: 'No projects',
              subtitle: 'Tap + to create a project and group your tasks.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final p = list[i];
              final tasks = store.tasksOfProject(p.id);
              final done = tasks.where((t) => t.isCompleted).length;
              final progress = store.projectProgress(p.id);
              final color = Color(p.color);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: WhiteCard(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ProjectDetailScreen(projectId: p.id)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: color.withAlpha(30),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.folder_rounded, color: color),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 3),
                            Text('${tasks.length} tasks • $done done',
                                style: const TextStyle(
                                    fontSize: 12.5, color: AppColors.textMuted)),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 6,
                                      color: color,
                                      backgroundColor: color.withAlpha(30),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text('${(progress * 100).round()}%',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textMuted)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ProjectDetailScreen extends StatelessWidget {
  final String projectId;
  const ProjectDetailScreen({super.key, required this.projectId});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.projectById(projectId);
        if (p == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
                icon: Icons.folder_off_outlined,
                title: 'Project not found',
                subtitle: 'It may have been deleted.'),
          );
        }
        final tasks = store.tasksOfProject(p.id)
          ..sort((a, b) => a.startAt.compareTo(b.startAt));
        final done = tasks.where((t) => t.isCompleted).length;
        final progress = store.projectProgress(p.id);
        final color = Color(p.color);

        return Scaffold(
          appBar: AppBar(
            title: Text(p.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (a) async {
                  if (a == 'edit') {
                    await showProjectDialog(context, project: p);
                  } else if (a == 'delete') {
                    final ok = await confirmDialog(context,
                        title: 'Delete project?',
                        message:
                            'The project will be deleted. Its tasks will stay, without a project.',
                        confirmLabel: 'Delete',
                        danger: true);
                    if (ok) {
                      await store.deleteProject(p);
                      if (context.mounted) Navigator.pop(context);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit project')),
                  PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete project',
                          style: TextStyle(color: AppColors.danger))),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => TaskFormScreen(
                      initialDate: DateTime.now(), initialProjectId: p.id)),
            ),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add task'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              WhiteCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('${(progress * 100).round()}%',
                            style: TextStyle(
                                fontSize: 28, fontWeight: FontWeight.w800, color: color)),
                        const SizedBox(width: 10),
                        const Text('complete',
                            style: TextStyle(color: AppColors.textMuted)),
                        const Spacer(),
                        Text('$done / ${tasks.length} tasks',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        color: color,
                        backgroundColor: color.withAlpha(30),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const SectionHeader(title: 'Tasks'),
              const SizedBox(height: 12),
              if (tasks.isEmpty)
                const EmptyState(
                  icon: Icons.playlist_add_rounded,
                  title: 'No tasks in this project',
                  subtitle: 'Tap "Add task" to create one.',
                )
              else
                ...tasks.map((t) =>
                    TaskTile(task: t, onTap: () => openTaskDetail(context, t))),
            ],
          ),
        );
      },
    );
  }
}
