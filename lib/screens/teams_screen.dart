import 'workload_screen.dart';
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
import '../core/utils.dart';
import 'create_task_dialog.dart';
import 'report_screen.dart';
import 'team_screen.dart';

part 'teams_wide.dart';

/// Teams: invitations to me, the teams I am in, open invitations I sent and
/// what happened lately.
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
    return SafeArea(
      child: ListenableBuilder(
        listenable: TeamStore.instance,
        builder: (context, _) => _TeamsPage(onCreate: _create, wide: isWideScreen(context)),
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
