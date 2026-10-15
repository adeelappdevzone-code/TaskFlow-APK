import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// Only these: flutter_local_notifications has its own `Priority`.
import 'models.dart' show TaskItem, TaskStatus;

/// How long before a task's start time the phone reminder is shown.
const reminderLead = Duration(minutes: 15);

/// Android allows a limited number of scheduled alarms per app, so only the
/// next [maxReminders] tasks get one.
const maxReminders = 50;

/// One phone notification to schedule.
class ReminderPlan {
  final int id;
  final String taskId;
  final DateTime at;
  final String title;
  final String body;

  const ReminderPlan({
    required this.id,
    required this.taskId,
    required this.at,
    required this.title,
    required this.body,
  });
}

/// Stable notification id for a task (String.hashCode is not guaranteed to be
/// the same between app runs). FNV-1a, kept positive and within 31 bits.
int reminderIdFor(String taskId) {
  var h = 0x811c9dc5;
  for (final c in taskId.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

/// Which reminders should be scheduled right now: pending tasks whose
/// reminder time ([reminderLead] before the start) is still in the future,
/// soonest first, at most [max].
List<ReminderPlan> planReminders(Iterable<TaskItem> tasks, DateTime now,
    {int max = maxReminders}) {
  final plans = <ReminderPlan>[];
  for (final t in tasks) {
    if (t.status != TaskStatus.pending) continue;
    final at = t.startAt.subtract(reminderLead);
    if (!at.isAfter(now)) continue;
    plans.add(ReminderPlan(
      id: reminderIdFor(t.id),
      taskId: t.id,
      at: at,
      title: 'Reminder: ${t.title}',
      body: 'Starts in ${reminderLead.inMinutes} minutes',
    ));
  }
  plans.sort((a, b) => a.at.compareTo(b.at));
  return plans.length > max ? plans.sublist(0, max) : plans;
}

/// Phone notifications for upcoming tasks. They are shown by Android even when
/// the app is closed (and are re-created after a phone restart).
class PhoneReminders {
  PhoneReminders._();
  static final PhoneReminders instance = PhoneReminders._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _askedPermission = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'task_reminders',
      'Task reminders',
      channelDescription: 'Reminds you 15 minutes before a task starts',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Reminders init: $e');
    }
  }

  /// Asks for the notification permission (Android 13+), once per app run.
  Future<void> askPermission() async {
    if (!_ready || _askedPermission) return;
    _askedPermission = true;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Reminders permission: $e');
    }
  }

  /// Replaces all scheduled reminders with the ones for [tasks].
  Future<void> sync(Iterable<TaskItem> tasks) async {
    if (!_ready) return;
    try {
      // Only scheduled ones: cancelAll() would also remove notifications
      // already showing (e.g. "New task assigned").
      await _plugin.cancelAllPendingNotifications();
      for (final p in planReminders(tasks, DateTime.now())) {
        await _plugin.zonedSchedule(
          id: p.id,
          title: p.title,
          body: p.body,
          // An exact instant, so UTC works whatever the phone's time zone is.
          scheduledDate: tz.TZDateTime.from(p.at.toUtc(), tz.UTC),
          notificationDetails: _details,
          // Inexact: no special "alarms" permission needed; Android may show
          // it a few minutes late when the phone is idle.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: p.taskId,
        );
      }
    } catch (e) {
      debugPrint('Reminders sync: $e');
    }
  }

  int _nextNowId = 0;

  /// Shows a notification right away (e.g. "New task assigned to you").
  Future<void> showNow(String title, String body) async {
    if (!_ready) return;
    try {
      // Negative ids never clash with reminder ids (0 .. 2^31-1, see
      // [reminderIdFor]).
      await _plugin.show(
        id: -1 - (_nextNowId++ % 1000),
        title: title,
        body: body,
        notificationDetails: _nowDetails,
      );
    } catch (e) {
      debugPrint('Notification: $e');
    }
  }

  static const _nowDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'team_updates',
      'Team updates',
      channelDescription: 'New tasks, invitations and team changes',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  /// Removes all scheduled reminders (e.g. on logout).
  Future<void> clear() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('Reminders clear: $e');
    }
  }
}
