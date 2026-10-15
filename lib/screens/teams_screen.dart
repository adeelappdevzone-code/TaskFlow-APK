import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../data/app_store.dart';
import '../data/activity.dart';
import '../data/models.dart';
import '../data/team_models.dart';
import '../data/team_stats.dart';
import '../data/team_store.dart';
import '../widgets/common.dart';
import '../widgets/dashboard.dart';
import '../widgets/responsive.dart';
import 'report_screen.dart';
import 'team_screen.dart';

part 'teams_wide.dart';

/// Bottom-nav tab: invitations to me + the teams I am in.
class TeamsScreen extends StatelessWidget {
  const TeamsScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final result = await showTeamDialog(context);
    if (result == null || !context.mounted) return;
    final team = await TeamStore.instance.createTeam(result.$1, result.$2);
    if (team != null && context.mounted) openTeam(context, team);
  }

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    return SafeArea(
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final me = store.uid ?? '';
          if (isWideScreen(context)) return _TeamsWide(onCreate: _create);
          final sent = _sentInvites(me);
          final activity = _activity(me, limit: 5);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            children: [
              Row(
                children: [
                  const Expanded(
                    child:
                        Text('Teams', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                  TextButton.icon(
                    onPressed: () => _create(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New team'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Create a team, invite people by email and give them tasks.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (store.invites.isNotEmpty) ...[
                const SectionHeader(title: 'Invitations'),
                const SizedBox(height: 10),
                for (final i in store.invites) _InviteCard(invite: i),
                const SizedBox(height: 10),
              ],
              if (store.teams.isEmpty)
                Column(
                  children: [
                    const EmptyState(
                      icon: Icons.groups_rounded,
                      title: 'No teams yet',
                      subtitle:
                          'Make a team (for example "SEO"), then add people with the email they log in with.',
                    ),
                    PrimaryButton(
                      label: 'Create a team',
                      icon: Icons.add_rounded,
                      onPressed: () => _create(context),
                    ),
                  ],
                )
              else ...[
                _PhoneStats(teams: store.teams),
                const SizedBox(height: 18),
                const SectionHeader(title: 'My teams'),
                const SizedBox(height: 10),
                for (final t in store.teams) _TeamCard(team: t, me: me),
                if (sent.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  SectionHeader(title: 'Pending invites (${sent.length})'),
                  const SizedBox(height: 4),
                  WhiteCard(
                    padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
                    child: Column(children: [
                      for (final i in sent) _SentInviteRow(invite: i, showTeam: true),
                    ]),
                  ),
                ],
                if (activity.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const SectionHeader(title: 'Recent activity'),
                  const SizedBox(height: 4),
                  WhiteCard(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                    child: Column(children: [for (final a in activity) _ActivityRow(item: a)]),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

void openTeam(BuildContext context, Team team) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => TeamScreen(teamId: team.id)),
  );
}

/// Create / edit team dialog. Returns (name, color) or null.
Future<(String, int)?> showTeamDialog(BuildContext context, {Team? team}) {
  final name = TextEditingController(text: team?.name ?? '');
  var color =
      team?.color ?? kPaletteColors[TeamStore.instance.teams.length % kPaletteColors.length];
  return showDialog<(String, int)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(team == null ? 'New team' : 'Edit team'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: fieldDecoration('Team name, e.g. SEO'),
              inputFormatters: [LengthLimitingTextInputFormatter(60)],
            ),
            const SizedBox(height: 16),
            ColorPickerRow(selected: color, onChanged: (c) => setLocal(() => color = c)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final n = name.text.trim();
              if (n.isNotEmpty) Navigator.pop(ctx, (n, color));
            },
            child: Text(team == null ? 'Create' : 'Save'),
          ),
        ],
      ),
    ),
  );
}

class _TeamCard extends StatelessWidget {
  final Team team;
  final String me;
  const _TeamCard({required this.team, required this.me});

  @override
  Widget build(BuildContext context) {
    final store = TeamStore.instance;
    final tasks = store.tasksOf(team.id).where((t) => !t.isCancelled).toList();
    final done = tasks.where((t) => t.isCompleted).length;
    final forMe = store.pendingForMe(team.id);
    final role = team.roleOf(me) ?? TeamRole.member;
    final color = Color(team.color);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WhiteCard(
        onTap: () => openTeam(context, team),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: color.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.groups_rounded, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(team.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '${team.memberIds.length} ${team.memberIds.length == 1 ? 'member' : 'members'}'
                        ' • ${tasks.length} ${tasks.length == 1 ? 'task' : 'tasks'}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                RoleChip(role: role),
                SizedBox(width: 36, child: _teamMenu(context, team, me)),
              ],
            ),
            const SizedBox(height: 12),
            _MemberDots(team: team, canInvite: team.isAdmin(me)),
            if (tasks.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: done / tasks.length,
                  minHeight: 6,
                  color: color,
                  backgroundColor: color.withAlpha(30),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('$done/${tasks.length} done',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  const Spacer(),
                  if (forMe > 0)
                    Text('$forMe pending for you',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ],
              ),
              const Divider(height: 22),
              _TeamLegend(stats: TeamStats.compute(team, tasks, DateTime.now())),
            ],
          ],
        ),
      ),
    );
  }
}

class RoleChip extends StatelessWidget {
  final TeamRole role;
  const RoleChip({super.key, required this.role});

  @override
  Widget build(BuildContext context) => TagChip(
        label: role.label,
        color: switch (role) {
          TeamRole.owner => AppColors.purple,
          TeamRole.manager => AppColors.primary,
          TeamRole.member => AppColors.textMuted,
        },
      );
}

class _InviteCard extends StatefulWidget {
  final TeamInvite invite;
  const _InviteCard({required this.invite});

  @override
  State<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<_InviteCard> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    final store = TeamStore.instance;
    final err = await store.acceptInvite(widget.invite);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) {
      showSnack(context, 'You joined ${widget.invite.teamName}');
    } else if (err == TeamStore.needsVerification) {
      await _askToVerify();
    } else {
      showSnack(context, err);
    }
  }

  Future<void> _askToVerify() async {
    final email = AppStore.instance.currentUser?.email ?? 'your email';
    final send = await confirmDialog(
      context,
      title: 'Verify your email first',
      message: 'To join a team we must know $email really belongs to you. '
          'We will send a link to it: open it, then come back and tap Accept again.',
      confirmLabel: 'Send link',
    );
    if (!send || !mounted) return;
    final err = await TeamStore.instance.sendVerificationEmail();
    if (!mounted) return;
    showSnack(context, err ?? 'Link sent to $email. Check your inbox (and spam).');
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.invite;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WhiteCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mail_outline_rounded, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: i.invitedByName.isEmpty ? 'Someone' : i.invitedByName,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const TextSpan(text: ' invited you to '),
                    TextSpan(text: i.teamName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ])),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => TeamStore.instance.declineInvite(i),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _accept,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small avatar + name of a task's assignee, for team task rows.
class AssigneeBadge extends StatelessWidget {
  final Team team;
  final TaskItem task;
  const AssigneeBadge({super.key, required this.team, required this.task});

  @override
  Widget build(BuildContext context) {
    if (task.assigneeId == null) {
      return const TagChip(label: 'Unassigned', color: AppColors.textMuted);
    }
    final name = team.nameOf(task.assigneeId);
    final isMe = task.assigneeId == TeamStore.instance.uid;
    return Tooltip(
      message: name,
      child: Avatar(name: name, size: 30, color: isMe ? AppColors.primary : AppColors.purple),
    );
  }
}

/// Phone: Total teams / Pending / Overdue / Done this week, 2 x 2.
class _PhoneStats extends StatelessWidget {
  final List<Team> teams;
  const _PhoneStats({required this.teams});

  @override
  Widget build(BuildContext context) {
    final t = _Totals(teams);
    Widget tile(IconData icon, Color color, int value, String label, {bool colored = true}) =>
        Expanded(
          child: WhiteCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: color.withAlpha(28),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$value',
                          style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: colored ? color : AppColors.text)),
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
    return Column(
      children: [
        Row(children: [
          tile(Icons.groups_rounded, AppColors.primary, teams.length, 'Total teams',
              colored: false),
          const SizedBox(width: 10),
          tile(Icons.schedule_rounded, AppColors.warning, t.pending, 'Pending'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          tile(Icons.warning_amber_rounded, AppColors.danger, t.overdue, 'Overdue'),
          const SizedBox(width: 10),
          tile(Icons.check_circle_rounded, AppColors.success, t.doneThisWeek, 'Done this week'),
        ]),
      ],
    );
  }
}
