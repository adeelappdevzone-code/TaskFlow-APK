import 'package:flutter/material.dart';
import '../data/images.dart';
import '../widgets/images.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/chat_store.dart';
import '../data/models.dart';
import '../data/task_repository.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import '../widgets/responsive.dart';
import '../widgets/task_extras.dart';
import 'main_shell.dart';
import 'task_open.dart';

/// Opens the direct chat with a teammate: in Messages on a laptop, as its
/// own page on a phone.
void openChatWith(BuildContext context, Contact c) {
  final id = ChatStore.instance.openDirect(c);
  openChat(context, id);
}

void openChat(BuildContext context, String chatId) {
  if (isWideScreen(context)) {
    MessagesScreen.select.value = chatId;
    MainShell.switchTab(context, 13);
  } else {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(chatId: chatId)));
  }
}

String _time(DateTime d) {
  final now = DateTime.now();
  if (isSameDay(d, now)) return DateFormat('h:mm a').format(d);
  if (isSameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  if (now.difference(d).inDays < 7) return DateFormat('EEE').format(d);
  return DateFormat('d MMM').format(d);
}

/// Start a chat: pick a teammate, or ask someone else by email.
Future<String?> newChatDialog(BuildContext context) async {
  final store = ChatStore.instance;
  final contacts = store.contacts();
  final email = TextEditingController();
  var q = '';
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final list = contacts
            .where((c) =>
                q.isEmpty || c.name.toLowerCase().contains(q) || c.email.toLowerCase().contains(q))
            .toList();
        return AlertDialog(
          title: const Text('New message'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (contacts.isNotEmpty) ...[
                    TextField(
                      autofocus: true,
                      onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
                      decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search_rounded),
                          hintText: 'Search people in your teams'),
                    ),
                    const SizedBox(height: 6),
                    for (final c in list.take(30))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Avatar(name: c.name, size: 36, uid: c.uid),
                        title: Text(c.name),
                        subtitle: Text(
                            c.teamIds
                                .map((id) => TeamStore.instance.teamById(id)?.name ?? '')
                                .join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.pop(ctx, store.openDirect(c)),
                      ),
                    const Divider(height: 24),
                  ],
                  const Text('Someone not in your teams?',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text(
                      'Enter the email they log in with. They accept your chat request '
                      'in their Messages.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.mail_outline_rounded),
                        hintText: 'name@example.com',
                        errorText: error),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final err = store.requestByEmail(email.text);
                if (err != null) {
                  setState(() => error = err);
                  return;
                }
                final mail = email.text.trim().toLowerCase();
                final known = contacts.where((c) => c.email.toLowerCase() == mail).firstOrNull;
                Navigator.pop(ctx,
                    known != null ? directChatId(store.uid!, known.uid) : 'req_${store.uid}_$mail');
              },
              child: const Text('Send request'),
            ),
          ],
        );
      },
    ),
  );
}

// ------------------------------------------------------------------ screen

class MessagesScreen extends StatefulWidget {
  final bool page;
  const MessagesScreen({super.key, this.page = false});

  /// Chat to show (set by "Message" buttons elsewhere).
  static final select = ValueNotifier<String?>(null);

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool _group = false;
  String _search = '';
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = MessagesScreen.select.value;
    MessagesScreen.select.addListener(_onSelect);
  }

  @override
  void dispose() {
    MessagesScreen.select.removeListener(_onSelect);
    super.dispose();
  }

  void _onSelect() {
    final id = MessagesScreen.select.value;
    if (id == null) return;
    setState(() {
      _selected = id;
      _group = id.startsWith('team_');
    });
  }

  void _open(BuildContext context, String id, bool wide) {
    if (wide) {
      setState(() => _selected = id);
      MessagesScreen.select.value = id;
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(chatId: id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ChatStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([store, TeamStore.instance]),
      builder: (context, _) => LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final list = _ChatList(
          group: _group,
          search: _search,
          selected: wide ? _selected : null,
          onGroup: (g) => setState(() => _group = g),
          onSearch: (v) => setState(() => _search = v),
          onOpen: (id) => _open(context, id, wide),
          onNew: () async {
            final id = await newChatDialog(context);
            if (id != null && context.mounted) {
              setState(() => _group = false);
              _open(context, id, wide);
            }
          },
        );
        if (!wide) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: widget.page
                ? AppBar(backgroundColor: AppColors.background, title: const Text('Messages'))
                : null,
            body: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: list),
          );
        }
        final sel = _selected;
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PageHeader(
                    title: 'Messages',
                    subtitle: 'Chat with your team, share tasks and links, and keep work moving.'),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 340, child: list),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DashCard(
                          padding: EdgeInsets.zero,
                          child: sel == null || store.byId(sel) == null
                              ? const Center(
                                  child: EmptyState(
                                    icon: Icons.forum_outlined,
                                    title: 'Pick a conversation',
                                    subtitle: 'Or start a new one with the pencil button.',
                                  ),
                                )
                              : ChatView(key: ValueKey(sel), chatId: sel),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _ChatList extends StatelessWidget {
  final bool group;
  final String search;
  final String? selected;
  final ValueChanged<bool> onGroup;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onOpen;
  final VoidCallback onNew;
  const _ChatList({
    required this.group,
    required this.search,
    required this.selected,
    required this.onGroup,
    required this.onSearch,
    required this.onOpen,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    final store = ChatStore.instance;
    final me = store.uid ?? '';
    final q = search.trim().toLowerCase();
    final chats = (group ? store.teamChats : store.directChats)
        .where((c) =>
            q.isEmpty ||
            store.titleOf(c).toLowerCase().contains(q) ||
            c.lastText.toLowerCase().contains(q))
        .toList();
    final unreadDirect = store.directChats.where((c) => c.unreadFor(me)).length;
    final unreadGroup = store.teamChats.where((c) => c.unreadFor(me)).length;
    Widget tab(String label, bool g, int n) => Expanded(
          child: Material(
            color: group == g ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onGroup(g),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: group == g ? Colors.white : AppColors.text)),
                  if (n > 0) ...[
                    const SizedBox(width: 6),
                    Badge(label: Text('$n')),
                  ],
                ]),
              ),
            ),
          ),
        );
    return DashCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Expanded(
              child: Text('Messages', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            IconButton.filledTonal(
              tooltip: 'New message',
              onPressed: onNew,
              icon: const Icon(Icons.edit_square, size: 20),
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: TextField(
              onChanged: onSearch,
              decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search conversations...'),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
                color: const Color(0xFFF1F3F6), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              tab('Direct', false, unreadDirect + store.incomingRequests.length),
              tab('Group', true, unreadGroup),
            ]),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                if (!group && store.incomingRequests.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
                    child: Text('Requests (${store.incomingRequests.length})',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted)),
                  ),
                  for (final r in store.incomingRequests)
                    _RequestTile(chat: r, selected: selected == r.id, onOpen: () => onOpen(r.id)),
                  const SizedBox(height: 6),
                ],
                if (chats.isEmpty && (group || store.incomingRequests.isEmpty))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Text(
                      group
                          ? 'Join or create a team to get a team chat.'
                          : 'No conversations yet. Tap the pencil to message a teammate.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                for (final c in chats)
                  _ChatTile(chat: c, selected: selected == c.id, onOpen: () => onOpen(c.id)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final Chat chat;
  final bool selected;
  final VoidCallback onOpen;
  const _ChatTile({required this.chat, required this.selected, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final store = ChatStore.instance;
    final me = store.uid ?? '';
    final title = store.titleOf(chat);
    final unread = chat.unreadFor(me);
    final team = teamOfChat(chat);
    final preview = chat.isPending && chat.createdBy == me
        ? 'Waiting for them to accept'
        : (chat.lastText.isEmpty
            ? (chat.isTeam ? 'Say hello to the team' : 'No messages yet')
            : '${chat.lastFrom == me ? 'You: ' : ''}${chat.lastText}');
    return Material(
      color: selected ? AppColors.primaryLight : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: selected
              ? const BoxDecoration(
                  border: Border(left: BorderSide(color: AppColors.primary, width: 3)))
              : null,
          child: Row(children: [
            chat.isTeam
                ? CircleAvatar(
                    radius: 22,
                    backgroundColor: Color(team?.color ?? 0xFF1F6FEB).withAlpha(30),
                    child: Icon(Icons.groups_rounded, color: Color(team?.color ?? 0xFF1F6FEB)),
                  )
                : Avatar(name: title, size: 44, color: AppColors.purple, uid: chat.otherOf(me)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: unread ? FontWeight.w800 : FontWeight.w700, fontSize: 15)),
                  ),
                  if (chat.lastAt != null)
                    Text(_time(chat.lastAt!),
                        style: TextStyle(
                            fontSize: 12, color: unread ? AppColors.primary : AppColors.textMuted)),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(
                    child: Text(preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            color: unread ? AppColors.text : AppColors.textMuted,
                            fontWeight: unread ? FontWeight.w600 : FontWeight.w400)),
                  ),
                  if (unread)
                    Container(
                      width: 10,
                      height: 10,
                      decoration:
                          const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final Chat chat;
  final bool selected;
  final VoidCallback onOpen;
  const _RequestTile({required this.chat, required this.selected, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final store = ChatStore.instance;
    final name = store.titleOf(chat);
    final teammate = chat.isTeammateRequest;
    return Material(
      color: selected ? AppColors.primaryLight : AppColors.warningLight.withAlpha(150),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Avatar(name: name, size: 40, color: AppColors.warning, uid: chat.createdBy),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                    teammate && chat.lastText.isNotEmpty
                        ? chat.lastText
                        : 'Wants to send you messages',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              ]),
            ),
            IconButton(
              tooltip: teammate ? 'Block' : 'Decline',
              onPressed: () => teammate ? store.block(chat) : store.decline(chat),
              icon: Icon(teammate ? Icons.block_rounded : Icons.close_rounded,
                  color: AppColors.danger),
            ),
            IconButton.filled(
              tooltip: teammate ? 'Approve' : 'Accept',
              onPressed: () {
                store.accept(chat);
                onOpen();
              },
              icon: const Icon(Icons.check_rounded),
            ),
          ]),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- chat

/// A chat on its own page (phone).
class ChatPage extends StatelessWidget {
  final String chatId;
  const ChatPage({super.key, required this.chatId});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(child: ChatView(chatId: chatId, showBack: true)),
      );
}

class ChatView extends StatefulWidget {
  final String chatId;
  final bool showBack;
  const ChatView({super.key, required this.chatId, this.showBack = false});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final List<TaskLink> _links = [];
  TaskRef? _task;
  late final Stream<List<ChatMessage>> _stream = ChatStore.instance.messagesOf(widget.chatId);

  @override
  void initState() {
    super.initState();
    ChatStore.instance.openChatId = widget.chatId;
  }

  @override
  void dispose() {
    if (ChatStore.instance.openChatId == widget.chatId) ChatStore.instance.openChatId = null;
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send(Chat chat) {
    final t = _task;
    ChatStore.instance
        .send(chat, _text.text, links: [..._links], task: t?.task, taskTeamId: t?.team?.id);
    setState(() {
      _text.clear();
      _links.clear();
      _task = null;
    });
    _focus.requestFocus();
  }

  Future<void> _attach(Chat chat) async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Send a photo'),
            subtitle: const Text('Screenshot, design, a picture of the work...'),
            onTap: () => Navigator.pop(ctx, 'photo'),
          ),
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: const Text('Add a link'),
            subtitle: const Text('Google Drive, Sheets, Figma, a website...'),
            onTap: () => Navigator.pop(ctx, 'link'),
          ),
          ListTile(
            leading: const Icon(Icons.task_alt_rounded),
            title: const Text('Share a task'),
            onTap: () => Navigator.pop(ctx, 'task'),
          ),
        ]),
      ),
    );
    if (!mounted || pick == null) return;
    if (pick == 'photo') {
      final url = await pickAndUploadImage(context);
      if (url == null || !mounted) return;
      final c = ChatStore.instance.byId(widget.chatId) ?? chat;
      ChatStore.instance.send(c, _text.text, links: [TaskLink(title: 'Photo', url: url)]);
      setState(_text.clear);
    } else if (pick == 'link') {
      final l = await linkDialog(context);
      if (l != null) setState(() => _links.add(l));
    } else {
      final tasks = [
        for (final r in TaskRepository.myTasks())
          if (!r.task.isCancelled && (!chat.isTeam || r.team?.id == chat.teamId)) r
      ];
      if (!mounted) return;
      if (tasks.isEmpty) {
        showSnack(context, 'No tasks to share.');
        return;
      }
      final r = await showDialog<TaskRef>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Share a task'),
          children: [
            for (final r in tasks.take(30))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, r),
                child: Text('${r.task.title}  •  ${r.sourceLabel}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      );
      if (r != null) setState(() => _task = r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ChatStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([store, TeamStore.instance]),
      builder: (context, _) {
        final chat = store.byId(widget.chatId);
        if (chat == null) {
          return const Center(
              child: EmptyState(
                  icon: Icons.forum_outlined,
                  title: 'Chat not found',
                  subtitle: 'It may have been deleted.'));
        }
        final me = store.uid ?? '';
        // An email request: they can't read it until they accept.
        final incoming = chat.isPending && chat.createdBy != me && !chat.isTeammateRequest;
        if (chat.unreadFor(me)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => store.markRead(chat));
        }
        final title = store.titleOf(chat);
        final team = teamOfChat(chat);
        final header = Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration:
              const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
          child: Row(children: [
            if (widget.showBack) const BackButton(),
            chat.isTeam
                ? CircleAvatar(
                    radius: 22,
                    backgroundColor: Color(team?.color ?? 0xFF1F6FEB).withAlpha(30),
                    child: Icon(Icons.groups_rounded, color: Color(team?.color ?? 0xFF1F6FEB)),
                  )
                : Avatar(name: title, size: 44, color: AppColors.purple, uid: chat.otherOf(me)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text(store.subtitleOf(chat),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              ]),
            ),
            if (!chat.isTeam && !(chat.isBlocked && chat.blockedBy != me))
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (a) async {
                  switch (a) {
                    case 'block':
                      final ok = await confirmDialog(context,
                          title: 'Block $title?',
                          message: 'They can\'t message you until you unblock them.',
                          confirmLabel: 'Block',
                          danger: true);
                      if (ok) store.block(chat);
                    case 'unblock':
                      store.unblock(chat);
                    case 'delete':
                      final ok = await confirmDialog(context,
                          title: 'Delete this chat?',
                          message: 'The conversation is removed for both of you.',
                          confirmLabel: 'Delete',
                          danger: true);
                      if (ok) store.decline(chat);
                  }
                },
                itemBuilder: (_) => [
                  if (chat.inviteEmail == null && chat.status == 'active')
                    const PopupMenuItem(value: 'block', child: Text('Block')),
                  if (chat.isBlocked) const PopupMenuItem(value: 'unblock', child: Text('Unblock')),
                  if (!chat.isBlocked)
                    const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete chat', style: TextStyle(color: AppColors.danger))),
                ],
              ),
          ]),
        );

        final body = incoming
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Avatar(name: title, size: 64, color: AppColors.warning),
                    const SizedBox(height: 12),
                    Text('$title wants to chat with you',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text('Accept to see their messages and reply.',
                        style: TextStyle(color: AppColors.textMuted)),
                    const SizedBox(height: 16),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      OutlinedButton(
                          onPressed: () => store.decline(chat), child: const Text('Decline')),
                      const SizedBox(width: 10),
                      FilledButton(
                          onPressed: () => store.accept(chat), child: const Text('Accept')),
                    ]),
                  ]),
                ),
              )
            : StreamBuilder<List<ChatMessage>>(
                stream: _stream,
                builder: (context, snap) {
                  final msgs = snap.data ?? const <ChatMessage>[];
                  if (msgs.isEmpty) {
                    return Center(
                      child: Text(
                        chat.isPending
                            ? 'Write your first message. $title gets it with your request.'
                            : 'No messages yet. Say hello!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    );
                  }
                  final other = chat.isTeam ? null : chat.otherOf(me);
                  final seenAt = other == null ? 0 : (chat.read[other] ?? 0);
                  final lastMine = msgs.lastWhere((m) => m.from == me,
                      orElse: () => ChatMessage(
                          id: '', from: '', fromName: '', text: '', at: DateTime(2000)));
                  final items = <Widget>[];
                  DateTime? day;
                  for (final (i, m) in msgs.indexed) {
                    if (day == null || !isSameDay(day, m.at)) {
                      day = m.at;
                      items.add(_DayChip(day: m.at));
                    }
                    final prev = i > 0 ? msgs[i - 1] : null;
                    final grouped = prev != null &&
                        prev.from == m.from &&
                        isSameDay(prev.at, m.at) &&
                        m.at.difference(prev.at).inMinutes < 5;
                    items.add(_Bubble(
                      msg: m,
                      chat: chat,
                      mine: m.from == me,
                      grouped: grouped,
                      seen: m.id == lastMine.id &&
                          other != null &&
                          seenAt >= m.at.millisecondsSinceEpoch,
                    ));
                  }
                  return ListView(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    children: items.reversed.toList(),
                  );
                },
              );

        final pending = [
          for (final l in _links)
            InputChip(
              avatar: const Icon(Icons.link_rounded, size: 16),
              label: Text(l.label, overflow: TextOverflow.ellipsis),
              onDeleted: () => setState(() => _links.remove(l)),
            ),
          if (_task != null)
            InputChip(
              avatar: const Icon(Icons.task_alt_rounded, size: 16),
              label: Text(_task!.task.title, overflow: TextOverflow.ellipsis),
              onDeleted: () => setState(() => _task = null),
            ),
        ];
        Widget bar(IconData icon, String text, List<Widget> actions) => Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              decoration: const BoxDecoration(
                  color: AppColors.background,
                  border: Border(top: BorderSide(color: AppColors.border))),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 20, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Flexible(child: Text(text, style: const TextStyle(color: AppColors.text))),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final (i, a) in actions.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      a,
                    ],
                  ]),
                ],
              ),
            );
        final Widget? stop = chat.isTeammateRequest && chat.createdBy != me
            ? bar(Icons.mark_chat_unread_outlined,
                '$title wants to send you messages. Approve to reply.', [
                OutlinedButton(
                    onPressed: () => store.block(chat),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('Block')),
                FilledButton(onPressed: () => store.accept(chat), child: const Text('Approve')),
              ])
            : chat.isBlocked
                ? (chat.blockedBy == me
                    ? bar(Icons.block_rounded, 'You blocked $title.', [
                        OutlinedButton(
                            onPressed: () => store.unblock(chat), child: const Text('Unblock')),
                      ])
                    : bar(Icons.block_rounded, "You can't message $title.", const []))
                : !store.canSend(chat)
                    ? bar(Icons.hourglass_top_rounded, 'Waiting for $title to accept your request.',
                        const [])
                    : null;
        final composer = incoming
            ? const SizedBox.shrink()
            : stop ??
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  decoration:
                      const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (pending.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Wrap(spacing: 6, runSpacing: 6, children: pending),
                        ),
                      ),
                    Row(children: [
                      IconButton(
                        tooltip: 'Attach a link or task',
                        onPressed: () => _attach(chat),
                        icon: const Icon(Icons.attach_file_rounded),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _text,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(chat),
                          decoration:
                              const InputDecoration(isDense: true, hintText: 'Type a message...'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _send(chat),
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                        child: const Text('Send'),
                      ),
                    ]),
                  ]),
                );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [header, Expanded(child: body), composer],
        );
      },
    );
  }
}

class _DayChip extends StatelessWidget {
  final DateTime day;
  const _DayChip({required this.day});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label = isSameDay(day, now)
        ? 'Today'
        : isSameDay(day, now.subtract(const Duration(days: 1)))
            ? 'Yesterday'
            : DateFormat('EEE, d MMM').format(day);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration:
            BoxDecoration(color: const Color(0xFFF1F3F6), borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  final Chat chat;
  final bool mine;
  final bool grouped;
  final bool seen;
  const _Bubble(
      {required this.msg,
      required this.chat,
      required this.mine,
      required this.grouped,
      required this.seen});

  TaskRef? _taskRef() {
    final id = msg.taskId;
    if (id == null) return null;
    final teamId = msg.taskTeamId;
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
    final name = mine ? 'You' : (msg.fromName.isEmpty ? 'Member' : msg.fromName);
    final ref = _taskRef();
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (msg.text.isNotEmpty)
          SelectableText(msg.text, style: const TextStyle(fontSize: 14.5, height: 1.35)),
        for (final l in msg.links.where((l) => isImageUrl(l.url)))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => openImage(context, l.url),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260, maxHeight: 260),
                child: NetImage(thumbUrl(l.url, width: 600), fit: BoxFit.cover),
              ),
            ),
          ),
        for (final l in msg.links.where((l) => !isImageUrl(l.url)))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: InkWell(
              onTap: () => launchUrl(Uri.parse(l.url), mode: LaunchMode.externalApplication)
                  .catchError((_) => false),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration:
                    BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.link_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(l.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ),
          ),
        if (msg.taskId != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: InkWell(
              onTap: ref == null ? null : () => openTaskRef(context, ref),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration:
                    BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.task_alt_rounded, color: AppColors.purple, size: 22),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(msg.taskTitle ?? 'Task',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                          ref == null
                              ? 'Not available to you'
                              : '${ref.sourceLabel} • due ${DateFormat('d MMM').format(ref.task.startAt)}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ]),
                  ),
                  if (ref != null) const Icon(Icons.chevron_right_rounded),
                ]),
              ),
            ),
          ),
      ],
    );
    final bubble = GestureDetector(
      onLongPress: mine
          ? () async {
              final ok = await confirmDialog(context,
                  title: 'Delete message?',
                  message: 'It is removed for everyone.',
                  confirmLabel: 'Delete',
                  danger: true);
              if (ok) ChatStore.instance.deleteMessage(chat, msg);
            }
          : null,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? AppColors.primaryLight : const Color(0xFFF1F3F6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: content,
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: grouped ? 3 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!mine) ...[
            SizedBox(
                width: 36,
                child: grouped
                    ? null
                    : Avatar(name: name, size: 34, color: AppColors.purple, uid: msg.from)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!grouped)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(
                          text: name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      TextSpan(
                          text: '  ${DateFormat('h:mm a').format(msg.at)}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ])),
                  ),
                bubble,
                if (seen)
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child:
                        Text('Seen', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
