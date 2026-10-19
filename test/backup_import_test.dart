import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/app_store.dart';

// A hand-made backup: tasks without a date must still import (one bad row
// used to make the whole import fail).
void main() {
  test('task without a date becomes an all-day task today', () {
    final row = jsonDecode('{"id":"a","title":"[GlazeMe Audit] Fix drawer","priority":3,'
        '"status":"pending","start_at":null,"end_at":null,"created_at":1792411500000,'
        '"updated_at":1792411500000,"checklist":[]}') as Map<String, dynamic>;
    final fixed = AppStore.fixTaskRow(row)!;
    final n = DateTime.now();
    final start = DateTime.fromMillisecondsSinceEpoch(fixed['start_at'] as int);
    expect(start, DateTime(n.year, n.month, n.day));
    final t = AppStore.taskFromMap(fixed);
    expect(t.isAllDay, isTrue);
    expect(t.title, '[GlazeMe Audit] Fix drawer');
  });

  test('missing fields get defaults; rows without id or title are skipped', () {
    final t = AppStore.fixTaskRow({'id': 'b', 'title': 'Only a title'})!;
    expect(t['status'], 'pending');
    expect(t['priority'], 2);
    expect(t['start_at'], isA<int>());
    expect(AppStore.fixTaskRow({'id': 'c', 'title': '  '}), isNull);
    expect(AppStore.fixTaskRow({'title': 'No id'}), isNull);
  });

  test('a normal task is kept as it is', () {
    final row = {
      'id': 'd',
      'title': 'Shopify Audit',
      'priority': 2,
      'status': 'pending',
      'start_at': 1792494000000,
      'end_at': 1792497600000,
      'created_at': 1792153022646,
      'updated_at': 1792153022647,
    };
    final fixed = AppStore.fixTaskRow(Map.of(row))!;
    expect(fixed['start_at'], 1792494000000);
    expect(fixed['end_at'], 1792497600000);
  });
}
