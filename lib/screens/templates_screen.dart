import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../data/template_library.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import 'task_ui.dart';

/// Icons a template can have.
const templateIcons = <String, IconData>{
  'task': Icons.task_alt_rounded,
  'web': Icons.web_rounded,
  'campaign': Icons.campaign_rounded,
  'social': Icons.photo_camera_outlined,
  'search': Icons.search_rounded,
  'people': Icons.groups_rounded,
  'brush': Icons.brush_rounded,
  'phone': Icons.phone_iphone_rounded,
  'rocket': Icons.rocket_launch_rounded,
  'event': Icons.event_rounded,
  'person': Icons.person_rounded,
  'chart': Icons.bar_chart_rounded,
};

IconData _iconOf(TaskTemplate t) => templateIcons[t.icon] ?? Icons.task_alt_rounded;

/// Built-in / Mine / the team's name.
String _sourceOf(TaskTemplate t) {
  if (t.builtIn) return 'Built-in';
  if (t.teamId != null) return TeamStore.instance.teamById(t.teamId!)?.name ?? 'Team';
  return 'Mine';
}

bool _canEdit(TaskTemplate t) {
  if (t.builtIn) return false;
  if (t.teamId == null) return true;
  final team = TeamStore.instance.teamById(t.teamId!);
  return team != null && TeamStore.instance.isAdmin(team);
}

void _delete(BuildContext context, TaskTemplate t) async {
  final ok = await confirmDialog(context,
      title: 'Delete "${t.name}"?',
      message: 'Tasks already made from it stay.',
      confirmLabel: 'Delete',
      danger: true);
  if (!ok) return;
  final team = t.teamId == null ? null : TeamStore.instance.teamById(t.teamId!);
  if (team != null) {
    TeamStore.instance.deleteTeamTemplate(team, t);
  } else {
    AppStore.instance.deleteTemplate(t);
  }
}

TaskTemplate _copyOf(TaskTemplate t, {String? name}) => TaskTemplate(
      id: newId(),
      name: name ?? t.name,
      title: t.title,
      description: t.description,
      priority: t.priority,
      checklist: [...t.checklist],
      createdAt: DateTime.now(),
      category: t.category,
      color: t.color,
      icon: t.icon,
      tasks: [
        for (final w in t.workflow)
          TemplateTask(
            title: w.title,
            offsetDays: w.offsetDays,
            priority: w.priority,
            estimateMinutes: w.estimateMinutes,
            checklist: [...w.checklist],
          ),
      ],
    );

// ------------------------------------------------------------- use template

/// Where and when to create the template's tasks.
Future<void> useTemplateDialog(BuildContext context, TaskTemplate t) async {
  final store = TeamStore.instance;
  final teams = store.teams.where(store.canCreateTask).toList();
  Team? team = t.teamId == null ? null : store.teamById(t.teamId!);
  var day = dateOnly(DateTime.now());
  String? assignee;
  var asProject = t.workflow.length > 1;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final admin = team != null && store.isAdmin(team!);
      return AlertDialog(
        title: Text('Use "${t.name}"'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    '${t.workflow.length} ${t.workflow.length == 1 ? 'task' : 'tasks'} over '
                    '${t.spanDays} ${t.spanDays == 1 ? 'day' : 'days'}.',
                    style: const TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: team?.id ?? '',
                  decoration: const InputDecoration(labelText: 'Create in'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('My Tasks (personal)')),
                    for (final x in teams) DropdownMenuItem(value: x.id, child: Text(x.name)),
                  ],
                  onChanged: (id) => setState(() {
                    team = id == null || id.isEmpty ? null : store.teamById(id);
                    assignee = null;
                  }),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Start date'),
                  subtitle: Text(DateFormat('EEE, d MMM yyyy').format(day)),
                  onTap: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                        context: ctx,
                        initialDate: day,
                        firstDate: DateTime(now.year - 1),
                        lastDate: DateTime(now.year + 3));
                    if (d != null) setState(() => day = d);
                  },
                ),
                if (team != null && admin)
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: assignee ?? '',
                    decoration: const InputDecoration(labelText: 'Assign all tasks to'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Nobody yet')),
                      for (final uid in team!.sortedMemberIds)
                        DropdownMenuItem(value: uid, child: Text(team!.nameOf(uid))),
                    ],
                    onChanged: (v) => setState(() => assignee = v == null || v.isEmpty ? null : v),
                  )
                else if (team != null)
                  const Text('The tasks will be assigned to you.',
                      style: TextStyle(color: AppColors.textMuted)),
                if (team == null && t.workflow.length > 1)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: asProject,
                    onChanged: (v) => setState(() => asProject = v ?? false),
                    title: const Text('Group them in a new project'),
                    subtitle: Text('"${t.name}"'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Create tasks')),
        ],
      );
    }),
  );
  if (ok != true) return;
  String? projectId;
  if (team == null && asProject) {
    final p = await AppStore.instance.addProject(t.name, t.color);
    projectId = p.id;
  }
  final n =
      await useTemplate(t, start: day, team: team, assigneeId: assignee, projectId: projectId);
  if (context.mounted) {
    showSnack(context,
        '$n ${n == 1 ? 'task' : 'tasks'} created${team == null ? '' : ' in ${team!.name}'}');
  }
}

void _preview(BuildContext context, TaskTemplate t) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Row(children: [
              IconBox(icon: _iconOf(t), color: Color(t.color), size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(t.description, style: const TextStyle(color: AppColors.textMuted)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            for (final w in t.workflow)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(t.color).withAlpha(28),
                  child: Text('D${w.offsetDays + 1}',
                      style: TextStyle(
                          fontSize: 11.5, color: Color(t.color), fontWeight: FontWeight.w700)),
                ),
                title: Text(w.title),
                subtitle: Text([
                  w.priority.label,
                  if (w.estimateMinutes != null) formatMinutes(w.estimateMinutes!),
                  if (w.checklist.isNotEmpty) '${w.checklist.length} checklist items',
                ].join(' • ')),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                useTemplateDialog(context, t);
              },
              child: const Text('Use template'),
            ),
          ],
        ),
      ),
    ),
  );
}

// --------------------------------------------------------------- library

class TemplatesScreen extends StatefulWidget {
  final bool page;
  const TemplatesScreen({super.key, this.page = false});

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  String _category = '';
  String _source = '';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppStore.instance, TeamStore.instance]),
      builder: (context, _) {
        final all = allTemplates();
        bool srcOk(TaskTemplate t) => switch (_source) {
              'builtin' => t.builtIn,
              'mine' => !t.builtIn && t.teamId == null,
              'team' => t.teamId != null,
              _ => true,
            };
        final q = _search.trim().toLowerCase();
        bool searchOk(TaskTemplate t) =>
            q.isEmpty ||
            t.name.toLowerCase().contains(q) ||
            t.description.toLowerCase().contains(q) ||
            t.workflow.any((w) => w.title.toLowerCase().contains(q));
        final base = all.where((t) => srcOk(t) && searchOk(t)).toList();
        final list = base.where((t) => _category.isEmpty || t.category == _category).toList();

        return LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final cols = box.maxWidth >= 1250 ? 3 : (box.maxWidth >= 760 ? 2 : 1);
          final searchField = SizedBox(
            width: wide ? 280 : double.infinity,
            height: 46,
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search templates...',
                isDense: true,
              ),
            ),
          );
          final createBtn = FilledButton.icon(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const TemplateEditScreen())),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create Template'),
          );
          final tabs = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in ['', ...kTemplateCategories])
                ChoiceChip(
                  label: Text(
                      '${c.isEmpty ? 'All Templates' : c}  (${base.where((t) => c.isEmpty || t.category == c).length})'),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          );
          final sourceMenu = PopupMenuButton<String>(
            tooltip: 'Show',
            position: PopupMenuPosition.under,
            onSelected: (v) => setState(() => _source = v),
            itemBuilder: (_) => [
              for (final (v, l) in [
                ('', 'All sources'),
                ('builtin', 'Built-in'),
                ('mine', 'My templates'),
                ('team', 'Team templates'),
              ])
                CheckedPopupMenuItem(value: v, checked: _source == v, child: Text(l)),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _source.isEmpty ? AppColors.border : AppColors.primary),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.filter_alt_outlined, size: 18),
                const SizedBox(width: 6),
                Text(
                    switch (_source) {
                      'builtin' => 'Built-in',
                      'mine' => 'Mine',
                      'team' => 'Team',
                      _ => 'All sources',
                    },
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
          );

          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: widget.page
                ? AppBar(backgroundColor: AppColors.background, title: const Text('Templates'))
                : null,
            body: ListView(
              padding: EdgeInsets.fromLTRB(wide ? 28 : 16, wide ? 22 : 8, wide ? 28 : 16, 28),
              children: [
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: IconBox(icon: Icons.description_rounded, color: AppColors.purple),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: PageHeader(
                          title: 'Templates Library',
                          subtitle: 'Ready-made workflows to create projects and tasks quickly.',
                        ),
                      ),
                      searchField,
                      const SizedBox(width: 12),
                      createBtn,
                    ],
                  )
                else ...[
                  searchField,
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerLeft, child: createBtn),
                ],
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: tabs), const SizedBox(width: 10), sourceMenu],
                ),
                const SizedBox(height: 16),
                if (list.isEmpty)
                  const DashCard(
                    child: EmptyState(
                      icon: Icons.description_outlined,
                      title: 'No templates here',
                      subtitle: 'Create one, or save a task as a template from the task form.',
                    ),
                  )
                else
                  LayoutBuilder(builder: (context, inner) {
                    final w = (inner.maxWidth - 16 * (cols - 1)) / cols;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final t in list) SizedBox(width: w, child: _TemplateCard(t: t)),
                      ],
                    );
                  }),
              ],
            ),
          );
        });
      },
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final TaskTemplate t;
  const _TemplateCard({required this.t});

  @override
  Widget build(BuildContext context) {
    final color = Color(t.color);
    final n = t.workflow.length;
    Widget tag(String s) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration:
              BoxDecoration(color: const Color(0xFFF1F3F6), borderRadius: BorderRadius.circular(8)),
          child: Text(s, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
        );
    Widget meta(IconData icon, String s) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 5),
          Text(s, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
        ]);
    return DashCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _preview(context, t),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBox(icon: _iconOf(t), color: color, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      SizedBox(
                        height: 38,
                        child: Text(t.description.isEmpty ? t.title : t.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF4B5563), height: 1.35)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [tag(t.category), tag(_sourceOf(t))]),
          const SizedBox(height: 12),
          Wrap(spacing: 16, runSpacing: 6, children: [
            meta(Icons.description_outlined, '$n ${n == 1 ? 'task' : 'tasks'}'),
            meta(Icons.date_range_rounded, '${t.spanDays} ${t.spanDays == 1 ? 'day' : 'days'}'),
            if (t.workflow.any((w) => w.checklist.isNotEmpty))
              meta(Icons.checklist_rounded,
                  '${t.workflow.fold(0, (a, w) => a + w.checklist.length)} checklist items'),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: () => useTemplateDialog(context, t),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryLight,
                  foregroundColor: AppColors.primary,
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Use Template', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (a) {
                switch (a) {
                  case 'preview':
                    _preview(context, t);
                  case 'copy':
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                TemplateEditScreen(template: _copyOf(t), isCopy: true)));
                  case 'edit':
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => TemplateEditScreen(template: t)));
                  case 'delete':
                    _delete(context, t);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'preview', child: Text('Preview tasks')),
                const PopupMenuItem(value: 'copy', child: Text('Make a copy to edit')),
                if (_canEdit(t)) ...[
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete', style: TextStyle(color: AppColors.danger))),
                ],
              ],
            ),
          ]),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ edit / create

class TemplateEditScreen extends StatefulWidget {
  final TaskTemplate? template;

  /// A copy of another template (saved as a new one).
  final bool isCopy;
  const TemplateEditScreen({super.key, this.template, this.isCopy = false});

  @override
  State<TemplateEditScreen> createState() => _TemplateEditScreenState();
}

class _TaskDraft {
  final TextEditingController title;
  final TextEditingController checklist;
  int offset;
  Priority priority;
  int? estimate;
  _TaskDraft(TemplateTask t)
      : title = TextEditingController(text: t.title),
        checklist = TextEditingController(text: t.checklist.join('\n')),
        offset = t.offsetDays,
        priority = t.priority,
        estimate = t.estimateMinutes;
}

class _TemplateEditScreenState extends State<TemplateEditScreen> {
  late final TaskTemplate? _old = widget.isCopy ? null : widget.template;
  late final _name = TextEditingController(text: widget.template?.name ?? '');
  late final _desc = TextEditingController(text: widget.template?.description ?? '');
  late String _category = widget.template?.category ?? 'Personal';
  late int _color = widget.template?.color ?? 0xFF1F6FEB;
  late String _icon = widget.template?.icon ?? 'task';

  /// '' = my templates, else a team id (owner/manager only).
  late String _saveTo = widget.isCopy ? '' : (widget.template?.teamId ?? '');
  late final List<_TaskDraft> _tasks = [
    for (final w in widget.template?.workflow ?? [TemplateTask(title: '')]) _TaskDraft(w)
  ];
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    for (final t in _tasks) {
      t.title.dispose();
      t.checklist.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final tasks = [
      for (final d in _tasks)
        if (d.title.text.trim().isNotEmpty)
          TemplateTask(
            title: d.title.text.trim(),
            offsetDays: d.offset,
            priority: d.priority,
            estimateMinutes: d.estimate,
            checklist: [
              for (final l in d.checklist.text.split('\n'))
                if (l.trim().isNotEmpty) l.trim()
            ],
          ),
    ];
    if (name.isEmpty || tasks.isEmpty) {
      setState(
          () => _error = name.isEmpty ? 'Give the template a name.' : 'Add at least one task.');
      return;
    }
    final t = TaskTemplate(
      id: _old?.id ?? newId(),
      name: name,
      title: tasks.first.title,
      description: _desc.text.trim(),
      priority: tasks.first.priority,
      checklist: tasks.first.checklist,
      createdAt: _old?.createdAt ?? DateTime.now(),
      category: _category,
      color: _color,
      icon: _icon,
      tasks: tasks,
      createdBy: _old?.createdBy ?? TeamStore.instance.uid,
    );
    final team = _saveTo.isEmpty ? null : TeamStore.instance.teamById(_saveTo);
    if (team != null) {
      TeamStore.instance.saveTeamTemplate(team, t);
    } else {
      AppStore.instance.saveTemplate(t);
    }
    showSnack(context, 'Template "$name" saved');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    final adminTeams = store.teams.where(store.isAdmin).toList();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(_old == null ? 'New template' : 'Edit template'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 8, wide ? 24 : 16, 32),
            children: [
              DashCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Template name')),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _desc,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Description'),
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _category,
                          decoration: const InputDecoration(labelText: 'Category'),
                          items: [
                            for (final c in kTemplateCategories)
                              DropdownMenuItem(value: c, child: Text(c)),
                          ],
                          onChanged: (v) => setState(() => _category = v ?? _category),
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _saveTo,
                          decoration: const InputDecoration(labelText: 'Save to'),
                          items: [
                            const DropdownMenuItem(value: '', child: Text('My templates')),
                            for (final t in adminTeams)
                              DropdownMenuItem(value: t.id, child: Text('Team: ${t.name}')),
                          ],
                          onChanged: _old != null ? null : (v) => setState(() => _saveTo = v ?? ''),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    const Text('Icon', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final e in templateIcons.entries)
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _icon = e.key),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _icon == e.key
                                  ? Color(_color).withAlpha(40)
                                  : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: _icon == e.key ? Color(_color) : Colors.transparent,
                                  width: 2),
                            ),
                            child: Icon(e.value, color: Color(_color)),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    const Text('Color', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    ColorPickerRow(selected: _color, onChanged: (c) => setState(() => _color = c)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: Text('Tasks (${_tasks.length})',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                TextButton.icon(
                  onPressed: _tasks.length >= 60
                      ? null
                      : () => setState(() => _tasks.add(_TaskDraft(TemplateTask(
                          title: '', offsetDays: _tasks.isEmpty ? 0 : _tasks.last.offset)))),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add task'),
                ),
              ]),
              const Text('"Day" is when the task is due, counted from the start date.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              const SizedBox(height: 10),
              for (final (i, d) in _tasks.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DashCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: Color(_color),
                            child: Text('${i + 1}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: d.title,
                              decoration:
                                  const InputDecoration(isDense: true, hintText: 'Task title'),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: _tasks.length == 1
                                ? null
                                : () => setState(() => _tasks.removeAt(i)),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        Wrap(spacing: 10, runSpacing: 10, children: [
                          _Stepper(
                            label: 'Day ${d.offset + 1}',
                            onMinus: d.offset == 0 ? null : () => setState(() => d.offset--),
                            onPlus: d.offset >= 365 ? null : () => setState(() => d.offset++),
                          ),
                          DropdownButton<Priority>(
                            value: d.priority,
                            underline: const SizedBox.shrink(),
                            items: [
                              for (final p in Priority.values.reversed)
                                DropdownMenuItem(value: p, child: Text('${p.label} priority')),
                            ],
                            onChanged: (p) => setState(() => d.priority = p ?? d.priority),
                          ),
                          DropdownButton<int>(
                            value: d.estimate ?? 0,
                            underline: const SizedBox.shrink(),
                            items: [
                              for (final m in {
                                ...kEstimateChoices,
                                if (d.estimate != null) d.estimate!
                              })
                                DropdownMenuItem(
                                    value: m,
                                    child: Text(m == 0 ? 'No estimate' : formatMinutes(m))),
                            ],
                            onChanged: (m) =>
                                setState(() => d.estimate = m == null || m == 0 ? null : m),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        TextField(
                          controller: d.checklist,
                          minLines: 1,
                          maxLines: 5,
                          decoration: const InputDecoration(
                              isDense: true, hintText: 'Checklist (one item per line, optional)'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                child: const Text('Save template'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final String label;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  const _Stepper({required this.label, required this.onMinus, required this.onPlus});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onMinus,
              icon: const Icon(Icons.remove_rounded, size: 18)),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onPlus,
              icon: const Icon(Icons.add_rounded, size: 18)),
        ]),
      );
}
