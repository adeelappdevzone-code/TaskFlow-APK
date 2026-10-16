import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/chat_store.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/screens/messages_screen.dart';
import 'package:taskflow/screens/team_screen.dart';

void main() {
  final now = DateTime.now();
  Team team(String id, String name, List<String> ids) => Team(
        id: id,
        name: name,
        color: 0xFF16A34A,
        ownerId: ids.first,
        memberIds: ids,
        managerIds: const [],
        members: {
          for (final u in ids)
            u: TeamMemberInfo(
                name: {'me': 'Adeel', 'wa': 'Waseem', 'ma': 'Awais'}[u] ?? u, email: '$u@x.com'),
        },
        createdAt: now,
        updatedAt: now,
      );
  final seo = team('T1', 'SEO Dev', ['me', 'wa']);
  final ui = team('T2', 'UI UX', ['me', 'ma', 'wa']);

  final waChat = Chat(
    id: directChatId('me', 'wa'),
    type: ChatType.direct,
    memberIds: const ['me', 'wa'],
    names: const {'me': 'Adeel', 'wa': 'Waseem'},
    lastText: 'Banner ready?',
    lastAt: now.subtract(const Duration(minutes: 3)),
    lastFrom: 'wa',
    read: {'me': now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch},
    createdBy: 'wa',
  );
  final request = Chat(
    id: 'req_zz_me@x.com',
    type: ChatType.direct,
    memberIds: const ['zz'],
    names: const {'zz': 'Zara Client'},
    inviteEmail: 'me@x.com',
    status: 'pending',
    createdBy: 'zz',
  );

  void seed({List<Chat> requests = const []}) {
    TeamStore.instance
      ..teams = [seo, ui]
      ..invites = []
      ..setForTest(uid: 'me', tasks: {});
    ChatStore.instance.setForTest(
        uid: 'me',
        direct: [waChat],
        requests: requests,
        messages: {
          waChat.id: [
            ChatMessage(
                id: '1', from: 'wa', fromName: 'Waseem', text: 'Banner ready?', at: waChat.lastAt!),
          ],
        });
  }

  group('chat data', () {
    test('direct chat id is the same whoever starts it', () {
      expect(directChatId('b', 'a'), 'a_b');
      expect(directChatId('a', 'b'), 'a_b');
    });

    test('unread only for messages from others after my last read', () {
      expect(waChat.unreadFor('me'), isTrue);
      expect(waChat.unreadFor('wa'), isFalse); // own message
      final read = Chat(
          id: 'x',
          type: ChatType.direct,
          lastAt: now,
          lastFrom: 'wa',
          read: {'me': now.millisecondsSinceEpoch});
      expect(read.unreadFor('me'), isFalse);
    });

    test('contacts: everyone in my teams once, with all shared teams', () {
      seed();
      final c = ChatStore.instance.contacts();
      expect(c.map((x) => x.name), ['Awais', 'Waseem']);
      expect(c.last.teamIds, ['T1', 'T2']);
      expect(c.last.email, 'wa@x.com');
    });

    test('titles, team chats and the unread count', () {
      seed(requests: [request]);
      final s = ChatStore.instance;
      expect(s.titleOf(waChat), 'Waseem');
      expect(s.titleOf(request), 'Zara Client');
      expect(s.teamChats.map(s.titleOf).toSet(), {'SEO Dev', 'UI UX'});
      expect(s.subtitleOf(waChat), 'SEO Dev, UI UX');
      expect(s.unreadCount, 2); // Waseem's message + the request
    });

    test('sending updates the last message and marks it read for me', () {
      seed();
      final s = ChatStore.instance;
      s.send(s.byId(waChat.id)!, '  Yes, sending now  ');
      final c = s.byId(waChat.id)!;
      expect(c.lastText, 'Yes, sending now');
      expect(c.lastFrom, 'me');
      expect(c.unreadFor('me'), isFalse);
      s.send(s.teamChats.first, 'Morning team');
      expect(s.teamChats.first.lastText, 'Morning team');
    });

    test('openDirect reuses the existing chat', () {
      seed();
      final id = ChatStore.instance.openDirect(const Contact('wa', 'Waseem', 'wa@x.com', ['T1']));
      expect(id, waChat.id);
    });
  });

  testWidgets('laptop: list with tabs, open a chat, send a message', (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seed(requests: [request]);
    MessagesScreen.select.value = null;
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const MessagesScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Pick a conversation'), findsOneWidget);
    expect(find.text('Waseem'), findsOneWidget);
    expect(find.text('Zara Client'), findsOneWidget);

    await tester.tap(find.text('Waseem'));
    await tester.pumpAndSettle();
    expect(find.text('Banner ready?'), findsWidgets);
    await tester.enterText(find.byType(TextField).last, 'On it');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('You: On it'), findsOneWidget);

    await tester.tap(find.text('Group'));
    await tester.pumpAndSettle();
    expect(find.text('SEO Dev'), findsOneWidget);
    expect(find.text('UI UX'), findsOneWidget);
  });

  testWidgets('phone: chat request can be accepted', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seed(requests: [request]);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const MessagesScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Zara Client'), findsOneWidget);
    await tester.tap(find.byTooltip('Accept'));
    await tester.pumpAndSettle();
    expect(ChatStore.instance.requests, isEmpty);
  });

  testWidgets('invite dialog offers people from my other teams', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seed();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
              onPressed: () => showInviteDialog(context, seo), child: const Text('open')),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('People you work with'), findsOneWidget);
    // Awais is in UI UX but not in SEO Dev; Waseem is already in SEO Dev.
    expect(find.text('Awais'), findsOneWidget);
    expect(find.text('Waseem'), findsNothing);
  });
}
