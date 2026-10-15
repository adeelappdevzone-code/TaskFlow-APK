import 'package:intl/intl.dart';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "Today", "Tomorrow", "Yesterday" or "Thu, 19 Jun".
String relativeDay(DateTime d) {
  final today = dateOnly(DateTime.now());
  final diff = dateOnly(d).difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return DateFormat('EEE, d MMM').format(d);
}

String formatTime(DateTime d) => DateFormat('HH:mm').format(d);

String formatFullDate(DateTime d) => DateFormat('EEEE, d MMM yyyy').format(d);

String formatShortDate(DateTime d) => DateFormat('d MMM yyyy').format(d);

/// "Just now", "10m", "2h", "3d".
String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return DateFormat('d MMM').format(d);
}

String greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

/// "2h 05m", "25m", "0m" (rounded down to minutes).
String formatDuration(Duration d) {
  final m = d.inMinutes;
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

/// "1:05:09" / "5:09" for a running timer.
String formatClock(Duration d) {
  final h = d.inHours;
  final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
  final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '${d.inMinutes}:$ss';
}

/// "10:00 - 11:00", "10:00", or "All day" (00:00 – 23:59).
String timeRangeText(DateTime start, DateTime? end) {
  if (end != null &&
      start.hour == 0 &&
      start.minute == 0 &&
      isSameDay(start, end) &&
      end.hour == 23 &&
      end.minute == 59) {
    return 'All day';
  }
  return end == null ? formatTime(start) : '${formatTime(start)} - ${formatTime(end)}';
}
