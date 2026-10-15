import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/activity.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import '../widgets/responsive.dart';
import 'notifications_screen.dart';
import 'projects_screen.dart';

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
          return isWideScreen(context) ? _ProfileWide(data: data) : _ProfilePhone(data: data);
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

Future<void> _pickReminder(BuildContext context) async {
  final store = AppStore.instance;
  final picked = await showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Remind me before a task'),
      children: [
        for (final m in const [0, 5, 15, 30, 60])
          ListTile(
            title: Text(m == 0 ? 'No reminders' : '$m minutes before'),
            trailing: store.reminderMinutes == m
                ? const Icon(Icons.check_rounded, color: AppColors.primary)
                : null,
            onTap: () => Navigator.pop(ctx, m),
          ),
      ],
    ),
  );
  if (picked != null) store.setReminderMinutes(picked);
}

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

List<Widget> _badges(BuildContext context, _ProfileData d) {
  final store = AppStore.instance;
  return [
    if (store.jobTitle.isNotEmpty)
      _Badge(icon: Icons.work_outline_rounded, text: store.jobTitle, color: AppColors.primary)
    else
      InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _push(context, const AccountScreen()),
        child: const _Badge(
            icon: Icons.add_rounded, text: 'Add job title', color: AppColors.textMuted),
      ),
    if (d.role != null)
      _Badge(
          icon: d.role == 'Owner'
              ? Icons.workspace_premium_rounded
              : (d.role == 'Manager' ? Icons.manage_accounts_rounded : Icons.person_rounded),
          text: d.role == 'Member' ? 'Team member' : 'Team ${d.role}',
          color: d.role == 'Owner' ? AppColors.warning : AppColors.purple),
    _Badge(
        icon: Icons.calendar_month_rounded,
        text: 'Member since ${DateFormat('MMM yyyy').format(d.user.createdAt)}',
        color: AppColors.success),
  ];
}

/// One settings shortcut (icon, title, description).
class _QuickItem {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final void Function(BuildContext) onTap;
  final int badge;
  const _QuickItem(this.icon, this.color, this.title, this.subtitle, this.onTap, {this.badge = 0});
}

List<_QuickItem> _quickItems() => [
      _QuickItem(Icons.person_outline_rounded, AppColors.primary, 'Account Info',
          'Name, job title, email and password', (c) => _push(c, const AccountScreen())),
      _QuickItem(Icons.notifications_none_rounded, AppColors.purple, 'Notifications',
          'Your inbox of reminders and updates', (c) => _push(c, const NotificationsScreen()),
          badge: AppStore.instance.unreadCount),
      _QuickItem(Icons.folder_outlined, AppColors.warning, 'Projects',
          'View and manage your projects', (c) => _push(c, const ProjectsScreen())),
      _QuickItem(Icons.label_outline_rounded, const Color(0xFFF97316), 'Categories',
          'Organize your task categories', (c) => _push(c, const CategoriesScreen())),
      _QuickItem(Icons.settings_outlined, AppColors.primary, 'Settings & Backup',
          'Backup, restore and reset data', (c) => _push(c, const SettingsScreen())),
      _QuickItem(Icons.help_outline_rounded, AppColors.success, 'Help & FAQ', 'How TaskFlow works',
          (c) => _push(c, const HelpScreen())),
      _QuickItem(Icons.info_outline_rounded, AppColors.textMuted, 'About', 'Version and app info',
          _showAbout),
    ];

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

class _PreferencesCard extends StatelessWidget {
  const _PreferencesCard();

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final mins = store.reminderMinutes;
    return DashCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 8),
      child: Column(
        children: [
          const _CardTitle(
              icon: Icons.tune_rounded,
              title: 'Preferences',
              subtitle: 'Saved to your account (all devices)'),
          const SizedBox(height: 8),
          _InfoLine(
            icon: Icons.alarm_rounded,
            label: 'Task reminder',
            value: _valueText(mins == 0 ? 'Off' : '$mins min before',
                color: mins == 0 ? AppColors.textMuted : AppColors.primary, pill: true),
            onTap: () => _pickReminder(context),
          ),
          _InfoLine(
            icon: Icons.notifications_active_outlined,
            label: 'Team alerts on phone',
            value: Switch(
              value: store.teamAlerts,
              onChanged: store.setTeamAlerts,
            ),
          ),
        ],
      ),
    );
  }
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

class _ActivityCard extends StatelessWidget {
  final List<ActivityItem> items;
  const _ActivityCard({required this.items});

  @override
  Widget build(BuildContext context) => DashCard(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle(
                icon: Icons.history_rounded,
                title: 'Recent activity',
                subtitle: 'What you did lately'),
            const SizedBox(height: 6),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Nothing yet. Finish a task or create a team.',
                    style: TextStyle(color: AppColors.textMuted)),
              )
            else
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 56),
                _ActivityTile(item: items[i]),
              ],
          ],
        ),
      );
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

class _ProfilePhone extends StatelessWidget {
  final _ProfileData data;
  const _ProfilePhone({required this.data});

  @override
  Widget build(BuildContext context) {
    final d = data;
    Widget tile(IconData icon, Color color, int value, String label) => Expanded(
          child: WhiteCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                    radius: 19,
                    backgroundColor: color.withAlpha(28),
                    child: Icon(icon, color: color, size: 19)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$value',
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        Row(
          children: [
            Avatar(name: d.user.name, size: 64),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.user.name,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(d.user.email, style: const TextStyle(color: AppColors.textMuted)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit profile',
              icon: const Icon(Icons.edit_outlined, color: AppColors.textMuted),
              onPressed: () => _push(context, const AccountScreen()),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: _badges(context, d)),
        const SizedBox(height: 18),
        Row(children: [
          tile(Icons.assignment_outlined, AppColors.primary, d.total, 'Total tasks'),
          const SizedBox(width: 10),
          tile(Icons.check_circle_outline_rounded, AppColors.success, d.done, 'Done'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          tile(Icons.schedule_rounded, AppColors.warning, d.pending, 'Pending'),
          const SizedBox(width: 10),
          tile(Icons.groups_rounded, AppColors.purple, d.teams, 'Teams'),
        ]),
        const SizedBox(height: 18),
        for (final q in _quickItems())
          _MenuTile(icon: q.icon, label: q.title, badge: q.badge, onTap: () => q.onTap(context)),
        const SizedBox(height: 12),
        ProgressRingCard(
            done: d.done,
            pending: d.pending,
            overdue: d.overdue,
            title: 'Focus summary',
            subtitle: 'Personal tasks + team tasks assigned to you'),
        const SizedBox(height: 14),
        const _PreferencesCard(),
        const SizedBox(height: 14),
        const _SecurityCard(),
        const SizedBox(height: 14),
        _ActivityCard(items: d.activity.take(4).toList()),
        const SizedBox(height: 20),
        _logoutButton(context),
      ],
    );
  }
}

// ================================================================ laptop

class _ProfileWide extends StatelessWidget {
  final _ProfileData data;
  const _ProfileWide({required this.data});

  @override
  Widget build(BuildContext context) {
    final d = data;
    final quick = _quickItems().take(6).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
      children: [
        // --------------------------------------------------- header card
        Container(
          padding: const EdgeInsets.fromLTRB(32, 26, 24, 26),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Colors.white, Color(0xFFEAF1FE)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            border: Border.all(color: const Color(0xFFEEF1F6)),
          ),
          child: Row(
            children: [
              Avatar(name: d.user.name, size: 104),
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.user.name,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(d.user.email,
                        style: const TextStyle(fontSize: 16, color: AppColors.textMuted)),
                    const SizedBox(height: 14),
                    Wrap(spacing: 10, runSpacing: 8, children: _badges(context, d)),
                  ],
                ),
              ),
              Tooltip(
                message: 'Edit profile',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _push(context, const AccountScreen()),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(Icons.edit_outlined),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
                child: StatCard(
                    icon: Icons.assignment_outlined,
                    color: AppColors.primary,
                    value: d.total,
                    label: 'Total tasks',
                    colorValue: false)),
            const SizedBox(width: 16),
            Expanded(
                child: StatCard(
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.success,
                    value: d.done,
                    label: 'Done',
                    colorValue: false)),
            const SizedBox(width: 16),
            Expanded(
                child: StatCard(
                    icon: Icons.schedule_rounded,
                    color: AppColors.warning,
                    value: d.pending,
                    label: 'Pending',
                    colorValue: false)),
            const SizedBox(width: 16),
            Expanded(
                child: StatCard(
                    icon: Icons.groups_rounded,
                    color: AppColors.purple,
                    value: d.teams,
                    label: 'Teams',
                    colorValue: false)),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DashCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _CardTitle(
                            icon: Icons.settings_outlined,
                            title: 'Quick settings',
                            subtitle: 'Manage your account and app'),
                        const SizedBox(height: 14),
                        LayoutBuilder(builder: (context, box) {
                          final w = (box.maxWidth - 14) / 2;
                          return Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: [
                              for (final q in quick) SizedBox(width: w, child: _QuickCard(item: q)),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _ActivityCard(items: d.activity),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProgressRingCard(
                      done: d.done,
                      pending: d.pending,
                      overdue: d.overdue,
                      title: 'Focus summary',
                      subtitle: 'Your task completion progress'),
                  const SizedBox(height: 18),
                  const _PreferencesCard(),
                  const SizedBox(height: 18),
                  const _SecurityCard(),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => _push(context, const HelpScreen()),
              icon: const Icon(Icons.help_outline_rounded),
              label: const Text('Help & FAQ'),
            ),
            TextButton.icon(
              onPressed: () => _showAbout(context),
              icon: const Icon(Icons.info_outline_rounded),
              label: const Text('About'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _logoutButton(context),
      ],
    );
  }
}

class _QuickCard extends StatelessWidget {
  final _QuickItem item;
  const _QuickCard({required this.item});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => item.onTap(context),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8ECF3)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: item.color.withAlpha(26),
                  child: Badge(
                    isLabelVisible: item.badge > 0,
                    label: Text('${item.badge}'),
                    child: Icon(item.icon, color: item.color),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      );
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int badge;
  final VoidCallback onTap;
  const _MenuTile({required this.icon, required this.label, required this.onTap, this.badge = 0});

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
                decoration:
                    BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(10)),
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
