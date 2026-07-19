import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:choke/features/match/providers/submissions_provider.dart';

/// A store whose writes always fail — a full disk, a broken platform channel.
class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore() : super.empty();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    throw Exception('disk full');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hydrate', () {
    test('adopts the state read back from disk', () {
      // Arrange — main() loads the saved list before the first frame and
      // hands it over; the picker must never pop up empty and fill later
      final notifier = SubmissionsNotifier();
      addTearDown(notifier.dispose);
      const saved = SubmissionsState(
        custom: ['baratoplata'],
        hidden: {'armbar'},
      );

      // Act
      notifier.hydrate(saved);

      // Assert
      expect(notifier.state.custom, ['baratoplata']);
      expect(notifier.state.hidden, {'armbar'});
    });
  });

  group('a failed save', () {
    test('does not poison the chain: the next edit is still saved', () async {
      // Arrange — every write fails (disk full, broken channel)
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _FailingStore();
      final notifier = SubmissionsNotifier();
      addTearDown(notifier.dispose);

      // Act — the referee adds a technique; the write fails behind the scenes
      notifier.add('baratoplata');
      await notifier.saved; // must complete, not throw

      // Assert — the in-memory list still has it: losing a save is a
      // nuisance, losing the referee's tap would be a lie on the mat
      expect(notifier.state.custom, ['baratoplata']);

      // Act — the platform recovers, and the next edit saves normally
      SharedPreferencesStorePlatform.instance =
          InMemorySharedPreferencesStore.empty();
      notifier.add('twister');
      await notifier.saved;

      // Assert — the chain was not left permanently broken by the failure
      final reloaded = await SubmissionsNotifier.loadSaved();
      expect(reloaded.custom, contains('twister'));
    });
  });
}
