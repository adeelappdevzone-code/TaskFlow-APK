import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/weekly_report.dart';
import 'package:taskflow/widgets/task_extras.dart';

void main() {
  final now = DateTime(2026, 4, 15, 10); // a Wednesday

  TaskItem task({String id = 't1', String? assignee}) => TaskItem(
        id: id,
        title: 'Report',
        assigneeId: assignee,
        startAt: now,
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now,
        createdBy: 'own',
      );

  Team team() => Team(
        id: 'T',
        name: 'SEO',
        color: 1,
        ownerId: 'own',
        memberIds: ['own', 'adl', 'ali', 'aliya'],
        managerIds: [],
        members: {
          'own': const TeamMemberInfo(name: 'Owner', email: 'o@x.com'),
          'adl': const TeamMemberInfo(name: 'Adeel Khan', email: 'a@x.com'),
          'ali': const TeamMemberInfo(name: 'Ali Raza', email: 'ali@x.com'),
          'aliya': const TeamMemberInfo(name: 'Aliya', email: 'aliya@x.com'),
        },
        createdAt: now,
        updatedAt: now,
      );

  test('links: normalize addresses', () {
    expect(TaskLink.normalizeUrl('drive.google.com/abc'), 'https://drive.google.com/abc');
    expect(TaskLink.normalizeUrl(' https://x.com/a '), 'https://x.com/a');
    expect(TaskLink.normalizeUrl('http://site.pk'), 'http://site.pk');
    expect(TaskLink.normalizeUrl('hello'), isNull);
    expect(TaskLink.normalizeUrl('not a link.com'), isNull);
    expect(TaskLink.normalizeUrl('ftp://x.com'), isNull);
    expect(TaskLink.normalizeUrl(''), isNull);
    expect(const TaskLink(url: 'https://www.site.com/a').label, 'site.com/a');
    expect(const TaskLink(title: 'Brief', url: 'https://a.com').label, 'Brief');
  });

  test('links, history and time survive toMap / fromMap', () {
    final t = task()
      ..links = [const TaskLink(title: 'Doc', url: 'https://docs.google.com/x')]
      ..timerBy = 'adl'
      ..timerAt = now;
    t.addHistory(HistoryKind.created, 'own', at: now);
    t.addHistory(HistoryKind.stage, 'adl', to: TaskStage.doing, at: now);
    t.timeLog.add(TimeEntry(by: 'adl', start: now, end: now.add(const Duration(minutes: 90))));
    final back = TaskItem.fromMap(t.toMap());
    expect(back.links.single.url, 'https://docs.google.com/x');
    expect(back.history.map((e) => e.kind), [HistoryKind.created, HistoryKind.stage]);
    expect(back.history.last.to, TaskStage.doing);
    expect(back.timeLog.single.duration, const Duration(minutes: 90));
    expect(back.timerBy, 'adl');
    expect(back.timerAt, now);

    // Old tasks / bad values.
    final old = TaskItem.fromMap({...task().toMap()}
      ..remove('links')
      ..['history'] = [
        {'kind': 'done'}, // no time: skipped
        'junk',
      ]);
    expect(old.links, isEmpty);
    expect(old.history, isEmpty);
    expect(old.timerRunning, isFalse);
  });

  test('history: edits within 30 minutes merge, list is capped', () {
    final t = task();
    t.addHistory(HistoryKind.created, 'own', at: now);
    t.addHistory(HistoryKind.edited, 'own', at: now);
    t.addHistory(HistoryKind.edited, 'own', at: now.add(const Duration(minutes: 10)));
    expect(t.history.length, 2);
    t.addHistory(HistoryKind.edited, 'own', at: now.add(const Duration(hours: 2)));
    expect(t.history.length, 3);
    for (var i = 0; i < 150; i++) {
      t.addHistory(HistoryKind.stage, 'adl', to: TaskStage.doing, at: now);
    }
    expect(t.history.length, kMaxHistory);
    expect(t.history.first.kind, HistoryKind.created);
  });

  test('history: older tasks show what is known', () {
    final t = task(assignee: 'adl')
      ..assignedBy = 'own'
      ..assignedAt = now
      ..status = TaskStatus.completed
      ..completedAt = now.add(const Duration(hours: 1))
      ..completedBy = 'adl';
    final h = t.historyOrDerived;
    expect(h.map((e) => e.kind), [HistoryKind.created, HistoryKind.assigned, HistoryKind.done]);
    String name(String? id) => team().nameOf(id);
    expect(historyText(h[1], name), 'Owner assigned it to Adeel Khan');
    expect(historyText(h[2], name), 'Adeel Khan marked it done');
    expect(
        historyText(
            TaskEvent(kind: HistoryKind.stage, by: 'ali', at: now, to: TaskStage.review), name),
        'Ali Raza moved it to Review');
  });

  test('time: totals per person, running timer counted', () {
    final t = task()
      ..timeLog = [
        TimeEntry(by: 'adl', start: now, end: now.add(const Duration(minutes: 30))),
        TimeEntry(by: 'ali', start: now, end: now.add(const Duration(hours: 2))),
        TimeEntry(by: 'adl', start: now, end: now.add(const Duration(minutes: 45))),
      ]
      ..timerBy = 'adl'
      ..timerAt = now;
    expect(t.timeSpent(), const Duration(minutes: 195));
    expect(t.timeSpent(by: 'adl'), const Duration(minutes: 75));
    expect(t.timeSpent(by: 'adl', now: now.add(const Duration(minutes: 5))),
        const Duration(minutes: 80));
    expect(t.timeByPerson.first.key, 'ali');
    expect(t.timeByPerson.last.value, const Duration(minutes: 75));
  });

  test('weekly report adds tracked time per member', () {
    final monday = DateTime(2026, 4, 13);
    final t = task(assignee: 'adl')
      ..timeLog = [
        TimeEntry(
            by: 'adl',
            start: monday.add(const Duration(hours: 9)),
            end: monday.add(const Duration(hours: 11))),
        // Last week: not counted.
        TimeEntry(
            by: 'adl',
            start: monday.subtract(const Duration(days: 2)),
            end: monday.subtract(const Duration(days: 2)).add(const Duration(hours: 1))),
      ];
    final cancelled = task(id: 't2', assignee: 'ali')
      ..status = TaskStatus.cancelled
      ..timeLog = [
        TimeEntry(
            by: 'ali',
            start: monday.add(const Duration(days: 1)),
            end: monday.add(const Duration(days: 1, minutes: 30))),
      ];
    final r = WeeklyReport.compute(team(), [t, cancelled], now);
    expect(r.totalTime, const Duration(hours: 2, minutes: 30));
    expect(r.members.firstWhere((m) => m.uid == 'adl').time, const Duration(hours: 2));
    expect(r.members.firstWhere((m) => m.uid == 'ali').time, const Duration(minutes: 30));
    expect(r.toText(), contains('2h 30m'));
  });

  test('mentions: full name, unique first name, not partial words', () {
    final tm = team();
    expect(findMentions(tm, '@Adeel Khan please check'), ['adl']);
    expect(findMentions(tm, '@adeel please check'), ['adl']);
    expect(findMentions(tm, 'cc @Ali Raza and @Aliya'), ['ali', 'aliya']);
    expect(findMentions(tm, '@Ali'), ['ali'], reason: 'Ali is a unique first name');
    expect(findMentions(tm, '@Alibaba'), isEmpty);
    expect(findMentions(tm, 'mail me at x@adeel.com'), isEmpty);
    expect(findMentions(tm, '@Owner done', except: 'own'), isEmpty);
    expect(findMentions(tm, 'no tags'), isEmpty);
  });

  test('mention query while typing', () {
    TextEditingValue v(String text) =>
        TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    expect(mentionQuery(v('hi @Ad')), (start: 3, query: 'Ad'));
    expect(mentionQuery(v('@')), (start: 0, query: ''));
    expect(mentionQuery(v('mail x@y')), isNull);
    expect(mentionQuery(v('no tag')), isNull);
    expect(mentionQuery(v('@Ali\nnext')), isNull);
  });

  test('comment mentions survive toMap / fromMap', () {
    final c = TaskComment(
        id: 'c',
        taskId: 't',
        authorId: 'own',
        authorName: 'Owner',
        text: '@Adeel Khan',
        createdAt: now,
        mentions: ['adl']);
    expect(TaskComment.fromMap(c.toMap()).mentions, ['adl']);
    final plain = TaskComment(
        id: 'c', taskId: 't', authorId: 'own', authorName: 'O', text: 'x', createdAt: now);
    expect(plain.toMap().containsKey('mentions'), isFalse);
    expect(TaskComment.fromMap(plain.toMap()).mentions, isEmpty);
  });
}
