import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../widgets/common.dart';
import 'task_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _tab = 'all'; // all | task | system

  /// Ids that were unread when the screen opened, so they stay highlighted
  /// while the user is looking at them.
  late final Set<String> _unreadOnOpen;

  @override
  void initState() {
    super.initState();
    final store = AppStore.instance;
    _unreadOnOpen =
        store.notifications.where((n) => !n.isRead).map((n) => n.id).toSet();
    WidgetsBinding.instance.addPostFrameCallback((_) => store.markAllRead());
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              if (store.notifications.isEmpty) return;
              final ok = await confirmDialog(context,
                  title: 'Clear notifications?',
                  message: 'All notifications will be removed.',
                  confirmLabel: 'Clear',
                  danger: true);
              if (ok) await store.clearNotifications();
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final list = store.notifications
              .where((n) => _tab == 'all' || n.type == _tab)
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    _pill('All', 'all'),
                    const SizedBox(width: 8),
                    _pill('Tasks', 'task'),
                    const SizedBox(width: 8),
                    _pill('System', 'system'),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? ListView(children: const [
                        EmptyState(
                          icon: Icons.notifications_off_outlined,
                          title: 'No notifications',
                          subtitle: "You're all caught up.",
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) => _NotificationRow(
                          n: list[i],
                          highlight: _unreadOnOpen.contains(list[i].id),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _pill(String label, String value) {
    final active = _tab == value;
    return GestureDetector(
      onTap: () => setState(() => _tab = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? AppColors.primary : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? Colors.white : AppColors.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final AppNotification n;
  final bool highlight;
  const _NotificationRow({required this.n, required this.highlight});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (n.kind) {
      'completed' => (Icons.check_circle_rounded, AppColors.success),
      'assigned' => (Icons.person_add_alt_1_rounded, AppColors.primary),
      'reminder' => (Icons.notifications_active_rounded, AppColors.purple),
      'cancelled' => (Icons.cancel_rounded, AppColors.danger),
      'project' => (Icons.folder_rounded, AppColors.primary),
      'team' => (Icons.groups_rounded, AppColors.primary),
      _ => (Icons.info_rounded, AppColors.textMuted),
    };
    final store = AppStore.instance;
    final task = n.taskId == null ? null : store.taskById(n.taskId!);

    return InkWell(
      onTap: task == null ? null : () => openTaskDetail(context, task),
      child: Container(
        color: highlight ? AppColors.primaryLight.withAlpha(120) : null,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: color.withAlpha(30), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(n.body,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 13, height: 1.35)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(timeAgo(n.createdAt),
                style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
