import 'package:flutter/material.dart';
import '../widgets/images.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/activity.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../data/team_store.dart';
import 'work_hours.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import '../widgets/responsive.dart';
import 'notifications_screen.dart';
import 'main_shell.dart';
import 'projects_screen.dart';

part 'profile_page.dart';

/// Profile: who I am, my numbers, settings, preferences, account security
/// and my recent activity. Phones get one column, laptops the dashboard
/// layout.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([store, TeamStore.instance]),
        builder: (context, _) {
          final user = store.currentUser;
          if (user == null) return const SizedBox.shrink();
          final data = _ProfileData.build();
          return _ProfilePage(data: data, wide: isWideScreen(context));
        },
      ),
    );
  }
}

void _push(BuildContext context, Widget w) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => w));

/// Everything the profile shows, computed once per build.
class _ProfileData {
  final AppUser user;
  final int total;
  final int done;
  final int pending;
  final int overdue;
  final int teams;

  /// Owner / Manager / Member, or null if in no team.
  final String? role;
  final List<ActivityItem> activity;

  _ProfileData(this.user, this.total, this.done, this.pending, this.overdue, this.teams, this.role,
      this.activity);

  factory _ProfileData.build() {
    final store = AppStore.instance;
    final ts = TeamStore.instance;
    final me = ts.uid ?? store.currentUser!.id;
    final all = [
      ...store.tasks.where((t) => !t.isCancelled),
      ...ts.myTeamTasks,
    ];
    final done = all.where((t) => t.isCompleted).length;
    final overdue = all.where((t) => t.isOverdue).length;
    String? role;
    if (ts.teams.any((t) => t.ownerId == me)) {
      role = 'Owner';
    } else if (ts.teams.any((t) => t.managerIds.contains(me))) {
      role = 'Manager';
    } else if (ts.teams.isNotEmpty) {
      role = 'Member';
    }

    // My own actions: personal tasks I finished + what I did in teams.
    final mine = <ActivityItem>[
      for (final t in store.tasks)
        if (t.isCompleted && t.completedAt != null)
          ActivityItem(
            kind: ActivityKind.completed,
            at: t.completedAt!,
            actor: 'You',
            verb: 'completed',
            object: t.title,
            teamId: '',
          ),
      ...recentActivity(
        teams: ts.teams,
        tasksOf: ts.tasksOf,
        invitesOf: (id) => ts.sentInvites[id] ?? const [],
        me: me,
        limit: 50,
      ).where((a) =>
          a.actor == 'You' ||
          (a.kind == ActivityKind.teamCreated && ts.teamById(a.teamId)?.ownerId == me)),
    ]..sort((a, b) => b.at.compareTo(a.at));

    return _ProfileData(store.currentUser!, all.length, done, all.length - done, overdue,
        ts.teams.length, role, mine.take(6).toList());
  }
}

String _agoText(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return '1 day ago';
  return '${diff.inDays} days ago';
}

Future<void> _logout(BuildContext context) async {
  final ok = await confirmDialog(context,
      title: 'Logout?',
      message: 'Your data is saved in your account. Log in again (on any phone) to see it.',
      confirmLabel: 'Logout',
      danger: true);
  if (ok) await AppStore.instance.logout();
}

void _showAbout(BuildContext context) => showAboutDialog(
      context: context,
      applicationName: 'TaskFlow',
      applicationVersion: '1.1.0',
      applicationIcon: const AppLogo(size: 44),
      children: const [
        Text('Task manager with teams and cloud sync. Your data is saved to your '
            'account (Firebase) and also kept on the device, so the app works '
            'offline and syncs when internet is back.'),
      ],
    );

Future<void> _verifyEmail(BuildContext context) async {
  final store = AppStore.instance;
  await store.refreshAccount();
  if (!context.mounted || store.emailVerified) return;
  final send = await confirmDialog(context,
      title: 'Verify your email',
      message: 'We will send a link to ${store.currentUser?.email}. Open it, then come back here. '
          'A verified email is needed to accept team invitations.',
      confirmLabel: 'Send link');
  if (!send || !context.mounted) return;
  final err = await TeamStore.instance.sendVerificationEmail();
  if (context.mounted) showSnack(context, err ?? 'Link sent. Check your inbox (and spam).');
}

/// Small coloured chip with an icon (header badges).
class _Badge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Badge({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withAlpha(24),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12.5)),
          ],
        ),
      );
}

class _ActivityTile extends StatelessWidget {
  final ActivityItem item;
  const _ActivityTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final (icon, color, title) = switch (item.kind) {
      ActivityKind.completed => (Icons.check_circle_rounded, AppColors.success, 'Completed a task'),
      ActivityKind.assigned => (
          Icons.assignment_ind_outlined,
          AppColors.primary,
          'Assigned a task'
        ),
      ActivityKind.invited => (Icons.person_add_alt_1_rounded, AppColors.purple, 'Invited someone'),
      ActivityKind.teamCreated => (Icons.groups_rounded, AppColors.purple, 'Created a new team'),
    };
    final detail = switch (item.kind) {
      ActivityKind.completed => 'You marked "${item.object}" as done',
      ActivityKind.assigned => 'You assigned "${item.object}"${item.suffix}',
      ActivityKind.invited => 'You invited ${item.object}${item.suffix}',
      ActivityKind.teamCreated => 'You created the "${item.object}" team',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: color.withAlpha(28),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(_agoText(item.at),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// A "label .... value >" line in the Preferences / Security cards.
class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget value;
  final VoidCallback? onTap;
  const _InfoLine({required this.icon, required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 21, color: AppColors.text),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5))),
              const SizedBox(width: 8),
              Flexible(child: value),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              ],
            ],
          ),
        ),
      );
}

Widget _valueText(String text, {Color? color, bool pill = false}) => pill
    ? Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (color ?? AppColors.primary).withAlpha(24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: TextStyle(
                color: color ?? AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
      )
    : Text(text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: TextStyle(color: color ?? AppColors.textMuted, fontSize: 13.5));

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _CardTitle({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primaryLight,
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      );
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard();

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final methods = store.signInMethods;
    final google = methods.contains('google.com');
    final password = methods.contains('password');
    final method = [if (google) 'Google', if (password) 'Email & password'].join(' + ');
    final backup = store.lastBackupAt;
    return DashCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 8),
      child: Column(
        children: [
          const _CardTitle(
              icon: Icons.shield_outlined,
              title: 'Security & account',
              subtitle: 'Keep your account secure'),
          const SizedBox(height: 8),
          _InfoLine(
            icon: Icons.login_rounded,
            label: 'Login method',
            value: _valueText(method.isEmpty ? '—' : method),
          ),
          _InfoLine(
            icon: Icons.lock_outline_rounded,
            label: 'Password',
            value: _valueText(password ? 'Change' : 'Managed by Google'),
            onTap: password ? () => _push(context, const AccountScreen()) : null,
          ),
          _InfoLine(
            icon: Icons.mark_email_read_outlined,
            label: 'Email verification',
            value: store.emailVerified
                ? _valueText('Verified', color: AppColors.success, pill: true)
                : _valueText('Not verified', color: AppColors.warning, pill: true),
            onTap: store.emailVerified ? null : () => _verifyEmail(context),
          ),
          _InfoLine(
            icon: Icons.cloud_done_outlined,
            label: 'Cloud sync',
            value: _valueText('On', color: AppColors.success, pill: true),
          ),
          _InfoLine(
            icon: Icons.backup_outlined,
            label: 'Backup copy',
            value: _valueText(backup == null ? 'Never' : 'Last ${_agoText(backup)}'),
            onTap: () => _push(context, const SettingsScreen()),
          ),
        ],
      ),
    );
  }
}

Widget _logoutButton(BuildContext context) => SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: () => _logout(context),
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Logout'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          side: const BorderSide(color: Color(0xFFFCA5A5)),
          backgroundColor: const Color(0xFFFFF5F5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );

// ================================================================= phone

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _title;
  late final TextEditingController _email;
  final _password = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final u = AppStore.instance.currentUser!;
    _name = TextEditingController(text: u.name);
    _title = TextEditingController(text: AppStore.instance.jobTitle);
    _email = TextEditingController(text: u.email);
  }

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final store = AppStore.instance;
    final user = store.currentUser!;
    final emailChanged = _email.text.trim().toLowerCase() != user.email.toLowerCase();
    final passwordChanged = _password.text.isNotEmpty;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final notes = <String>[];

    await store.updateName(_name.text);
    if (_title.text.trim() != store.jobTitle) store.updateJobTitle(_title.text);
    if (passwordChanged) {
      final err = await store.changePassword(_password.text);
      notes.add(err ?? 'Password changed.');
    }
    if (emailChanged) {
      final err = await store.changeEmail(_email.text);
      notes.add(
          err ?? 'We sent a link to ${_email.text.trim()}. Your email changes after you open it.');
    }
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text(notes.isEmpty ? 'Profile updated' : notes.join('\n')),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: notes.isEmpty ? 3 : 6),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final user = AppStore.instance.currentUser!;
    return Scaffold(
      appBar: AppBar(title: const Text('Account Info')),
      body: CenteredContent(
          maxWidth: 640,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Center(child: EditableAvatar(size: 80)),
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
                  inputFormatters: [LengthLimitingTextInputFormatter(100)],
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your name' : null,
                ),
                const SizedBox(height: 16),
                const Text('Job title', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _title,
                  textCapitalization: TextCapitalization.words,
                  decoration: fieldDecoration('e.g. CEO, SEO lead (optional)'),
                  inputFormatters: [LengthLimitingTextInputFormatter(60)],
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
                  validator: (v) =>
                      (v != null && v.isNotEmpty && v.length < 6) ? 'At least 6 characters' : null,
                ),
                const SizedBox(height: 28),
                PrimaryButton(label: 'Save changes', loading: _saving, onPressed: _save),
              ],
            ),
          )),
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
    int color = existing?.color ?? kPaletteColors[store.categories.length % kPaletteColors.length];
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
                inputFormatters: [LengthLimitingTextInputFormatter(100)],
              ),
              const SizedBox(height: 16),
              ColorPickerRow(selected: color, onChanged: (c) => setLocal(() => color = c)),
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
                          decoration: BoxDecoration(color: Color(c.color), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                            child:
                                Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        Text('${store.tasks.where((t) => t.categoryId == c.id).length} tasks',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                        IconButton(
                          icon:
                              const Icon(Icons.delete_outline_rounded, color: AppColors.textMuted),
                          onPressed: () async {
                            final ok = await confirmDialog(context,
                                title: 'Delete category?',
                                message: 'Tasks in "${c.name}" will stay, without a category.',
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
                  'For now members are just names you can assign tasks to. Later '
                  'they can become real accounts that '
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
                              Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                  '${store.tasks.where((t) => t.assigneeId == m.id && !t.isCancelled).length} assigned tasks',
                                  style:
                                      const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon:
                              const Icon(Icons.delete_outline_rounded, color: AppColors.textMuted),
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
    AppStore.instance.markBackupCopied();
    if (context.mounted) {
      showSnack(
          context, 'Backup copied. Paste it somewhere safe (e.g. WhatsApp to yourself, Notes).');
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
              'Paste the backup text below. Its tasks and projects will be added to your account.',
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
              child: const Text('Restore', style: TextStyle(color: AppColors.danger))),
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
        message: 'All your tasks, projects, categories, members and notifications will be '
            'permanently deleted from your account. Your login stays. Make a backup first if you need it.',
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
                      Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
                      const SizedBox(height: 2),
                      Text(sub, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
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
                Icon(Icons.cloud_done_rounded, color: AppColors.primary),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Storage: your account in the cloud (Firebase), with an offline '
                    'copy on this phone. Log in on any phone to see your data.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          tile(Icons.copy_all_rounded, 'Copy backup', 'Copies all data as text to the clipboard',
              () => _copyBackup(context)),
          tile(Icons.restore_rounded, 'Restore backup',
              'Paste a backup to add its data to your account', () => _restore(context)),
          tile(Icons.delete_forever_rounded, 'Reset all data', 'Delete all your tasks and projects',
              () => _reset(context),
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
      'In your account in the cloud (Google Firebase), plus an offline copy on the phone.'
    ],
    [
      'Can I use my account on another phone?',
      'Yes. Just log in with the same email and password on the other phone.'
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
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    expandedAlignment: Alignment.centerLeft,
                    children: [
                      Text(q[1], style: const TextStyle(color: AppColors.textMuted, height: 1.45)),
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
