import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../widgets/common.dart';
import 'notifications_screen.dart';
import 'projects_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return SafeArea(
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final user = store.currentUser;
          if (user == null) return const SizedBox.shrink();
          void push(Widget w) =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => w));

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            children: [
              // ---------------------------------------------------- header
              Row(
                children: [
                  Avatar(name: user.name, size: 64),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name,
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(user.email,
                            style: const TextStyle(color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: AppColors.textMuted),
                    onPressed: () => push(const AccountScreen()),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ----------------------------------------------------- stats
              WhiteCard(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    _stat('${store.totalCount}', 'Total Tasks'),
                    _divider(),
                    _stat('${store.doneCount}', 'Done'),
                    _divider(),
                    _stat('${store.pendingCount}', 'Pending'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ------------------------------------------------------ menu
              _MenuTile(
                icon: Icons.person_outline_rounded,
                label: 'Account Info',
                onTap: () => push(const AccountScreen()),
              ),
              _MenuTile(
                icon: Icons.notifications_none_rounded,
                label: 'Notifications',
                badge: store.unreadCount,
                onTap: () => push(const NotificationsScreen()),
              ),
              _MenuTile(
                icon: Icons.folder_outlined,
                label: 'Projects',
                onTap: () => push(const ProjectsScreen()),
              ),
              _MenuTile(
                icon: Icons.label_outline_rounded,
                label: 'Categories',
                onTap: () => push(const CategoriesScreen()),
              ),
              _MenuTile(
                icon: Icons.group_outlined,
                label: 'Team Members',
                onTap: () => push(const MembersScreen()),
              ),
              _MenuTile(
                icon: Icons.settings_outlined,
                label: 'Settings & Backup',
                onTap: () => push(const SettingsScreen()),
              ),
              _MenuTile(
                icon: Icons.help_outline_rounded,
                label: 'Help & FAQ',
                onTap: () => push(const HelpScreen()),
              ),
              _MenuTile(
                icon: Icons.info_outline_rounded,
                label: 'About',
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'TaskFlow',
                  applicationVersion: '1.0.0 (offline)',
                  applicationIcon: const AppLogo(size: 44),
                  children: const [
                    Text('Offline-first task manager. All data is stored on this '
                        'phone in a local SQLite database. Cloud sync and multi-device '
                        'login will come in a later version.'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await confirmDialog(context,
                        title: 'Logout?',
                        message: 'Your data stays on this phone. Log in again to see it.',
                        confirmLabel: 'Logout',
                        danger: true);
                    if (ok) await store.logout();
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Logout'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      );

  Widget _divider() =>
      Container(width: 1, height: 32, color: AppColors.border);
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int badge;
  final VoidCallback onTap;
  const _MenuTile(
      {required this.icon, required this.label, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: WhiteCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.text, size: 22),
            const SizedBox(width: 14),
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500))),
            if (badge > 0)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.danger, borderRadius: BorderRadius.circular(10)),
                child: Text('$badge',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ============================================================ Account

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  final _password = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final u = AppStore.instance.currentUser!;
    _name = TextEditingController(text: u.name);
    _email = TextEditingController(text: u.email);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final store = AppStore.instance;
    final user = store.currentUser!;
    final emailChanged = _email.text.trim().toLowerCase() != user.email;
    final passwordChanged = _password.text.isNotEmpty;
    if (emailChanged && !passwordChanged) {
      showSnack(context, 'Please also enter a new password when changing email.');
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    if (emailChanged || passwordChanged) {
      await store.changeEmailAndPassword(_name.text, _email.text, _password.text);
    } else {
      await store.updateProfile(_name.text, user.email);
    }
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(
        content: Text('Profile updated'), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final user = AppStore.instance.currentUser!;
    return Scaffold(
      appBar: AppBar(title: const Text('Account Info')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(child: Avatar(name: user.name, size: 80)),
            const SizedBox(height: 8),
            Center(
              child: Text('Member since ${formatShortDate(user.createdAt)}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            ),
            const SizedBox(height: 24),
            const Text('Full name', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: fieldDecoration('Full name'),
              validator: (v) =>
                  (v == null || v.trim().length < 2) ? 'Enter your name' : null,
            ),
            const SizedBox(height: 16),
            const Text('Email', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: fieldDecoration('Email'),
              validator: (v) => (v == null || !v.contains('@') || !v.contains('.'))
                  ? 'Enter a valid email'
                  : null,
            ),
            const SizedBox(height: 16),
            const Text('New password', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: fieldDecoration('Leave empty to keep current password'),
              validator: (v) => (v != null && v.isNotEmpty && v.length < 6)
                  ? 'At least 6 characters'
                  : null,
            ),
            const SizedBox(height: 28),
            PrimaryButton(label: 'Save changes', loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

// ========================================================= Categories

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  Future<void> _edit(BuildContext context, {String? id}) async {
    final store = AppStore.instance;
    final existing = store.categoryById(id);
    final name = TextEditingController(text: existing?.name ?? '');
    int color = existing?.color ??
        kPaletteColors[store.categories.length % kPaletteColors.length];
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'New category' : 'Edit category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: fieldDecoration('Category name'),
              ),
              const SizedBox(height: 16),
              ColorPickerRow(
                  selected: color, onChanged: (c) => setLocal(() => color = c)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                final n = name.text.trim();
                if (n.isEmpty) return;
                if (existing == null) {
                  await store.addCategory(n, color);
                } else {
                  existing.name = n;
                  existing.color = color;
                  await store.updateCategory(existing);
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

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (store.categories.isEmpty) {
            return const EmptyState(
                icon: Icons.label_outline_rounded,
                title: 'No categories',
                subtitle: 'Tap + to add one.');
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
            children: [
              for (final c in store.categories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: WhiteCard(
                    onTap: () => _edit(context, id: c.id),
                    child: Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                              color: Color(c.color), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Text(c.name,
                                style: const TextStyle(fontWeight: FontWeight.w600))),
                        Text(
                            '${store.tasks.where((t) => t.categoryId == c.id).length} tasks',
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 12.5)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: AppColors.textMuted),
                          onPressed: () async {
                            final ok = await confirmDialog(context,
                                title: 'Delete category?',
                                message:
                                    'Tasks in "${c.name}" will stay, without a category.',
                                confirmLabel: 'Delete',
                                danger: true);
                            if (ok) await store.deleteCategory(c);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================ Members

class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Team Members')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final name = await textInputDialog(context,
              title: 'Add team member', hint: 'Member name', okLabel: 'Add');
          if (name != null) await store.addMember(name);
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add_alt_1_rounded),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Text(
                  'In this offline version members are just names you can assign '
                  'tasks to. In the cloud version they will be real accounts that '
                  'get notified on their own phone.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
                ),
              ),
              if (store.members.isEmpty)
                const EmptyState(
                    icon: Icons.group_outlined,
                    title: 'No team members',
                    subtitle: 'Tap + to add someone.'),
              for (final m in store.members)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: WhiteCard(
                    child: Row(
                      children: [
                        Avatar(name: m.name, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                  '${store.tasks.where((t) => t.assigneeId == m.id && !t.isCancelled).length} assigned tasks',
                                  style: const TextStyle(
                                      color: AppColors.textMuted, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: AppColors.textMuted),
                          onPressed: () async {
                            final ok = await confirmDialog(context,
                                title: 'Remove member?',
                                message: 'Their tasks will become unassigned.',
                                confirmLabel: 'Remove',
                                danger: true);
                            if (ok) await store.deleteMember(m);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// =========================================================== Settings

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _copyBackup(BuildContext context) async {
    final json = await AppStore.instance.exportBackup();
    await Clipboard.setData(ClipboardData(text: json));
    if (context.mounted) {
      showSnack(context,
          'Backup copied. Paste it somewhere safe (e.g. WhatsApp to yourself, Notes).');
    }
  }

  Future<void> _restore(BuildContext context) async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Paste the backup text below. This will REPLACE all data on this phone.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 6,
              decoration: fieldDecoration('Paste backup here'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) ctrl.text = data!.text!;
                },
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: const Text('Paste'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Restore',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    final err = await AppStore.instance.importBackup(text);
    if (!context.mounted) return;
    showSnack(context, err ?? 'Backup restored');
    if (err == null && AppStore.instance.currentUser == null) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _reset(BuildContext context) async {
    final ok = await confirmDialog(context,
        title: 'Reset all data?',
        message:
            'Your account, tasks, projects and everything else will be permanently '
            'deleted from this phone. Make a backup first if you need it.',
        confirmLabel: 'Delete everything',
        danger: true);
    if (!ok) return;
    await AppStore.instance.resetAllData();
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String title, String sub, VoidCallback onTap,
            {Color color = AppColors.text}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: WhiteCard(
            onTap: onTap,
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(fontWeight: FontWeight.w600, color: color)),
                      const SizedBox(height: 2),
                      Text(sub,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings & Backup')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          WhiteCard(
            child: const Row(
              children: [
                Icon(Icons.phone_android_rounded, color: AppColors.primary),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Storage: this phone only (offline). If the app is uninstalled, '
                    'data is lost, so keep a backup.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          tile(Icons.copy_all_rounded, 'Copy backup',
              'Copies all data as text to the clipboard', () => _copyBackup(context)),
          tile(Icons.restore_rounded, 'Restore backup',
              'Paste a backup to replace current data', () => _restore(context)),
          tile(Icons.delete_forever_rounded, 'Reset all data',
              'Delete everything on this phone', () => _reset(context),
              color: AppColors.danger),
        ],
      ),
    );
  }
}

// =============================================================== Help

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faq = [
    ['How do I add a task?', 'Tap the blue + button at the bottom of the screen.'],
    [
      'How do I complete a task?',
      'Tap the circle next to a task, or open it and press "Mark as Done".'
    ],
    [
      'What does the purple icon mean?',
      'The task is in progress: some of its checklist items are done.'
    ],
    [
      'Where is my data saved?',
      'Only on this phone, in a local database. Nothing is uploaded.'
    ],
    [
      'Can I use my account on another phone?',
      'Not yet. Use Settings > Copy backup, then Restore backup on the other phone. '
          'Real cloud login is planned for the next version.'
    ],
    [
      'Do I get reminders?',
      'While the app is open you get an in-app reminder 15 minutes before a task. '
          'Phone notifications when the app is closed are planned for a later version.'
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & FAQ')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final q in _faq)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: WhiteCard(
                padding: EdgeInsets.zero,
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: Text(q[0],
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14.5)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    expandedAlignment: Alignment.centerLeft,
                    children: [
                      Text(q[1],
                          style: const TextStyle(
                              color: AppColors.textMuted, height: 1.45)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
