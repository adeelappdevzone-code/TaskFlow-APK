import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taskflow/core/theme.dart';
import 'package:taskflow/data/app_store.dart';
import 'package:taskflow/data/images.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/data/team_models.dart';
import 'package:taskflow/data/team_store.dart';
import 'package:taskflow/screens/task_page.dart';
import 'package:taskflow/widgets/common.dart';
import 'package:taskflow/widgets/images.dart';

void main() {
  const img = 'https://res.cloudinary.com/voejff1h/image/upload/v1/taskflow/abc.jpg';

  test('image addresses and small copies', () {
    expect(isImageUrl(img), isTrue);
    expect(isImageUrl('https://x.com/a.PNG'), isTrue);
    expect(isImageUrl('https://docs.google.com/document/d/1'), isFalse);
    expect(thumbUrl(img, width: 300),
        'https://res.cloudinary.com/voejff1h/image/upload/c_limit,w_300,q_auto,f_auto/v1/taskflow/abc.jpg');
    expect(thumbUrl('https://x.com/a.png'), 'https://x.com/a.png');
  });

  test('upload sends the unsigned preset and returns the address', () async {
    late http.BaseRequest sent;
    final client = MockClient.streaming((req, body) async {
      sent = req;
      final fields = utf8.decode(await body.toBytes(), allowMalformed: true);
      expect(fields, contains('taskflow'));
      return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({'secure_url': img}))), 200);
    });
    final url =
        await uploadImage(XFile.fromData(utf8.encode('fake'), name: 'a.jpg'), client: client);
    expect(url, img);
    expect(sent.url.toString(), 'https://api.cloudinary.com/v1_1/voejff1h/image/upload');
  });

  test('upload error is readable', () async {
    final client = MockClient((_) async => http.Response(
        jsonEncode({
          'error': {'message': 'Upload preset not found'}
        }),
        400));
    expect(
        () => uploadImage(XFile.fromData(utf8.encode('x'), name: 'a.jpg'), client: client),
        throwsA(isA<ImageUploadError>()
            .having((e) => e.message, 'message', contains('Upload preset not found'))));
  });

  test('profile photo travels with the member info', () {
    const i = TeamMemberInfo(name: 'A', email: 'a@x.com', photo: img);
    final back = TeamMemberInfo.fromMap(i.toMap());
    expect(back.photo, img);
    expect(back.sameAs(i), isTrue);
    expect(const TeamMemberInfo(name: 'A', email: 'a').toMap().containsKey('photo'), isFalse);
  });

  testWidgets('task shows image links as pictures; avatar falls back to letters', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final t = TaskItem(
        id: 't1',
        title: 'Banner',
        startAt: now,
        createdAt: now,
        updatedAt: now,
        links: const [
          TaskLink(title: 'Image', url: img),
          TaskLink(title: 'Brief', url: 'https://docs.google.com/document/d/1'),
        ]);
    AppStore.instance.tasks = [t];
    TeamStore.instance
      ..teams = []
      ..setForTest(uid: 'me');
    await tester
        .pumpWidget(MaterialApp(theme: buildAppTheme(), home: const TaskPage(taskId: 't1')));
    await tester.pumpAndSettle();
    expect(find.byType(ImageThumb), findsOneWidget);
    expect(find.text('Brief'), findsOneWidget);
    expect(find.text('Image'), findsNothing); // shown as a picture, not a link row

    await tester.pumpWidget(const MaterialApp(home: Avatar(name: 'Adeel App', url: img)));
    await tester.pumpAndSettle();
    expect(find.text('AA'), findsOneWidget); // no network in tests: letters
    AppStore.instance.tasks = [];
  });
}
