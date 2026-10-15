import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/team_models.dart';

void main() {
  final now = DateTime(2026, 4, 1, 10);

  Team team() => Team(
        id: 'T',
        name: 'SEO',
        color: 0xFF1F6FEB,
        ownerId: 'own',
        memberIds: ['own', 'mgr', 'zed', 'amy'],
        managerIds: ['mgr'],
        members: {
          'own': const TeamMemberInfo(name: 'Owner', email: 'owner@x.com'),
          'mgr': const TeamMemberInfo(name: 'Manager', email: 'mgr@x.com'),
          'zed': const TeamMemberInfo(name: 'Zed', email: 'zed@x.com'),
          'amy': const TeamMemberInfo(name: '', email: 'amy.k@x.com'),
        },
        createdAt: now,
        updatedAt: now,
      );

  test('roles and permissions', () {
    final t = team();
    expect(t.roleOf('own'), TeamRole.owner);
    expect(t.roleOf('mgr'), TeamRole.manager);
    expect(t.roleOf('zed'), TeamRole.member);
    expect(t.roleOf('stranger'), isNull);
    expect(t.isAdmin('own'), isTrue);
    expect(t.isAdmin('mgr'), isTrue);
    expect(t.isAdmin('zed'), isFalse);
  });

  test('names: falls back to email, then "Former member"', () {
    final t = team();
    expect(t.nameOf('zed'), 'Zed');
    expect(t.nameOf('amy'), 'amy.k');
    expect(t.nameOf('gone'), 'Former member');
    expect(t.nameOf(null), '');
  });

  test('members sorted: owner, managers, then by name', () {
    expect(team().sortedMemberIds, ['own', 'mgr', 'amy', 'zed']);
  });

  test('Team survives toMap / fromMap', () {
    final back = Team.fromMap(team().toMap());
    expect(back.name, 'SEO');
    expect(back.ownerId, 'own');
    expect(back.memberIds, ['own', 'mgr', 'zed', 'amy']);
    expect(back.managerIds, ['mgr']);
    expect(back.members['mgr']!.email, 'mgr@x.com');
    expect(back.createdAt, now);
  });

  test('invites: id and email helpers', () {
    expect(normalizeEmail('  Adeel@Gmail.COM '), 'adeel@gmail.com');
    expect(inviteIdFor('T', 'Adeel@Gmail.com'), 'T_adeel@gmail.com');
    expect(looksLikeEmail('a@b.co'), isTrue);
    expect(looksLikeEmail('a@b'), isFalse);
    expect(looksLikeEmail('no spaces@x.com'), isFalse);

    final i = TeamInvite(
      id: 'T_a@b.co',
      teamId: 'T',
      teamName: 'SEO',
      email: 'a@b.co',
      invitedBy: 'own',
      invitedByName: 'Owner',
      createdAt: now,
    );
    final back = TeamInvite.fromMap(i.toMap());
    expect(back.teamName, 'SEO');
    expect(back.email, 'a@b.co');
    expect(back.createdAt, now);
  });
}
