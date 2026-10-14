import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/utils.dart';

void main() {
  test('initials', () {
    expect(initials('Andi Pratama'), 'AP');
    expect(initials('usman'), 'U');
  });
}
