// Kept as widget_test.dart: `flutter create` (run in CI) would otherwise add
// its default counter-app test here, which does not compile for this app.

import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/utils.dart';

void main() {
  test('initials', () {
    expect(initials('Andi Pratama'), 'AP');
    expect(initials('usman'), 'U');
    expect(initials('  '), '?');
    expect(initials('ali  raza khan'), 'AR');
  });

  test('dates', () {
    expect(dateOnly(DateTime(2026, 5, 4, 23, 59)), DateTime(2026, 5, 4));
    expect(isSameDay(DateTime(2026, 5, 4, 1), DateTime(2026, 5, 4, 23)), isTrue);
    expect(isSameDay(DateTime(2026, 5, 4), DateTime(2026, 5, 5)), isFalse);
    expect(formatTime(DateTime(2026, 5, 4, 9, 5)), '09:05');
    expect(formatShortDate(DateTime(2026, 5, 4)), '4 May 2026');
  });

  test('relative day and time ago', () {
    final now = DateTime.now();
    expect(relativeDay(now), 'Today');
    expect(relativeDay(now.add(const Duration(days: 1))), 'Tomorrow');
    expect(relativeDay(now.subtract(const Duration(days: 1))), 'Yesterday');
    expect(timeAgo(now), 'Just now');
    expect(timeAgo(now.subtract(const Duration(minutes: 10))), '10m');
    expect(timeAgo(now.subtract(const Duration(hours: 2))), '2h');
    expect(timeAgo(now.subtract(const Duration(days: 3))), '3d');
  });
}
