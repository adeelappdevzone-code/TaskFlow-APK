part of 'profile_screen.dart';

// The Profile page (laptop and phone): header, my numbers, and tabs for
// Account, Notifications, Preferences and Security & Backup.

enum _PTab { account, notifications, preferences, security }

class _ProfilePage extends StatefulWidget {
  final _ProfileData data;
  final bool wide;
  const _ProfilePage({required this.data, required this.wide});

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  _PTab _tab = _PTab.account;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final wide = widget.wide;
    final gap = SizedBox(height: wide ? 20 : 14, width: wide ? 20 : 12);

    final stats = [
      _ProfileStat(
          icon: Icons.assignment_turned_in_outlined,
          color: AppColors.primary,
          value: d.total,
          label: 'Total Tasks',
          compact: !wide,
          onTap: () => MainShell.switchTab(context, 1)),
      _ProfileStat(
          icon: Icons.check_box_rounded,
          color: AppColors.success,
          value: d.done,
          label: 'Completed',
          compact: !wide,
          onTap: () => MainShell.switchTab(context, 1)),
      _ProfileStat(
          icon: Icons.person_outline_rounded,
          color: AppColors.danger,
          value: d.pending,
          label: 'Pending',
          compact: !wide,
          onTap: () => MainShell.switchTab(context, 1)),
      _ProfileStat(
          icon: Icons.groups_rounded,
          color: AppColors.purple,
          value: d.teams,
          label: 'Teams',
          compact: !wide,
          onTap: () => MainShell.switchTab(context, 4)),
    ];

    return ListView(
      padding: wide
          ? const EdgeInsets.fromLTRB(24, 20, 24, 40)
          : const EdgeInsets.fromLTRB(16, 14, 16, 100),
      children: [
        _Header(data: d, wide: wide),
        gap,
        if (wide)
          Row(children: [
            for (final (i, s) in stats.indexed) ...[if (i > 0) gap, Expanded(child: s)],
          ])
        else
          Column(children: [
            Row(children: [Expanded(child: stats[0]), gap, Expanded(child: stats[1])]),
            const SizedBox(height: 12),
            Row(children: [Expanded(child: stats[2]), gap, Expanded(child: stats[3])]),
          ]),
        gap,
        _Tabs(tab: _tab, onChanged: (t) => setState(() => _tab = t)),
        gap,
        ..._body(context, d, wide, gap),
        if (!wide) ...[gap, _logoutButton(context)],
      ],
    );
  }

  List<Widget> _body(BuildContext context, _ProfileData d, bool wide, Widget gap) {
    Widget split(List<Widget> left, List<Widget> right) => wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 11, child: Column(children: left)),
            gap,
            Expanded(flex: 9, child: Column(children: right)),
          ])
        : Column(children: [...left, ...right]);

    switch (_tab) {
      case _PTab.account:
        return [
          split([
            const _ProfileInfoCard(),
            gap,
            const _QuickSettingsCard(),
          ], [
            if (!wide) gap,
            const _SecurityShort(),
            gap,
            _RecentCard(items: d.activity),
          ]),
        ];
      case _PTab.notifications:
        return [
          split([const _NotifSettingsCard()], [if (!wide) gap, const _InboxCard()]),
        ];
      case _PTab.preferences:
        return [
          split([const _QuickSettingsCard(), gap, const _OrganizeCard()],
              [if (!wide) gap, const _AboutCard()]),
        ];
      case _PTab.security:
        return [
          split([const _SecurityCard(), gap, const _BackupCard()],
              [if (!wide) gap, const _SessionCard()]),
        ];
    }
  }
}

// ==================================================================== header

class _Header extends StatelessWidget {
  final _ProfileData data;
  final bool wide;
  const _Header({required this.data, required this.wide});

  @override
  Widget build(BuildContext context) {
    final d = data;
    final store = AppStore.instance;
    final chips = [
      if (store.jobTitle.isNotEmpty)
        _Badge(icon: Icons.work_outline_rounded, text: store.jobTitle, color: AppColors.primary),
      if (d.role != null)
        _Badge(
            icon: d.role == 'Owner'
                ? Icons.workspace_premium_rounded
                : (d.role == 'Manager' ? Icons.manage_accounts_rounded : Icons.person_rounded),
            text: d.role == 'Member' ? 'Team member' : 'Team ${d.role}',
            color: d.role == 'Owner' ? AppColors.primary : AppColors.purple),
      const _Badge(icon: Icons.circle, text: 'Active today', color: AppColors.success),
    ];
    final edit = OutlinedButton.icon(
      onPressed: () => _push(context, const AccountScreen()),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.edit_outlined, size: 18),
      label: const Text('Edit profile', style: TextStyle(fontWeight: FontWeight.w600)),
    );
    return DashCard(
      padding: EdgeInsets.all(wide ? 24 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditableAvatar(size: wide ? 118 : 64),
          SizedBox(width: wide ? 32 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: wide ? 8 : 0),
                Text(d.user.name,
                    style: TextStyle(fontSize: wide ? 28 : 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(d.user.email,
                    style: TextStyle(color: AppColors.textMuted, fontSize: wide ? 17 : 13.5)),
                const SizedBox(height: 12),
                Wrap(spacing: 10, runSpacing: 8, children: chips),
              ],
            ),
          ),
          if (wide)
            edit
          else
            IconButton(
              tooltip: 'Edit profile',
              onPressed: () => _push(context, const AccountScreen()),
              icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
            ),
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int value;
  final String label;
  final bool compact;
  final VoidCallback onTap;
  const _ProfileStat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(compact ? 12 : 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEEF1F6)),
          ),
          child: Row(children: [
            Container(
              width: compact ? 40 : 60,
              height: compact ? 40 : 60,
              decoration: BoxDecoration(
                  color: color.withAlpha(24),
                  borderRadius: BorderRadius.circular(compact ? 11 : 16)),
              child: Icon(icon, color: color, size: compact ? 21 : 30),
            ),
            SizedBox(width: compact ? 10 : 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$value',
                      style: TextStyle(
                          fontSize: compact ? 20 : 30,
                          fontWeight: FontWeight.w800,
                          color: Color.lerp(color, Colors.black, 0.15))),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: compact ? 12.5 : 16,
                          color: label == 'Completed' ? color : const Color(0xFF374151))),
                ],
              ),
            ),
            if (!compact)
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: color.withAlpha(20), shape: BoxShape.circle),
                child: Icon(Icons.chevron_right_rounded, color: color),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  final _PTab tab;
  final ValueChanged<_PTab> onChanged;
  const _Tabs({required this.tab, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const items = [
      (_PTab.account, Icons.person_outline_rounded, 'Account'),
      (_PTab.notifications, Icons.notifications_none_rounded, 'Notifications'),
      (_PTab.preferences, Icons.settings_outlined, 'Preferences'),
      (_PTab.security, Icons.verified_user_outlined, 'Security & Backup'),
    ];
    return DashCard(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (t, icon, label) in items)
            InkWell(
              onTap: () => onChanged(t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                        color: tab == t ? AppColors.primary : Colors.transparent, width: 3),
                  ),
                ),
                child: Row(children: [
                  Icon(icon, size: 21, color: tab == t ? AppColors.primary : AppColors.text),
                  const SizedBox(width: 10),
                  Text(label,
                      style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: tab == t ? FontWeight.w700 : FontWeight.w500,
                          color: tab == t ? AppColors.primary : AppColors.text)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

// =================================================================== account

Widget _cardHead(String title, {Widget? trailing, String? subtitle}) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              if (subtitle != null)
                Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ]),
    );

/// "(GMT+05:00) PKT" from the device.
String _timezoneText() {
  final now = DateTime.now();
  final o = now.timeZoneOffset;
  final sign = o.isNegative ? '-' : '+';
  final h = o.inHours.abs().toString().padLeft(2, '0');
  final m = (o.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return '(GMT$sign$h:$m) ${now.timeZoneName}';
}

class _ProfileInfoCard extends StatefulWidget {
  const _ProfileInfoCard();

  @override
  State<_ProfileInfoCard> createState() => _ProfileInfoCardState();
}

class _ProfileInfoCardState extends State<_ProfileInfoCard> {
  bool _editing = false;
  bool _saving = false;
  final _name = TextEditingController();
  final _title = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    super.dispose();
  }

  void _startEdit() {
    final store = AppStore.instance;
    _name.text = store.currentUser?.name ?? '';
    _title.text = store.jobTitle;
    setState(() => _editing = true);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      showSnack(context, 'Please enter your name.');
      return;
    }
    setState(() => _saving = true);
    final store = AppStore.instance;
    await store.updateName(name);
    if (_title.text.trim() != store.jobTitle) store.updateJobTitle(_title.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _editing = false;
    });
    showSnack(context, 'Profile updated');
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final user = store.currentUser!;
    Widget field(String label, Widget child) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            const SizedBox(height: 8),
            child,
          ],
        );
    Widget shown(String text, {IconData? trailing}) => Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _editing ? const Color(0xFFF7F8FA) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Expanded(
                child: Text(text.isEmpty ? '—' : text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5))),
            if (trailing != null) Icon(trailing, size: 18, color: AppColors.textMuted),
          ]),
        );
    final fields = [
      field(
          'Full name',
          _editing
              ? TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [LengthLimitingTextInputFormatter(100)],
                  decoration: fieldDecoration('Full name'))
              : shown(user.name)),
      field('Email address', shown(user.email, trailing: Icons.lock_outline_rounded)),
      field(
          'Job title',
          _editing
              ? TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [LengthLimitingTextInputFormatter(60)],
                  decoration: fieldDecoration('e.g. CEO, SEO lead'))
              : shown(store.jobTitle)),
      field('Timezone', shown(_timezoneText(), trailing: Icons.public_rounded)),
    ];

    return DashCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHead('Profile Information',
              trailing: _editing
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      TextButton(
                          onPressed: () => setState(() => _editing = false),
                          child: const Text('Cancel')),
                      const SizedBox(width: 6),
                      FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
                    ])
                  : FilledButton.tonalIcon(
                      onPressed: _startEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    )),
          LayoutBuilder(builder: (context, box) {
            final two = box.maxWidth >= 560;
            final avatar = Column(children: [
              const EditableAvatar(size: 110),
              const SizedBox(height: 10),
              Text('Member since ${DateFormat('MMM yyyy').format(user.createdAt)}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            ]);
            final grid = Column(children: [
              for (var i = 0; i < fields.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: two
                      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: fields[i]),
                          const SizedBox(width: 18),
                          Expanded(child: fields[i + 1]),
                        ])
                      : Column(children: [fields[i], const SizedBox(height: 16), fields[i + 1]]),
                ),
            ]);
            return two
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 170, child: avatar),
                    const SizedBox(width: 24),
                    Expanded(child: grid),
                  ])
                : grid; // phone: the photo is already in the header
          }),
        ],
      ),
    );
  }
}

/// One row: icon in a circle, title + description, control on the right.
class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final Color color;
  const _SettingRow(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.trailing,
      this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: color.withAlpha(20), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 23),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ]),
      );
}

Widget _pill(String text, Color c, {IconData icon = Icons.check_circle_rounded}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: c.withAlpha(24), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    );

Widget _dropdown<T>(
        {required T value,
        required List<(T, String)> items,
        required ValueChanged<T> onChanged,
        IconData? icon}) =>
    PopupMenuButton<T>(
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final (v, l) in items)
          CheckedPopupMenuItem(value: v, checked: v == value, child: Text(l)),
      ],
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.warning),
            const SizedBox(width: 8)
          ],
          Text(items.firstWhere((i) => i.$1 == value).$2,
              style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 10),
          const Icon(Icons.expand_more_rounded, size: 20),
        ]),
      ),
    );

class _QuickSettingsCard extends StatelessWidget {
  const _QuickSettingsCard();

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return DashCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
      child: Column(children: [
        _cardHead('Quick Settings'),
        _SettingRow(
          icon: Icons.work_history_outlined,
          title: 'Working hours',
          subtitle: '${workHoursText(context)} • ${workDaysText(store.workDays)}'
              '${store.workHoursSet ? '' : ' (default)'}',
          trailing: OutlinedButton(
            onPressed: () => editWorkHours(context),
            child: const Text('Change'),
          ),
        ),
        const Divider(height: 1),
        _SettingRow(
          icon: Icons.dark_mode_outlined,
          title: 'Theme',
          subtitle: 'Dark mode is coming soon',
          trailing: _dropdown<String>(
              value: 'light',
              icon: Icons.wb_sunny_rounded,
              items: const [('light', 'Light')],
              onChanged: (_) {}),
        ),
        const Divider(height: 1),
        _SettingRow(
          icon: Icons.alarm_rounded,
          title: 'Task reminders',
          subtitle: 'Phone reminder before a task starts',
          trailing: _dropdown<int>(
            value: store.reminderMinutes,
            items: const [(0, 'Off'), (5, '5 min'), (15, '15 min'), (30, '30 min'), (60, '1 hour')],
            onChanged: store.setReminderMinutes,
          ),
        ),
        const Divider(height: 1),
        _SettingRow(
          icon: Icons.notifications_active_outlined,
          title: 'Team alerts',
          subtitle: 'New tasks, comments and invites on your phone',
          trailing: Switch(value: store.teamAlerts, onChanged: store.setTeamAlerts),
        ),
      ]),
    );
  }
}

Future<void> _changePassword(BuildContext context) async {
  final a = TextEditingController();
  final b = TextEditingController();
  String? error;
  final pw = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Change password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: a,
              obscureText: true,
              decoration: fieldDecoration('New password', icon: Icons.lock_outline_rounded)),
          const SizedBox(height: 10),
          TextField(
              controller: b,
              obscureText: true,
              decoration: fieldDecoration('Repeat new password', icon: Icons.lock_outline_rounded)
                  .copyWith(errorText: error)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (a.text.length < 6) {
                setState(() => error = 'At least 6 characters');
              } else if (a.text != b.text) {
                setState(() => error = 'The two passwords are different');
              } else {
                Navigator.pop(ctx, a.text);
              }
            },
            child: const Text('Change'),
          ),
        ],
      ),
    ),
  );
  if (pw == null || !context.mounted) return;
  final err = await AppStore.instance.changePassword(pw);
  if (context.mounted) showSnack(context, err ?? 'Password changed.');
}

class _SecurityShort extends StatelessWidget {
  const _SecurityShort();

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final password = store.signInMethods.contains('password');
    final backup = store.lastBackupAt;
    return DashCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
      child: Column(children: [
        _cardHead('Security & Account'),
        _SettingRow(
          icon: Icons.lock_outline_rounded,
          title: 'Password',
          subtitle: password ? 'Change your password regularly' : 'You sign in with Google',
          trailing: password
              ? OutlinedButton(
                  onPressed: () => _changePassword(context), child: const Text('Change password'))
              : _pill('Google', AppColors.primary, icon: Icons.verified_rounded),
        ),
        const Divider(height: 1),
        _SettingRow(
          icon: Icons.verified_user_outlined,
          color: AppColors.success,
          title: 'Email verification',
          subtitle: store.emailVerified ? 'Your email is verified' : 'Needed to join teams',
          trailing: store.emailVerified
              ? _pill('Verified', AppColors.success)
              : OutlinedButton(onPressed: () => _verifyEmail(context), child: const Text('Verify')),
        ),
        const Divider(height: 1),
        _SettingRow(
          icon: Icons.cloud_done_outlined,
          title: 'Backup & Sync',
          subtitle: 'Your data syncs to your account automatically',
          trailing: _pill(
              backup == null ? 'Synced' : 'Last backup: ${_agoText(backup)}', AppColors.success),
        ),
      ]),
    );
  }
}

class _RecentCard extends StatefulWidget {
  final List<ActivityItem> items;
  const _RecentCard({required this.items});

  @override
  State<_RecentCard> createState() => _RecentCardState();
}

class _RecentCardState extends State<_RecentCard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final items = _all ? widget.items : widget.items.take(4).toList();
    return DashCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHead('Recent Activity',
              trailing: widget.items.length > 4
                  ? FilledButton.tonal(
                      onPressed: () => setState(() => _all = !_all),
                      child: Text(_all ? 'Show less' : 'View all'))
                  : null),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Nothing yet. Finish a task or create a team.',
                  style: TextStyle(color: AppColors.textMuted)),
            ),
          for (final a in items) _ActivityTile(item: a),
        ],
      ),
    );
  }
}

// ============================================================= notifications

class _NotifSettingsCard extends StatelessWidget {
  const _NotifSettingsCard();

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return DashCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
      child: Column(children: [
        _cardHead('Notification settings', subtitle: 'Saved to your account (all devices)'),
        _SettingRow(
          icon: Icons.alarm_rounded,
          title: 'Task reminders',
          subtitle: 'A phone notification before each task starts',
          trailing: _dropdown<int>(
            value: store.reminderMinutes,
            items: const [(0, 'Off'), (5, '5 min'), (15, '15 min'), (30, '30 min'), (60, '1 hour')],
            onChanged: store.setReminderMinutes,
          ),
        ),
        const Divider(height: 1),
        _SettingRow(
          icon: Icons.groups_outlined,
          title: 'Team alerts',
          subtitle: 'Assigned tasks, comments, @mentions, invites',
          trailing: Switch(value: store.teamAlerts, onChanged: store.setTeamAlerts),
        ),
        const Divider(height: 1),
        _SettingRow(
          icon: Icons.mail_outline_rounded,
          color: AppColors.textMuted,
          title: 'Email notifications',
          subtitle: 'Needs the paid Firebase plan — not available yet',
          trailing: const Switch(value: false, onChanged: null),
        ),
      ]),
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard();

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final list = [...store.notifications]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return DashCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHead('Notifications',
              subtitle: '${store.unreadCount} unread',
              trailing: FilledButton.tonal(
                  onPressed: () => _push(context, const NotificationsScreen()),
                  child: const Text('Open notifications'))),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No notifications yet.', style: TextStyle(color: AppColors.textMuted)),
            ),
          for (final n in list.take(6))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Icon(
                    n.isRead
                        ? Icons.notifications_none_rounded
                        : Icons.notifications_active_rounded,
                    color: n.isRead ? AppColors.textMuted : AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700)),
                      Text(n.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
                Text(_agoText(n.createdAt),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ]),
            ),
        ],
      ),
    );
  }
}

// =============================================================== preferences

class _OrganizeCard extends StatelessWidget {
  const _OrganizeCard();

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return DashCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
      child: Column(children: [
        _cardHead('Organize', subtitle: 'For your personal tasks'),
        _SettingRow(
          icon: Icons.folder_outlined,
          color: AppColors.warning,
          title: 'Projects',
          subtitle: '${store.projects.where((p) => p.deletedAt == null).length} projects',
          trailing: OutlinedButton(
              onPressed: () => _push(context, const ProjectsScreen()), child: const Text('Manage')),
        ),
        const Divider(height: 1),
        _SettingRow(
          icon: Icons.label_outline_rounded,
          color: const Color(0xFFF97316),
          title: 'Labels',
          subtitle: '${store.categories.length} labels',
          trailing: OutlinedButton(
              onPressed: () => _push(context, const CategoriesScreen()),
              child: const Text('Manage')),
        ),
      ]),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return DashCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
      child: Column(children: [
        _cardHead('Help & About'),
        _SettingRow(
          icon: Icons.help_outline_rounded,
          color: AppColors.success,
          title: 'Help & FAQ',
          subtitle: 'How TaskFlow works',
          trailing: OutlinedButton(
              onPressed: () => _push(context, const HelpScreen()), child: const Text('Open')),
        ),
        const Divider(height: 1),
        _SettingRow(
          icon: Icons.info_outline_rounded,
          color: AppColors.textMuted,
          title: 'About TaskFlow',
          subtitle: 'Version and app info',
          trailing: OutlinedButton(onPressed: () => _showAbout(context), child: const Text('Open')),
        ),
      ]),
    );
  }
}

// ================================================================== security

class _BackupCard extends StatelessWidget {
  const _BackupCard();

  @override
  Widget build(BuildContext context) {
    final backup = AppStore.instance.lastBackupAt;
    return DashCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
      child: Column(children: [
        _cardHead('Backup', subtitle: 'Your data is already synced to your account'),
        _SettingRow(
          icon: Icons.backup_outlined,
          title: 'Backup copy',
          subtitle: backup == null ? 'Never copied' : 'Last copied ${_agoText(backup)}',
          trailing: OutlinedButton(
              onPressed: () => _push(context, const SettingsScreen()),
              child: const Text('Backup & restore')),
        ),
      ]),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard();

  @override
  Widget build(BuildContext context) {
    final methods = AppStore.instance.signInMethods;
    final method = [
      if (methods.contains('google.com')) 'Google',
      if (methods.contains('password')) 'Email & password',
    ].join(' + ');
    return DashCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHead('Session'),
          _SettingRow(
            icon: Icons.login_rounded,
            title: 'Signed in with',
            subtitle: method.isEmpty ? '—' : method,
            trailing: const SizedBox.shrink(),
          ),
          const SizedBox(height: 10),
          _logoutButton(context),
        ],
      ),
    );
  }
}
