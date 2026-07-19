import 'package:flutter_test/flutter_test.dart';
import 'package:choke/services/nostr/relay/nostr_relay_backend.dart';

void main() {
  group('Filter.toJson', () {
    test('omits every unset field rather than sending nulls', () {
      // Arrange — a relay reads an explicit null as a constraint nothing can
      // satisfy, so an empty filter must serialize to an empty object
      const filter = Filter();

      // Act
      final json = filter.toJson();

      // Assert
      expect(json, isEmpty);
    });

    test('includes every field that is set, under its NIP-01 name', () {
      // Arrange
      final filter = Filter(
        kinds: const [31415],
        authors: ['a' * 64],
        ids: ['b' * 64],
        search: 'armbar',
        since: 100,
        until: 200,
        limit: 50,
      );

      // Act
      final json = filter.toJson();

      // Assert
      expect(json, {
        'kinds': [31415],
        'authors': ['a' * 64],
        'ids': ['b' * 64],
        'search': 'armbar',
        'since': 100,
        'until': 200,
        'limit': 50,
      });
    });

    test('keeps set and unset fields independent', () {
      // Arrange — only kinds constrained
      const filter = Filter(kinds: [31415]);

      // Act
      final json = filter.toJson();

      // Assert
      expect(json, {
        'kinds': [31415]
      });
    });
  });
}
