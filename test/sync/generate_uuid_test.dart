import 'package:alnaser/services/sync/sync_security.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generateUuid never repeats in a tight loop (same clock tick)', () {
    final ids = {for (var i = 0; i < 5000; i++) SyncSecurity.generateUuid()};
    expect(ids.length, 5000);
  });

  test('generateUuid keeps the 64-hex format', () {
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(SyncSecurity.generateUuid()), isTrue);
  });
}
