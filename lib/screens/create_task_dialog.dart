import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';
import 'task_form_screen.dart';

/// The one way to create a task, from everywhere (side menu, + button, a
/// team, a project, the calendar): a dialog on a laptop, a sheet on a phone.
/// [team] / [projectId] / [date] fill it in for where it was opened from.
Future<void> showCreateTask(BuildContext context,
    {Team? team, String? projectId, DateTime? date, TimeOfDay? time, String? stage}) async {
  final form =
      _CreateTaskForm(team: team, projectId: projectId, date: date, time: time, stage: stage);
  if (isWideScreen(context)) {
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x66111827),
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: form),
      ),
    );
  } else {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: form,
      ),
    );
  }
}

/// Google Calendar "add event" page for a task (opens the app or website).
Uri googleCalendarLink(TaskItem t) {
  final allDay = t.isAllDay;
  String stamp(DateTime d) => DateFormat("yyyyMMdd'T'HHmmss").format(d);
  final dates = allDay
      ? '${DateFormat('yyyyMMdd').format(t.startAt)}/'
          '${DateFormat('yyyyMMdd').format(t.startAt.add(const Duration(days: 1)))}'
      : '${stamp(t.startAt)}/${stamp(t.endAt ?? t.startAt.add(const Duration(hours: 1)))}';
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': t.title,
    'dates': dates,
    if (t.description.isNotEmpty) 'details': t.description,
  });
}

class _CreateTaskForm extends StatefulWidget {
  final Team? team;
  final String? projectId;
  final DateTime? date;
  final TimeOfDay? time;

  /// Board column to start in ([TaskStage]), when added from a team board.
  final String? stage;
  const _CreateTaskForm({this.team, this.projectId, this.date, this.time, this.stage});

  @override
  State<_CreateTaskForm> createState() => _CreateTaskFormState();
}

class _CreateTaskFormState extends State<_CreateTaskForm> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  late bool _isTeam = widget.team != null;
  late Team? _team = widget.team;
  late String? _projectId = widget.projectId;
  String? _assigneeId;
  String? _categoryId;
  late DateTime _date = dateOnly(widget.date ?? DateTime.now());
  late TimeOfDay? _time = widget.time;
  Priority _priority = Priority.medium;
  bool _addToCalendar = false;
  String? _titleError;
  String? _teamError;

  List<Team> get _teams => TeamStore.instance.teams;

  /// A plain member adds team tasks only for themselves.
  bool get _assignLocked => _team != null && !TeamStore.instance.isAdmin(_team!);

  @override
  void initState() {
    super.initState();
    if (_team != null && _assignLocked) _assigneeId = TeamStore.instance.uid;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _setTeamMode(bool team) {
    setState(() {
      _isTeam = team;
      _teamError = null;
      if (team) {
        _team ??= _teams.length == 1 ? _teams.first : null;
        _assigneeId = _assignLocked ? TeamStore.instance.uid : null;
      } else {
        _assigneeId = null;
      }
    });
  }

  void _setTeam(Team? team) {
    setState(() {
      _team = team;
      _teamError = null;
      _assigneeId = _assignLocked ? TeamStore.instance.uid : null;
    });
  }

  /// The task as filled in so far.
  TaskItem _build() {
    final now = DateTime.now();
    final t = _time;
    final start = t == null
        ? DateTime(_date.year, _date.month, _date.day)
        : DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);
    var end = t == null
        ? DateTime(_date.year, _date.month, _date.day, 23, 59)
        : start.add(const Duration(hours: 1));
    if (!isSameDay(end, start)) end = DateTime(start.year, start.month, start.day, 23, 59);
    return TaskItem(
      id: newId(),
      title: _title.text.trim(),
      description: _desc.text.trim(),
      categoryId: _isTeam ? null : _categoryId,
      projectId: _isTeam ? null : _projectId,
      assigneeId: _isTeam ? (_assignLocked ? TeamStore.instance.uid : _assigneeId) : null,
      priority: _priority,
      startAt: start,
      endAt: end,
      stage: TaskStage.all.contains(widget.stage) ? widget.stage! : TaskStage.todo,
      createdAt: now,
      updatedAt: now,
    );
  }

  bool _validate() {
    setState(() {
      _titleError = _title.text.trim().isEmpty ? 'Please enter a title' : null;
      _teamError = _isTeam && _team == null ? 'Choose a team' : null;
    });
    return _titleError == null && _teamError == null;
  }

  Future<void> _create() async {
    if (!_validate()) return;
    final task = _build();
    final team = _isTeam ? _team : null;
    if (team == null) {
      await AppStore.instance.saveTask(task, const [], isNew: true);
    } else {
      TeamStore.instance.saveTask(team, task, [], isNew: true);
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final calendar = _addToCalendar;
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text(team == null ? 'Task created' : 'Task created in ${team.name}'),
      behavior: SnackBarBehavior.floating,
    ));
    if (calendar) {
      launchUrl(googleCalendarLink(task), mode: LaunchMode.externalApplication)
          .catchError((_) => false);
    }
  }

  /// Opens the full form (checklist, links, repeat...) with what is typed.
  Future<void> _moreOptions() async {
    final draft = _build();
    final team = _isTeam ? _team : null;
    final nav = Navigator.of(context);
    nav.pop();
    await nav.push(MaterialPageRoute(builder: (_) => TaskFormScreen(draft: draft, team: team)));
  }

  // ------------------------------------------------------------------- pickers

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d != null) setState(() => _date = dateOnly(d));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
        context: context,
        initialTime: _time ?? TimeOfDay(hour: (DateTime.now().hour + 1) % 24, minute: 0));
    if (t != null) setState(() => _time = t);
  }

  Future<void> _newProject() async {
    final name = await textInputDialog(context, title: 'New project', hint: 'Project name');
    if (name == null) return;
    final store = AppStore.instance;
    final p =
        await store.addProject(name, kPaletteColors[store.projects.length % kPaletteColors.length]);
    setState(() => _projectId = p.id);
  }

  Future<void> _newLabel() async {
    final name = await textInputDialog(context, title: 'New label', hint: 'Label name');
    if (name == null) return;
    final store = AppStore.instance;
    final c = await store.addCategory(
        name, kPaletteColors[store.categories.length % kPaletteColors.length]);
    setState(() => _categoryId = c.id);
  }

  // --------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final wide = isWideScreen(context);
    final projects = store.projects.where((p) => p.deletedAt == null).toList();
    final team = _team;

    final dateField = _Field(
      label: 'Due date',
      child: _Box(
        onTap: _pickDate,
        text: DateFormat('EEE, d MMM yyyy').format(_date),
        trailing: Icons.calendar_today_outlined,
      ),
    );
    final timeField = _Field(
      label: 'Time (optional)',
      child: _Box(
        onTap: _pickTime,
        text: _time?.format(context) ?? 'Select time',
        muted: _time == null,
        trailing: _time == null ? Icons.schedule_rounded : Icons.close_rounded,
        onTrailing: _time == null ? null : () => setState(() => _time = null),
      ),
    );
    final priorityField = _Field(
      label: 'Priority',
      child: _Menu<Priority>(
        value: _priority,
        items: [
          for (final p in Priority.values.reversed)
            (p, p.label, Icons.flag_rounded, _priorityColor(p)),
        ],
        onChanged: (p) => setState(() => _priority = p),
      ),
    );

    final whereField = _Field(
      label: _isTeam ? 'Team' : 'Add to project',
      error: _teamError,
      child: _isTeam
          ? _Menu<String?>(
              value: team?.id,
              hint: _teams.isEmpty ? 'You are not in a team yet' : 'Select a team',
              leading: Icons.groups_outlined,
              items: [
                for (final t in _teams) (t.id, t.name, Icons.groups_rounded, Color(t.color)),
              ],
              onChanged: (id) => _setTeam(id == null ? null : TeamStore.instance.teamById(id)),
            )
          : _Menu<String?>(
              value: _projectId,
              hint: 'Select a project (optional)',
              leading: Icons.folder_outlined,
              items: [
                (null, 'No project', Icons.block_rounded, AppColors.textMuted),
                for (final p in projects) (p.id, p.name, Icons.folder_rounded, Color(p.color)),
              ],
              extra: ('New project', _newProject),
              onChanged: (id) => setState(() => _projectId = id),
            ),
    );
    final assignField = _Field(
      label: 'Assign to member',
      muted: !_isTeam,
      child: !_isTeam || team == null
          ? _Box(
              text: _isTeam ? 'Choose a team first' : 'Only for team tasks',
              muted: true,
              leading: Icons.person_outline_rounded,
              trailing: Icons.expand_more_rounded,
              disabled: true,
            )
          : _assignLocked
              ? _Box(
                  text: 'Me (${team.nameOf(TeamStore.instance.uid)})',
                  leading: Icons.lock_outline_rounded,
                  disabled: true,
                )
              : _Menu<String?>(
                  value: _assigneeId,
                  hint: 'Select a team member',
                  leading: Icons.person_outline_rounded,
                  items: [
                    (null, 'Not assigned', Icons.person_off_outlined, AppColors.textMuted),
                    for (final uid in team.sortedMemberIds)
                      (
                        uid,
                        uid == TeamStore.instance.uid
                            ? 'Me (${team.nameOf(uid)})'
                            : team.nameOf(uid),
                        Icons.person_rounded,
                        AppColors.primary
                      ),
                  ],
                  onChanged: (id) => setState(() => _assigneeId = id),
                ),
    );
    final labelField = _Field(
      label: 'Category / Label',
      muted: _isTeam,
      child: _isTeam
          ? const _Box(
              text: 'Labels are for personal tasks',
              muted: true,
              leading: Icons.sell_outlined,
              disabled: true)
          : _Menu<String?>(
              value: _categoryId,
              hint: 'Select a label',
              leading: Icons.sell_outlined,
              items: [
                (null, 'No label', Icons.block_rounded, AppColors.textMuted),
                for (final c in store.categories)
                  (c.id, c.name, Icons.label_rounded, Color(c.color)),
              ],
              extra: ('New label', _newLabel),
              onChanged: (id) => setState(() => _categoryId = id),
            ),
    );

    Widget pair(Widget a, Widget b) => wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: a),
            const SizedBox(width: 18),
            Expanded(child: b),
          ])
        : Column(children: [a, const SizedBox(height: 14), b]);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(wide ? 28 : 18, wide ? 24 : 14, wide ? 28 : 18, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Create a new task',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _KindCard(
                  icon: Icons.person_outline_rounded,
                  title: 'Personal task',
                  subtitle: 'Only for me',
                  selected: !_isTeam,
                  compact: !wide,
                  onTap: () => _setTeamMode(false),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _KindCard(
                  icon: Icons.groups_outlined,
                  title: 'Team task',
                  subtitle: _teams.isEmpty ? 'Join or create a team first' : 'Shared with a team',
                  selected: _isTeam,
                  compact: !wide,
                  onTap: _teams.isEmpty ? null : () => _setTeamMode(true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Field(
            label: 'Task title',
            required: true,
            error: _titleError,
            child: TextField(
              controller: _title,
              autofocus: wide,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [LengthLimitingTextInputFormatter(200)],
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
              onSubmitted: (_) => _create(),
              decoration: fieldDecoration('e.g. Complete landing page design',
                  icon: Icons.description_outlined),
            ),
          ),
          const SizedBox(height: 16),
          _Field(
            label: 'Description',
            child: TextField(
              controller: _desc,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [LengthLimitingTextInputFormatter(5000)],
              decoration: fieldDecoration('Add task description...'),
            ),
          ),
          const SizedBox(height: 16),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: dateField),
              const SizedBox(width: 16),
              Expanded(child: timeField),
              const SizedBox(width: 16),
              Expanded(child: priorityField),
            ])
          else ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: dateField),
              const SizedBox(width: 12),
              Expanded(child: timeField),
            ]),
            const SizedBox(height: 14),
            priorityField,
          ],
          const SizedBox(height: 16),
          // Phone: only the fields that apply to this kind of task.
          if (wide) ...[
            pair(whereField, assignField),
            const SizedBox(height: 16),
            labelField,
          ] else ...[
            whereField,
            const SizedBox(height: 14),
            if (_isTeam) assignField else labelField,
          ],
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _addToCalendar = !_addToCalendar),
            child: Row(
              children: [
                Checkbox(
                    value: _addToCalendar,
                    onChanged: (v) => setState(() => _addToCalendar = v ?? false)),
                const Flexible(
                  child: Text('Add to Google Calendar', style: TextStyle(fontSize: 14.5)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 10,
            children: [
              TextButton.icon(
                onPressed: _moreOptions,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('More options (checklist, links, repeat)'),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _create,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Create Task', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Color _priorityColor(Priority p) => switch (p) {
      Priority.high => AppColors.danger,
      Priority.medium => const Color(0xFFF59E0B),
      Priority.low => AppColors.success,
    };

/// Label above a field, with an optional red error under it.
class _Field extends StatelessWidget {
  final String label;
  final bool required;
  final bool muted;
  final String? error;
  final Widget child;
  const _Field(
      {required this.label,
      required this.child,
      this.required = false,
      this.muted = false,
      this.error});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              text: label,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                  color: muted ? AppColors.textMuted : AppColors.text),
              children: [
                if (required) const TextSpan(text: ' *', style: TextStyle(color: AppColors.danger)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          child,
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
            ),
        ],
      );
}

/// A field-looking box that opens a picker.
class _Box extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final IconData? leading;
  final IconData? trailing;
  final VoidCallback? onTrailing;
  final Color? leadingColor;
  final bool muted;
  final bool disabled;
  const _Box({
    required this.text,
    this.onTap,
    this.leading,
    this.trailing,
    this.onTrailing,
    this.leadingColor,
    this.muted = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: disabled ? const Color(0xFFF5F7FA) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              Icon(leading,
                  size: 20,
                  color: leadingColor ?? (disabled ? AppColors.border : AppColors.textMuted)),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14.5,
                      color: muted || disabled ? AppColors.textMuted : AppColors.text)),
            ),
            if (trailing != null)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: disabled ? null : (onTrailing ?? onTap),
                child: Icon(trailing,
                    size: 20, color: disabled ? AppColors.border : AppColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Drop-down styled like [_Box]. Items are (value, label, icon, color);
/// [extra] adds an action at the end ("New project").
class _Menu<T> extends StatelessWidget {
  final T value;
  final List<(T, String, IconData, Color)> items;
  final ValueChanged<T> onChanged;
  final String hint;
  final IconData? leading;
  final (String, VoidCallback)? extra;
  const _Menu({
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint = '',
    this.leading,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    (T, String, IconData, Color)? current;
    for (final i in items) {
      if (i.$1 == value) current = i;
    }
    return LayoutBuilder(
      builder: (context, box) => PopupMenuButton<int>(
        tooltip: '',
        position: PopupMenuPosition.under,
        constraints: BoxConstraints(minWidth: box.maxWidth, maxWidth: box.maxWidth),
        onSelected: (i) => i < 0 ? extra?.$2() : onChanged(items[i].$1),
        itemBuilder: (_) => [
          for (final (i, it) in items.indexed)
            PopupMenuItem(
              value: i,
              child: Row(children: [
                Icon(it.$3, size: 19, color: it.$4),
                const SizedBox(width: 10),
                Expanded(child: Text(it.$2, overflow: TextOverflow.ellipsis)),
                if (it.$1 == value)
                  const Icon(Icons.check_rounded, size: 18, color: AppColors.primary),
              ]),
            ),
          if (extra != null)
            PopupMenuItem(
              value: -1,
              child: Row(children: [
                const Icon(Icons.add_rounded, size: 19, color: AppColors.primary),
                const SizedBox(width: 10),
                Text(extra!.$1,
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
        child: IgnorePointer(
          child: _Box(
            text: current == null || (current.$1 == null && hint.isNotEmpty) ? hint : current.$2,
            muted: current == null || current.$1 == null,
            leading: current?.$1 == null ? leading : current!.$3,
            leadingColor: current?.$1 == null ? null : current!.$4,
            trailing: Icons.expand_more_rounded,
            onTap: () {},
          ),
        ),
      ),
    );
  }
}

/// "Personal task — Only for me" / "Team task — Shared with a team".
class _KindCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  /// Phone: no radio circle, so the text fits.
  final bool compact;
  const _KindCard({
    this.compact = false,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: selected ? const Color(0xFFBBD3FB) : AppColors.border, width: 1.4),
        ),
        child: Row(
          children: [
            if (!compact) ...[
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primary : Colors.white,
                  border: Border.all(
                      color: selected ? AppColors.primary : const Color(0xFFC5CBD5), width: 1.6),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
            ],
            Container(
              width: compact ? 34 : 40,
              height: compact ? 34 : 40,
              decoration: BoxDecoration(
                color: selected ? Colors.white : AppColors.background,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: onTap == null ? AppColors.textMuted : AppColors.primary),
            ),
            SizedBox(width: compact ? 8 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: selected ? AppColors.primary : AppColors.text)),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
