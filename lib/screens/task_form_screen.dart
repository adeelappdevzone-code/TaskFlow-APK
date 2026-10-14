import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../widgets/common.dart';

/// Add Task / Edit Task form.
class TaskFormScreen extends StatefulWidget {
  final TaskItem? task; // null = new task
  final DateTime? initialDate;
  final String? initialProjectId;

  const TaskFormScreen({super.key, this.task, this.initialDate, this.initialProjectId});

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _newItem = TextEditingController();

  String? _categoryId;
  String? _projectId;
  String? _assigneeId;
  Priority _priority = Priority.medium;
  late DateTime _date;
  late TimeOfDay _start;
  late TimeOfDay _end;
  List<ChecklistItem> _checklist = [];
  String? _originalAssigneeId;
  bool _saving = false;

  bool get _isNew => widget.task == null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    final store = AppStore.instance;
    if (t != null) {
      _title.text = t.title;
      _desc.text = t.description;
      _categoryId = t.categoryId;
      _projectId = t.projectId;
      _assigneeId = t.assigneeId;
      _originalAssigneeId = t.assigneeId;
      _priority = t.priority;
      _date = dateOnly(t.startAt);
      _start = TimeOfDay.fromDateTime(t.startAt);
      final end = t.endAt ?? t.startAt.add(const Duration(hours: 1));
      _end = TimeOfDay.fromDateTime(end);
      // Copy so cancelling the form doesn't change the original.
      _checklist = t.checklist
          .map((c) => ChecklistItem(
                id: c.id,
                taskId: c.taskId,
                title: c.title,
                isDone: c.isDone,
                sortOrder: c.sortOrder,
                createdAt: c.createdAt,
                updatedAt: c.updatedAt,
              ))
          .toList();
    } else {
      final now = DateTime.now();
      final base = widget.initialDate ?? now;
      _date = dateOnly(base);
      // Next full hour (for today) or 09:00 (for another day).
      if (isSameDay(base, now)) {
        final h = (now.hour + 1).clamp(0, 22).toInt();
        _start = TimeOfDay(hour: h, minute: 0);
      } else {
        _start = const TimeOfDay(hour: 9, minute: 0);
      }
      _end = TimeOfDay(hour: (_start.hour + 1) % 24, minute: _start.minute);
      _projectId = widget.initialProjectId;
      if (store.categories.isNotEmpty) _categoryId = store.categories.first.id;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _newItem.dispose();
    super.dispose();
  }

  DateTime _combine(TimeOfDay t) =>
      DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  Future<void> _pickTime(bool start) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        final duration = _combine(_end).difference(_combine(_start));
        _start = picked;
        final newEnd = _combine(_start).add(
            duration.isNegative || duration == Duration.zero
                ? const Duration(hours: 1)
                : duration);
        _end = isSameDay(newEnd, _date)
            ? TimeOfDay.fromDateTime(newEnd)
            : const TimeOfDay(hour: 23, minute: 59);
      } else {
        _end = picked;
      }
    });
  }

  void _addChecklistItem() {
    final text = _newItem.text.trim();
    if (text.isEmpty) return;
    final now = DateTime.now();
    setState(() {
      _checklist.add(ChecklistItem(
        id: newId(),
        taskId: widget.task?.id ?? '',
        title: text,
        isDone: false,
        sortOrder: _checklist.length,
        createdAt: now,
        updatedAt: now,
      ));
      _newItem.clear();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final startAt = _combine(_start);
    final endAt = _combine(_end);
    if (!endAt.isAfter(startAt)) {
      showSnack(context, 'End time must be after start time.');
      return;
    }
    _addChecklistItem(); // include any text still typed in the box
    setState(() => _saving = true);

    final now = DateTime.now();
    final store = AppStore.instance;
    final TaskItem task;
    if (_isNew) {
      task = TaskItem(
        id: newId(),
        title: _title.text.trim(),
        createdAt: now,
        updatedAt: now,
        startAt: startAt,
      );
    } else {
      task = widget.task!;
    }
    task
      ..title = _title.text.trim()
      ..description = _desc.text.trim()
      ..categoryId = _categoryId
      ..projectId = _projectId
      ..assigneeId = _assigneeId
      ..priority = _priority
      ..startAt = startAt
      ..endAt = endAt;

    final items = _checklist
        .map((c) => ChecklistItem(
              id: c.id,
              taskId: task.id,
              title: c.title,
              isDone: c.isDone,
              sortOrder: c.sortOrder,
              createdAt: c.createdAt,
              updatedAt: now,
            ))
        .toList();

    final messenger = ScaffoldMessenger.of(context);
    final wasNew = _isNew;
    await store.saveTask(task, items,
        isNew: wasNew, previousAssigneeId: _originalAssigneeId);
    if (!mounted) return;
    Navigator.pop(context, true);
    messenger.showSnackBar(SnackBar(
      content: Text(wasNew ? 'Task added' : 'Task updated'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ------------------------------------------------------------ pickers

  Future<void> _pickCategory() async {
    final store = AppStore.instance;
    final result = await _showOptions<String>(
      title: 'Category',
      options: [
        for (final c in store.categories)
          _Option(c.id, c.name, color: Color(c.color), icon: Icons.label_rounded),
      ],
      selected: _categoryId,
      addLabel: 'New category',
    );
    if (result == null) return;
    if (result == _addKey) {
      final name = await textInputDialog(context, title: 'New category', hint: 'Category name');
      if (name == null) return;
      final colors = kPaletteColors;
      final c = await store.addCategory(name, colors[store.categories.length % colors.length]);
      setState(() => _categoryId = c.id);
    } else {
      setState(() => _categoryId = result == _noneKey ? null : result);
    }
  }

  Future<void> _pickProject() async {
    final store = AppStore.instance;
    final result = await _showOptions<String>(
      title: 'Project',
      options: [
        const _Option(_noneKey, 'No project', icon: Icons.block_rounded),
        for (final p in store.projects)
          _Option(p.id, p.name, color: Color(p.color), icon: Icons.folder_rounded),
      ],
      selected: _projectId ?? _noneKey,
      addLabel: 'New project',
    );
    if (result == null) return;
    if (result == _addKey) {
      final name = await textInputDialog(context, title: 'New project', hint: 'Project name');
      if (name == null) return;
      final p = await store.addProject(
          name, kPaletteColors[store.projects.length % kPaletteColors.length]);
      setState(() => _projectId = p.id);
    } else {
      setState(() => _projectId = result == _noneKey ? null : result);
    }
  }

  Future<void> _pickAssignee() async {
    final store = AppStore.instance;
    final result = await _showOptions<String>(
      title: 'Assign to',
      options: [
        const _Option(_noneKey, 'Nobody (me)', icon: Icons.person_off_outlined),
        for (final m in store.members)
          _Option(m.id, m.name, icon: Icons.person_rounded),
      ],
      selected: _assigneeId ?? _noneKey,
      addLabel: 'Add team member',
    );
    if (result == null) return;
    if (result == _addKey) {
      final name = await textInputDialog(context, title: 'Team member', hint: 'Member name');
      if (name == null) return;
      final m = await store.addMember(name);
      setState(() => _assigneeId = m.id);
    } else {
      setState(() => _assigneeId = result == _noneKey ? null : result);
    }
  }

  static const _addKey = '__add__';
  static const _noneKey = '__none__';

  Future<String?> _showOptions<T>({
    required String title,
    required List<_Option> options,
    required String? selected,
    required String addLabel,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              for (final o in options)
                ListTile(
                  leading: Icon(o.icon, color: o.color ?? AppColors.textMuted),
                  title: Text(o.label),
                  trailing: selected == o.value
                      ? const Icon(Icons.check_rounded, color: AppColors.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, o.value),
                ),
              ListTile(
                leading: const Icon(Icons.add_rounded, color: AppColors.primary),
                title: Text(addLabel,
                    style: const TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, _addKey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final cat = store.categoryById(_categoryId);
    final project = store.projectById(_projectId);
    final member = store.memberById(_assigneeId);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_isNew ? 'Add Task' : 'Edit Task',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            const _Label('Task title', required: true),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: fieldDecoration('Enter task title'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 18),
            const _Label('Description'),
            TextFormField(
              controller: _desc,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: fieldDecoration('Add a description (optional)'),
            ),
            const SizedBox(height: 18),
            const _Label('Category'),
            _SelectField(
              icon: Icons.label_outline_rounded,
              iconColor: cat == null ? null : Color(cat.color),
              text: cat?.name ?? 'Select category',
              muted: cat == null,
              onTap: _pickCategory,
            ),
            const SizedBox(height: 18),
            const _Label('Priority'),
            Row(
              children: [
                _PriorityChip(
                  label: 'Low',
                  icon: Icons.trending_down_rounded,
                  color: AppColors.success,
                  selected: _priority == Priority.low,
                  onTap: () => setState(() => _priority = Priority.low),
                ),
                const SizedBox(width: 8),
                _PriorityChip(
                  label: 'Medium',
                  icon: Icons.drag_handle_rounded,
                  color: AppColors.primary,
                  selected: _priority == Priority.medium,
                  onTap: () => setState(() => _priority = Priority.medium),
                ),
                const SizedBox(width: 8),
                _PriorityChip(
                  label: 'High',
                  icon: Icons.local_fire_department_rounded,
                  color: AppColors.danger,
                  selected: _priority == Priority.high,
                  onTap: () => setState(() => _priority = Priority.high),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const _Label('Date & time'),
            _SelectField(
              icon: Icons.calendar_today_outlined,
              text: formatFullDate(_date),
              onTap: _pickDate,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _SelectField(
                    icon: Icons.schedule_rounded,
                    text: 'Start  ${_start.format(context)}',
                    onTap: () => _pickTime(true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SelectField(
                    icon: Icons.schedule_outlined,
                    text: 'End  ${_end.format(context)}',
                    onTap: () => _pickTime(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const _Label('Project'),
            _SelectField(
              icon: Icons.folder_outlined,
              iconColor: project == null ? null : Color(project.color),
              text: project?.name ?? 'No project (optional)',
              muted: project == null,
              onTap: _pickProject,
            ),
            const SizedBox(height: 18),
            const _Label('Assign to'),
            _SelectField(
              icon: Icons.person_outline_rounded,
              text: member?.name ?? 'Select member (optional)',
              muted: member == null,
              onTap: _pickAssignee,
            ),
            const SizedBox(height: 18),
            const _Label('Checklist'),
            for (var i = 0; i < _checklist.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: _checklist[i].isDone,
                      onChanged: (v) =>
                          setState(() => _checklist[i].isDone = v ?? false),
                    ),
                    Expanded(child: Text(_checklist[i].title)),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          size: 20, color: AppColors.textMuted),
                      onPressed: () => setState(() => _checklist.removeAt(i)),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newItem,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: fieldDecoration('Add checklist item',
                        icon: Icons.checklist_rounded),
                    onSubmitted: (_) => _addChecklistItem(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _addChecklistItem,
                  icon: const Icon(Icons.add_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primaryLight,
                    foregroundColor: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Save',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _Option {
  final String value;
  final String label;
  final Color? color;
  final IconData icon;
  const _Option(this.value, this.label, {this.color, required this.icon});
}

class _Label extends StatelessWidget {
  final String text;
  final bool required;
  const _Label(this.text, {this.required = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          text: text,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          children: [
            if (required)
              const TextSpan(text: ' *', style: TextStyle(color: AppColors.danger)),
          ],
        ),
      ),
    );
  }
}

class _SelectField extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String text;
  final bool muted;
  final VoidCallback onTap;
  const _SelectField({
    required this.icon,
    required this.text,
    required this.onTap,
    this.iconColor,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14, color: muted ? AppColors.textMuted : AppColors.text),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _PriorityChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? color.withAlpha(30) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : AppColors.border, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
