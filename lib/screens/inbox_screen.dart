import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/inbox.dart';
import '../data/models.dart';
import '../data/task_repository.dart';
import '../data/team_models.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import '../widgets/task_extras.dart';
import 'task_open.dart';
import 'task_ui.dart';

/// Inbox: capture tasks fast (typed, voice, pasted email, forwarded by a
/// teammate) and organize them later: date, priority, team, person, label,
/// then "Move to tasks".
class InboxScreen extends StatefulWidget {
  /// Opened as its own page on a phone (shows a back button).
  final bool page;
  const InboxScreen({super.key, this.page = false});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

/// List filters (the stat tiles and the Filter menu).
enum _Filter { all, noDate, quick, email, voice, forwarded }

enum _Sort { newest, oldest, due }

class _InboxScreenState extends State<InboxScreen> {
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.newest;
  final Set<String> _selected = {};

  /// Set by a suggestion's "Review": only these items are listed.
  Set<String>? _only;

  InboxStore get _inbox => InboxStore.instance;

  List<InboxItem> _visible(List<InboxItem> all) {
    final list = all.where((i) {
      if (_only != null && !_only!.contains(i.id)) return false;
      return switch (_filter) {
        _Filter.all => true,
        _Filter.noDate => i.dueAt == null,
        _Filter.quick => i.source == InboxSource.quick,
        _Filter.email => i.source == InboxSource.email,
        _Filter.voice => i.source == InboxSource.voice,
        _Filter.forwarded => i.source == InboxSource.forwarded,
      };
    }).toList();
    switch (_sort) {
      case _Sort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _Sort.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _Sort.due:
        final far = DateTime(9999);
        list.sort((a, b) => (a.dueAt ?? far).compareTo(b.dueAt ?? far));
    }
    return list;
  }

  void _setFilter(_Filter f) => setState(() {
        _filter = _filter == f ? _Filter.all : f;
        _only = null;
        _selected.clear();
      });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_inbox, TeamStore.instance, AppStore.instance]),
      builder: (context, _) {
        final items = _inbox.items;
        _selected.removeWhere((id) => !items.any((i) => i.id == id));
        return LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final side = box.maxWidth >= 1150;
          final main = _main(context, items, wide);
          final right = _SidePanel(
            items: items,
            onReview: (ids) => setState(() {
              _only = ids.toSet();
              _filter = _Filter.all;
            }),
          );
          final body = side
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: main),
                    const SizedBox(width: 22),
                    SizedBox(width: 380, child: right),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [main, const SizedBox(height: 18), right],
                );
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: widget.page
                ? AppBar(backgroundColor: AppColors.background, title: const Text('Inbox'))
                : null,
            body: ListView(
              padding: EdgeInsets.fromLTRB(wide ? 28 : 16, wide ? 22 : 8, wide ? 28 : 16, 32),
              children: [body],
            ),
          );
        });
      },
    );
  }

  Widget _main(BuildContext context, List<InboxItem> items, bool wide) {
    final visible = _visible(items);
    final count = (bool Function(InboxItem) f) => items.where(f).length;
    final tiles = [
      _StatTile(Icons.inbox_rounded, AppColors.primary, '${items.length}', 'Inbox items',
          _filter == _Filter.all && _only == null, () => _setFilter(_Filter.all)),
      _StatTile(Icons.warning_amber_rounded, AppColors.danger, '${count((i) => i.dueAt == null)}',
          'Need due date', _filter == _Filter.noDate, () => _setFilter(_Filter.noDate)),
      _StatTile(
          Icons.mail_outline_rounded,
          const Color(0xFFEA7A0C),
          '${count((i) => i.source == InboxSource.email)}',
          'From email',
          _filter == _Filter.email,
          () => _setFilter(_Filter.email)),
      _StatTile(
          Icons.mic_none_rounded,
          AppColors.success,
          '${count((i) => i.source == InboxSource.voice)}',
          'From voice',
          _filter == _Filter.voice,
          () => _setFilter(_Filter.voice)),
      _StatTile(
          Icons.arrow_forward_rounded,
          AppColors.primary,
          '${count((i) => i.source == InboxSource.forwarded)}',
          'Forwarded',
          _filter == _Filter.forwarded,
          () => _setFilter(_Filter.forwarded)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide) ...[
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(Icons.mark_email_unread_rounded, color: AppColors.primary, size: 34),
              ),
              SizedBox(width: 14),
              Expanded(
                child: PageHeader(
                    title: 'Inbox', subtitle: 'Capture tasks fast and organize them later.'),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],
        _QuickCapture(wide: wide),
        const SizedBox(height: 16),
        if (wide)
          Row(
            children: [
              for (final (i, t) in tiles.indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: t),
              ],
            ],
          )
        else
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tiles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => SizedBox(width: 168, child: tiles[i]),
            ),
          ),
        const SizedBox(height: 16),
        DashCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _listHeader(context, visible, wide),
              const Divider(height: 1, color: AppColors.border),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: EmptyState(
                    icon: Icons.inbox_outlined,
                    title: items.isEmpty ? 'Inbox zero' : 'Nothing here',
                    subtitle: items.isEmpty
                        ? 'Type anything above and press Enter. Organize it later.'
                        : 'No items match this filter.',
                  ),
                )
              else
                for (final (i, item) in visible.indexed) ...[
                  if (i > 0) const Divider(height: 1, color: AppColors.border),
                  _InboxRow(
                    item: item,
                    wide: wide,
                    selected: _selected.contains(item.id),
                    onSelect: (v) => setState(() {
                      if (v) {
                        _selected.add(item.id);
                      } else {
                        _selected.remove(item.id);
                      }
                    }),
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _listHeader(BuildContext context, List<InboxItem> visible, bool wide) {
    final all = visible.isNotEmpty && visible.every((i) => _selected.contains(i.id));
    final selected = [
      for (final i in visible)
        if (_selected.contains(i.id)) i
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      child: Row(
        children: [
          Checkbox(
            value: all,
            onChanged: visible.isEmpty
                ? null
                : (v) => setState(() {
                      if (v == true) {
                        _selected.addAll(visible.map((i) => i.id));
                      } else {
                        _selected.clear();
                      }
                    }),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              selected.isNotEmpty
                  ? '${selected.length} selected'
                  : '${visible.length} inbox ${visible.length == 1 ? 'item' : 'items'}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          if (_only != null)
            TextButton.icon(
              onPressed: () => setState(() => _only = null),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Show all'),
            ),
          if (selected.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () async {
                final day = await _pickDay(context, selected);
                if (day == null || !context.mounted) return;
                await _moveAll(context, selected, day);
                setState(_selected.clear);
              },
              icon: const Icon(Icons.drive_file_move_outline, size: 19),
              label: const Text('Move to tasks'),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: 'Delete ${selected.length} items?',
                    message: 'They will be removed from your inbox.',
                    confirmLabel: 'Delete',
                    danger: true);
                if (!ok) return;
                _inbox.delete(selected.map((i) => i.id));
                setState(_selected.clear);
              },
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            ),
          ] else ...[
            PopupMenuButton<_Sort>(
              tooltip: 'Sort',
              position: PopupMenuPosition.under,
              onSelected: (s) => setState(() => _sort = s),
              itemBuilder: (_) => [
                for (final s in _Sort.values)
                  CheckedPopupMenuItem(value: s, checked: _sort == s, child: Text(_sortLabel(s))),
              ],
              child: wide
                  ? _OutlineButton(
                      icon: Icons.swap_vert_rounded,
                      label: 'Sort: ${_sortLabel(_sort)}',
                      menu: true)
                  : const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.swap_vert_rounded)),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<_Filter>(
              tooltip: 'Filter',
              position: PopupMenuPosition.under,
              onSelected: (f) => setState(() {
                _filter = f;
                _only = null;
              }),
              itemBuilder: (_) => [
                for (final f in _Filter.values)
                  CheckedPopupMenuItem(
                      value: f, checked: _filter == f, child: Text(_filterLabel(f))),
              ],
              child: wide
                  ? const _OutlineButton(icon: Icons.filter_alt_outlined, label: 'Filter')
                  : const Padding(
                      padding: EdgeInsets.all(8), child: Icon(Icons.filter_alt_outlined)),
            ),
          ],
        ],
      ),
    );
  }

  static String _sortLabel(_Sort s) => switch (s) {
        _Sort.newest => 'Newest first',
        _Sort.oldest => 'Oldest first',
        _Sort.due => 'Due date',
      };

  static String _filterLabel(_Filter f) => switch (f) {
        _Filter.all => 'All items',
        _Filter.noDate => 'Need due date',
        _Filter.quick => 'Quick Capture',
        _Filter.email => 'From email',
        _Filter.voice => 'From voice',
        _Filter.forwarded => 'Forwarded',
      };
}

// ------------------------------------------------------------------ actions

/// For items without a date: the day they go to. Null = cancelled. Items
/// that all have dates need no question.
Future<DateTime?> _pickDay(BuildContext context, List<InboxItem> items) async {
  final now = DateTime.now();
  if (items.every((i) => i.dueAt != null)) return dateOnly(now);
  return showDatePicker(
    context: context,
    helpText: 'Due date for items without one',
    initialDate: now,
    firstDate: DateTime(now.year - 1),
    lastDate: DateTime(now.year + 5),
  );
}

Future<void> _moveAll(BuildContext context, List<InboxItem> items, DateTime day) async {
  var moved = 0;
  String? error;
  for (final i in items) {
    final e = await InboxStore.instance.organize(i, day: day);
    if (e == null) {
      moved++;
    } else {
      error ??= e;
    }
  }
  if (!context.mounted) return;
  showSnack(
      context,
      error == null
          ? (moved == 1 ? 'Moved to ${items.first.organizedTo}' : '$moved tasks moved')
          : '$moved moved. $error');
}

Future<void> _moveOne(BuildContext context, InboxItem item) async {
  final day = await _pickDay(context, [item]);
  if (day == null || !context.mounted) return;
  await _moveAll(context, [item], day);
}

/// Today / Tomorrow / Next week / a date and time / none.
Future<void> _chooseDue(BuildContext context, InboxItem item, Offset? at) async {
  final now = DateTime.now();
  final today = dateOnly(now);
  final pick = await showMenu<String>(
    context: context,
    position: _menuPos(context, at),
    items: const [
      PopupMenuItem(value: 'today', child: Text('Today')),
      PopupMenuItem(value: 'tomorrow', child: Text('Tomorrow')),
      PopupMenuItem(value: 'week', child: Text('Next week')),
      PopupMenuItem(value: 'pick', child: Text('Pick date & time...')),
      PopupMenuItem(value: 'none', child: Text('No due date')),
    ],
  );
  if (pick == null || !context.mounted) return;
  switch (pick) {
    case 'today' || 'tomorrow' || 'week':
      item
        ..dueAt = today.add(Duration(days: pick == 'today' ? 0 : (pick == 'tomorrow' ? 1 : 7)))
        ..allDay = true;
    case 'none':
      item
        ..dueAt = null
        ..allDay = false;
    case 'pick':
      final d = await showDatePicker(
        context: context,
        initialDate: item.dueAt ?? now,
        firstDate: DateTime(now.year - 1),
        lastDate: DateTime(now.year + 5),
      );
      if (d == null || !context.mounted) return;
      final t = await showTimePicker(
        context: context,
        helpText: 'Time (cancel for all day)',
        initialTime: item.dueAt != null && !item.allDay
            ? TimeOfDay.fromDateTime(item.dueAt!)
            : const TimeOfDay(hour: 9, minute: 0),
      );
      item
        ..dueAt = t == null ? d : DateTime(d.year, d.month, d.day, t.hour, t.minute)
        ..allDay = t == null;
  }
  InboxStore.instance.update(item);
}

RelativeRect _menuPos(BuildContext context, Offset? at) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final p = at ?? overlay.size.center(Offset.zero);
  return RelativeRect.fromRect(p & const Size(1, 1), Offset.zero & overlay.size);
}

Future<void> _choosePriority(BuildContext context, InboxItem item, Offset? at) async {
  final p = await showMenu<int>(
    context: context,
    position: _menuPos(context, at),
    items: [
      for (final p in Priority.values.reversed) PopupMenuItem(value: p.index, child: Text(p.label)),
      const PopupMenuItem(value: -1, child: Text('Not set')),
    ],
  );
  if (p == null) return;
  item.priority = p < 0 ? null : Priority.values[p];
  InboxStore.instance.update(item);
}

Future<void> _chooseTeam(BuildContext context, InboxItem item, Offset? at) async {
  final teams = TeamStore.instance.teams.where(TeamStore.instance.canCreateTask).toList();
  if (teams.isEmpty) {
    showSnack(context, 'Join or create a team first.');
    return;
  }
  final id = await showMenu<String>(
    context: context,
    position: _menuPos(context, at),
    items: [
      const PopupMenuItem(value: '', child: Text('Personal (My Tasks)')),
      for (final t in teams)
        PopupMenuItem(
          value: t.id,
          child: Row(children: [
            Icon(Icons.groups_rounded, size: 18, color: Color(t.color)),
            const SizedBox(width: 10),
            Flexible(child: Text(t.name, overflow: TextOverflow.ellipsis)),
          ]),
        ),
    ],
  );
  if (id == null) return;
  item.teamId = id.isEmpty ? null : id;
  if (id.isNotEmpty) item.categoryId = null;
  final team = id.isEmpty ? null : TeamStore.instance.teamById(id);
  if (team == null || !team.memberIds.contains(item.assigneeId)) item.assigneeId = null;
  InboxStore.instance.update(item);
}

/// People of the item's team, or of all my teams (choosing one also picks
/// the team). Plain members can only take a task themselves.
Future<void> _chooseAssignee(BuildContext context, InboxItem item, Offset? at) async {
  final store = TeamStore.instance;
  final me = store.uid;
  final teams = item.teamId == null
      ? store.teams.where(store.canCreateTask).toList()
      : [store.teamById(item.teamId!)].whereType<Team>().toList();
  if (teams.isEmpty) {
    showSnack(context, 'Tasks can be given to people in a team. Join or create a team first.');
    return;
  }
  final pick = await showMenu<String>(
    context: context,
    position: _menuPos(context, at),
    items: [
      const PopupMenuItem(value: '|', child: Text('Unassigned')),
      for (final t in teams) ...[
        if (teams.length > 1)
          PopupMenuItem(
              enabled: false,
              height: 30,
              child: Text(t.name.toUpperCase(),
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700))),
        for (final uid in t.memberIds)
          if (store.isAdmin(t) || uid == me)
            PopupMenuItem(
              value: '${t.id}|$uid',
              child: Row(children: [
                Avatar(name: t.nameOf(uid), size: 26),
                const SizedBox(width: 10),
                Flexible(
                    child: Text(uid == me ? '${t.nameOf(uid)} (me)' : t.nameOf(uid),
                        overflow: TextOverflow.ellipsis)),
              ]),
            ),
      ],
    ],
  );
  if (pick == null) return;
  final parts = pick.split('|');
  if (parts[0].isEmpty) {
    item.assigneeId = null;
  } else {
    item
      ..teamId = parts[0]
      ..assigneeId = parts[1]
      ..categoryId = null;
  }
  InboxStore.instance.update(item);
}

Future<void> _chooseLabel(BuildContext context, InboxItem item, Offset? at) async {
  final cats = AppStore.instance.categories.where((c) => c.deletedAt == null).toList();
  if (cats.isEmpty) {
    showSnack(context, 'Add labels (categories) in Profile first.');
    return;
  }
  final id = await showMenu<String>(
    context: context,
    position: _menuPos(context, at),
    items: [
      for (final c in cats)
        PopupMenuItem(
          value: c.id,
          child: Row(children: [
            Icon(Icons.label_rounded, size: 18, color: Color(c.color)),
            const SizedBox(width: 10),
            Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      const PopupMenuItem(value: '', child: Text('No label')),
    ],
  );
  if (id == null) return;
  item.categoryId = id.isEmpty ? null : id;
  InboxStore.instance.update(item);
}

Future<void> _edit(BuildContext context, InboxItem item) async {
  final title = TextEditingController(text: item.title);
  final notes = TextEditingController(text: item.notes);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Edit inbox item'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    ),
  );
  if (ok != true || title.text.trim().isEmpty) return;
  item
    ..title = title.text.trim()
    ..notes = notes.text.trim();
  InboxStore.instance.update(item);
}

Future<void> _forward(BuildContext context, InboxItem item) async {
  final store = TeamStore.instance;
  final me = store.uid;
  final people = <(Team, String)>[];
  final seen = <String>{};
  for (final t in store.teams) {
    for (final uid in t.memberIds) {
      if (uid != me && seen.add(uid)) people.add((t, uid));
    }
  }
  if (people.isEmpty) {
    showSnack(context, 'You can forward to people in your teams.');
    return;
  }
  final pick = await showDialog<(Team, String)>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Forward to a teammate'),
      children: [
        for (final (t, uid) in people)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, (t, uid)),
            child: Row(children: [
              Avatar(name: t.nameOf(uid), size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.nameOf(uid), style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(t.name, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                ]),
              ),
            ]),
          ),
      ],
    ),
  );
  if (pick == null || !context.mounted) return;
  InboxStore.instance.forward(item, pick.$1, pick.$2);
  showSnack(context, 'Sent to ${pick.$1.nameOf(pick.$2)}\'s inbox');
}

// ------------------------------------------------------------- quick capture

class _QuickCapture extends StatefulWidget {
  final bool wide;
  const _QuickCapture({required this.wide});

  @override
  State<_QuickCapture> createState() => _QuickCaptureState();
}

class _QuickCaptureState extends State<_QuickCapture> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final List<TaskLink> _links = [];

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add({String source = InboxSource.quick}) {
    final text = _text.text.trim();
    if (text.isEmpty) {
      _focus.requestFocus();
      return;
    }
    InboxStore.instance.capture(text, source: source, links: _links);
    setState(() {
      _text.clear();
      _links.clear();
    });
    _focus.requestFocus();
  }

  Future<void> _voice() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.mic_rounded, color: AppColors.danger),
          SizedBox(width: 10),
          Text('Voice capture'),
        ]),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Tap the mic on your keyboard and speak. Say a day or time too, '
                  'like "call Ali tomorrow at 5 pm".',
                  style: TextStyle(color: AppColors.textMuted, height: 1.4)),
              const SizedBox(height: 14),
              TextField(
                controller: c,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => Navigator.pop(ctx, v),
                decoration: const InputDecoration(hintText: 'What do you need to do?'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Add')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    InboxStore.instance.capture(text, source: InboxSource.voice);
  }

  Future<void> _email() async {
    final subject = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import from Email'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Copy the email from Gmail or Outlook and paste it here. '
                  'The subject becomes the task, the rest its notes.',
                  style: TextStyle(color: AppColors.textMuted, height: 1.4)),
              const SizedBox(height: 14),
              TextField(
                  controller: subject,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Subject')),
              const SizedBox(height: 12),
              TextField(
                controller: body,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(labelText: 'Email text'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import')),
        ],
      ),
    );
    if (ok != true) return;
    final (title, notes) = parseEmail(subject.text, body.text);
    if (title.isEmpty) return;
    InboxStore.instance.capture(title,
        source: InboxSource.email, notes: notes.length > 5000 ? notes.substring(0, 5000) : notes);
    if (mounted) showSnack(context, 'Email added to your inbox');
  }

  Future<void> _attach() async {
    final link = await linkDialog(context);
    if (link != null) setState(() => _links.add(link));
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _text,
      focusNode: _focus,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _add(),
      style: const TextStyle(fontSize: 15),
      decoration: const InputDecoration(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: 6),
        hintText: 'Type and press Enter to add a task...',
      ),
    );
    Widget square(IconData icon, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, color: AppColors.textMuted, size: 22),
            ),
          ),
        );
    final emailBtn = OutlinedButton.icon(
      onPressed: _email,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.mail_outline_rounded, color: AppColors.primary, size: 20),
      label: const Text('Import from Email'),
    );
    final addBtn = FilledButton(
      onPressed: _add,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text('Add Task', style: TextStyle(fontWeight: FontWeight.w700)),
    );
    final links = _links.isEmpty
        ? null
        : Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final l in _links)
                InputChip(
                  avatar: const Icon(Icons.link_rounded, size: 16),
                  label: Text(l.label, overflow: TextOverflow.ellipsis),
                  onDeleted: () => setState(() => _links.remove(l)),
                ),
            ],
          );
    const hint = Text('Try: "Send invoice tomorrow 5pm !high #Marketing"',
        style: TextStyle(fontSize: 12, color: AppColors.textMuted));

    if (!widget.wide) {
      return DashCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.edit_rounded, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(child: field),
            ]),
            if (links != null) Padding(padding: const EdgeInsets.only(top: 6), child: links),
            const SizedBox(height: 8),
            Row(
              children: [
                square(Icons.mic_none_rounded, 'Voice', _voice),
                const SizedBox(width: 8),
                square(Icons.attach_file_rounded, 'Attach a link', _attach),
                const SizedBox(width: 8),
                square(Icons.mail_outline_rounded, 'Import from Email', _email),
                const Spacer(),
                addBtn,
              ],
            ),
          ],
        ),
      );
    }
    return DashCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: AppColors.primaryLight, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.edit_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Quick Capture',
                        style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                    field,
                  ],
                ),
              ),
              const SizedBox(width: 10),
              square(Icons.mic_none_rounded, 'Voice', _voice),
              const SizedBox(width: 8),
              square(Icons.attach_file_rounded, 'Attach a link', _attach),
              const SizedBox(width: 12),
              emailBtn,
              const SizedBox(width: 10),
              addBtn,
            ],
          ),
          if (links != null) Padding(padding: const EdgeInsets.only(top: 8), child: links),
          const Padding(padding: EdgeInsets.only(left: 66, top: 2), child: hint),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------- rows

class _InboxRow extends StatelessWidget {
  final InboxItem item;
  final bool wide;
  final bool selected;
  final ValueChanged<bool> onSelect;
  const _InboxRow(
      {required this.item, required this.wide, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final i = item;
    final team = i.teamId == null ? null : TeamStore.instance.teamById(i.teamId!);
    final cat = AppStore.instance.categoryById(i.categoryId);

    // ---- title block
    final (IconData srcIcon, String srcText) = switch (i.source) {
      InboxSource.email => (Icons.mail_outline_rounded, 'Email'),
      InboxSource.voice => (Icons.mic_none_rounded, 'Voice'),
      InboxSource.forwarded => (
          Icons.arrow_forward_rounded,
          i.fromName == null ? 'Forwarded' : 'From ${i.fromName}'
        ),
      _ => (Icons.description_outlined, 'Quick Capture'),
    };
    final due = i.dueAt;
    final dueColor = due == null
        ? AppColors.textMuted
        : (due.isBefore(now) || isSameDay(due, now) ? AppColors.danger : AppColors.primary);
    final meta = Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (due != null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.schedule_rounded, size: 17, color: dueColor),
            const SizedBox(width: 5),
            Text(_dueText(i, now), style: TextStyle(color: dueColor, fontSize: 13.5)),
          ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(srcIcon, size: 17, color: AppColors.textMuted),
          const SizedBox(width: 5),
          Text(srcText, style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
        ]),
        if (i.notes.isNotEmpty)
          const Icon(Icons.notes_rounded, size: 17, color: AppColors.textMuted),
        if (i.links.isNotEmpty)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.link_rounded, size: 17, color: AppColors.textMuted),
            const SizedBox(width: 3),
            Text('${i.links.length}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ]),
      ],
    );
    final titleBlock = InkWell(
      onTap: () => _edit(context, i),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          meta,
        ],
      ),
    );

    // ---- organize chips
    Widget chip(String label, IconData icon, Color fg, Color bg,
            void Function(BuildContext, InboxItem, Offset?) onTap) =>
        _ActionChip(label: label, icon: icon, fg: fg, bg: bg, onTap: (o) => onTap(context, i, o));
    const grey = Color(0xFFF3F4F6);
    const greyFg = Color(0xFF4B5563);
    final dueChip = due == null
        ? chip('No due date', Icons.event_busy_rounded, AppColors.danger, AppColors.dangerLight,
            _chooseDue)
        : chip(_chipDate(i, now), Icons.calendar_today_outlined, greyFg, grey, _chooseDue);
    final who = i.assigneeId == null || team == null ? null : team.nameOf(i.assigneeId);
    final assignChip = chip(
        who ?? 'Assign',
        Icons.person_outline_rounded,
        who == null ? greyFg : AppColors.purple,
        who == null ? grey : AppColors.purpleLight,
        _chooseAssignee);
    final prio = i.priority;
    final prioChip = prio == null
        ? chip('Set priority', Icons.flag_outlined, greyFg, grey, _choosePriority)
        : chip(
            prio.label,
            Icons.flag_rounded,
            switch (prio) {
              Priority.high => AppColors.danger,
              Priority.medium => const Color(0xFFEA7A0C),
              Priority.low => greyFg,
            },
            switch (prio) {
              Priority.high => AppColors.dangerLight,
              Priority.medium => const Color(0xFFFFF0DF),
              Priority.low => grey,
            },
            _choosePriority);
    final teamChip = team == null
        ? chip('Add to team', Icons.groups_outlined, AppColors.primary, AppColors.primaryLight,
            _chooseTeam)
        : chip(team.name, Icons.groups_rounded, Color(team.color), Color(team.color).withAlpha(28),
            _chooseTeam);
    final labelChip = team != null
        ? null
        : (cat == null
            ? chip('Add label', Icons.label_outline_rounded, greyFg, grey, _chooseLabel)
            : chip(cat.name, Icons.label_rounded, Color(cat.color), Color(cat.color).withAlpha(28),
                _chooseLabel));
    final chips = Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [dueChip, assignChip, prioChip, teamChip, if (labelChip != null) labelChip],
    );

    final menu = PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (a) async {
        switch (a) {
          case 'move':
            await _moveOne(context, i);
          case 'edit':
            await _edit(context, i);
          case 'forward':
            await _forward(context, i);
          case 'delete':
            InboxStore.instance.delete([i.id]);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
            value: 'move',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.drive_file_move_outline),
                title: Text('Move to tasks'))),
        PopupMenuItem(
            value: 'edit',
            child: ListTile(dense: true, leading: Icon(Icons.edit_outlined), title: Text('Edit'))),
        PopupMenuItem(
            value: 'forward',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.forward_to_inbox_outlined),
                title: Text('Forward to teammate'))),
        PopupMenuItem(
            value: 'delete',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                title: Text('Delete', style: TextStyle(color: AppColors.danger)))),
      ],
    );
    final moveBtn = Tooltip(
      message: 'Move to tasks',
      child: IconButton(
        onPressed: () => _moveOne(context, i),
        icon: const Icon(Icons.drive_file_move_outline, color: AppColors.primary),
      ),
    );

    return Container(
      color: selected ? AppColors.primaryLight.withAlpha(110) : null,
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      child: wide
          ? Row(
              children: [
                Checkbox(value: selected, onChanged: (v) => onSelect(v ?? false)),
                const SizedBox(width: 6),
                Expanded(flex: 5, child: titleBlock),
                const SizedBox(width: 12),
                Expanded(flex: 6, child: chips),
                moveBtn,
                menu,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(value: selected, onChanged: (v) => onSelect(v ?? false)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: const EdgeInsets.only(top: 6), child: titleBlock),
                      const SizedBox(height: 10),
                      chips,
                    ],
                  ),
                ),
                Column(children: [menu, moveBtn]),
              ],
            ),
    );
  }

  static String _dueText(InboxItem i, DateTime now) {
    final d = i.dueAt!;
    final day = isSameDay(d, now)
        ? 'Today'
        : isSameDay(d, now.add(const Duration(days: 1)))
            ? 'Tomorrow'
            : DateFormat(d.year == now.year ? 'EEE d MMM' : 'd MMM yyyy').format(d);
    return i.allDay ? day : '$day ${formatTime(d)}';
  }

  static String _chipDate(InboxItem i, DateTime now) {
    final d = i.dueAt!;
    return DateFormat(d.year == now.year ? 'd MMM' : 'd MMM yy').format(d);
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;
  final ValueChanged<Offset?> onTap;
  const _ActionChip(
      {required this.label,
      required this.icon,
      required this.fg,
      required this.bg,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTapUp: (d) => onTap(d.globalPosition),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      );
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _StatTile(this.icon, this.color, this.value, this.label, this.active, this.onTap);

  @override
  Widget build(BuildContext context) => Material(
        color: active ? color.withAlpha(22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: active ? color.withAlpha(90) : const Color(0xFFEEF1F6)),
            ),
            child: Row(
              children: [
                IconBox(icon: icon, color: color, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(value,
                          style:
                              TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _OutlineButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool menu;
  const _OutlineButton({required this.icon, required this.label, this.menu = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          if (menu) const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        ]),
      );
}

// ---------------------------------------------------------------- side panel

class _SidePanel extends StatelessWidget {
  final List<InboxItem> items;
  final ValueChanged<List<String>> onReview;
  const _SidePanel({required this.items, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final inbox = InboxStore.instance;
    final suggestions = inboxSuggestions(
        items,
        TeamStore.instance.teams.where(TeamStore.instance.canCreateTask).toList(),
        AppStore.instance.categories.where((c) => c.deletedAt == null).toList());
    final recent = inbox.recentlyOrganized.take(3).toList();

    Widget title(IconData icon, Color color, String text, [String? sub]) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(text, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                  if (sub != null)
                    Text(sub, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                ]),
              ),
            ],
          ),
        );

    final total = items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---------------------------------------------------- suggestions
        DashCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title(
                  Icons.auto_awesome_rounded,
                  AppColors.primary,
                  'Organize suggestions',
                  suggestions.isEmpty
                      ? 'Nothing to suggest right now.'
                      : 'Ways to organize your inbox.'),
              for (final s in suggestions.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SuggestionTile(s: s, onReview: () => onReview(s.itemIds)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ------------------------------------------------- capture sources
        DashCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title(Icons.bar_chart_rounded, AppColors.primary, 'Capture sources'),
              for (final (src, icon, color) in const [
                (InboxSource.quick, Icons.description_outlined, AppColors.primary),
                (InboxSource.email, Icons.mail_rounded, AppColors.purple),
                (InboxSource.voice, Icons.mic_rounded, AppColors.danger),
                (InboxSource.forwarded, Icons.arrow_forward_rounded, Color(0xFFEA7A0C)),
              ])
                Builder(builder: (context) {
                  final n = items.where((i) => i.source == src).length;
                  final pct = total == 0 ? 0.0 : n / total;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        IconBox(icon: icon, color: color, size: 32),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 4,
                          child: Text(InboxSource.label(src),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        SizedBox(
                          width: 62,
                          child: Text('$n ${n == 1 ? 'task' : 'tasks'}',
                              style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                        ),
                        Expanded(
                          flex: 4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: pct,
                              minHeight: 7,
                              color: color,
                              backgroundColor: const Color(0xFFEEF1F6),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text('${(pct * 100).round()}%',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ----------------------------------------------- recently organized
        DashCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title(Icons.history_rounded, AppColors.primary, 'Recently organized'),
              if (recent.isEmpty)
                const Text('Items you move to your tasks show here for a week.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              for (final r in recent) _RecentTile(item: r),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ------------------------------------------------------ how it works
        DashCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title(Icons.lightbulb_rounded, const Color(0xFFF59E0B), 'How it works'),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Step(1, 'Capture', 'Add tasks instantly from anywhere.'),
                  _Step(2, 'Organize', 'Add dates, priority, team, person and labels.'),
                  _Step(3, 'Schedule', 'Move to My Tasks, a team or the calendar.'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final InboxSuggestion s;
  final VoidCallback onReview;
  const _SuggestionTile({required this.s, required this.onReview});

  Future<void> _apply(BuildContext context) async {
    final inbox = InboxStore.instance;
    final items = s.itemIds.map(inbox.byId).whereType<InboxItem>().toList();
    switch (s.kind) {
      case SuggestionKind.team:
        for (final i in items) {
          i
            ..teamId = s.targetId
            ..categoryId = null
            ..assigneeId = null;
          inbox.update(i);
        }
      case SuggestionKind.label:
        for (final i in items) {
          i.categoryId = s.targetId;
          inbox.update(i);
        }
      case SuggestionKind.dates:
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          helpText: 'Due date for ${items.length} items',
          initialDate: now,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 5),
        );
        if (d == null) return;
        for (final i in items) {
          i
            ..dueAt = d
            ..allDay = true;
          inbox.update(i);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String action) = switch (s.kind) {
      SuggestionKind.team => (Icons.groups_rounded, AppColors.success, 'Add'),
      SuggestionKind.label => (Icons.view_in_ar_rounded, AppColors.purple, 'Label'),
      SuggestionKind.dates => (Icons.calendar_month_rounded, AppColors.danger, 'Add dates'),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEF1F6)),
      ),
      child: Row(
        children: [
          IconBox(icon: icon, color: color, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onReview,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(s.subtitle,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () => _apply(context),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryLight,
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  final InboxItem item;
  const _RecentTile({required this.item});

  TaskRef? _task() {
    final id = item.taskId;
    if (id == null) return null;
    final teamId = item.taskTeamId;
    if (teamId == null) {
      final t = AppStore.instance.taskById(id);
      return t == null ? null : TaskRef(t);
    }
    final team = TeamStore.instance.teamById(teamId);
    final t = team == null ? null : TeamStore.instance.taskById(teamId, id);
    return t == null ? null : TaskRef(t, team);
  }

  @override
  Widget build(BuildContext context) {
    final ref = _task();
    final forwarded = item.organizedTo?.startsWith('Forwarded') ?? false;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: ref == null ? null : () => openTaskRef(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            IconBox(
                icon: forwarded ? Icons.forward_to_inbox_rounded : Icons.task_alt_rounded,
                color: forwarded ? const Color(0xFFEA7A0C) : AppColors.success,
                size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${forwarded ? item.organizedTo : 'Moved to ${item.organizedTo}'} • '
                    '${timeAgo(item.organizedAt!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String title;
  final String text;
  const _Step(this.n, this.title, this.text);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: AppColors.primary,
              child: Text('$n',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.3)),
          ],
        ),
      );
}
