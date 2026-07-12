import 'package:flutter_test/flutter_test.dart';
import 'package:choke/services/key_management/key_manager.dart';
import 'package:choke/services/nostr/nostr_service.dart';

void main() {
  group('nextCreatedAt', () {
    test('is strictly increasing for the same match, even within one second',
        () {
      // Arrange — relays keep a single addressable event per match and drop
      // same-second updates, so rapid publishes must never share a timestamp
      final service = NostrService(KeyManager());

      // Act — three "publishes" back to back, all within the same second
      final first = service.nextCreatedAt('abcd');
      final second = service.nextCreatedAt('abcd');
      final third = service.nextCreatedAt('abcd');

      // Assert
      expect(second, greaterThan(first));
      expect(third, greaterThan(second));
    });

    test('starts from the wall clock', () {
      // Arrange
      final service = NostrService(KeyManager());
      final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Act
      final createdAt = service.nextCreatedAt('abcd');

      // Assert
      final after = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(createdAt, greaterThanOrEqualTo(before));
      expect(createdAt, lessThanOrEqualTo(after + 1));
    });

    test('tracks each match independently', () {
      // Arrange — pushing one match's clock forward must not skew another's
      final service = NostrService(KeyManager());
      for (var i = 0; i < 5; i++) {
        service.nextCreatedAt('aaaa');
      }
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Act
      final other = service.nextCreatedAt('bbbb');

      // Assert — the fresh match starts at the wall clock, not at aaaa's +5
      expect(other, lessThanOrEqualTo(now + 1));
    });
  });
}
