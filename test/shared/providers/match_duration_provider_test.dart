import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:choke/shared/providers/match_duration_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The notifier persists through SharedPreferences, a plugin that does not
    // exist on the test host unless it is mocked.
    SharedPreferences.setMockInitialValues({});
  });

  group('loadSavedDuration', () {
    test('returns the default when nothing has been saved', () async {
      // Arrange — empty preferences, set in setUp

      // Act
      final duration = await MatchDurationNotifier.loadSavedDuration();

      // Assert
      expect(duration, defaultMatchDuration);
    });

    test('returns the stored value when it is a valid option', () async {
      // Arrange
      SharedPreferences.setMockInitialValues(
        {'choke:default-match-duration': 480},
      );

      // Act
      final duration = await MatchDurationNotifier.loadSavedDuration();

      // Assert
      expect(duration, 480);
    });

    test('falls back to the default when the stored value is not an option',
        () async {
      // Arrange — 999 is not in defaultDurationOptions; a corrupt or stale
      // value must never leak into the clock.
      SharedPreferences.setMockInitialValues(
        {'choke:default-match-duration': 999},
      );

      // Act
      final duration = await MatchDurationNotifier.loadSavedDuration();

      // Assert
      expect(duration, defaultMatchDuration);
    });
  });

  group('hydrate', () {
    test('adopts a valid saved duration synchronously', () {
      // Arrange
      final notifier = MatchDurationNotifier();

      // Act
      notifier.hydrate(180);

      // Assert
      expect(notifier.state, 180);
    });

    test('normalizes an invalid duration back to the default', () {
      // Arrange
      final notifier = MatchDurationNotifier();

      // Act
      notifier.hydrate(1234);

      // Assert
      expect(notifier.state, defaultMatchDuration);
    });
  });

  group('setDuration', () {
    test('updates state and persists a valid option', () async {
      // Arrange
      final notifier = MatchDurationNotifier();

      // Act
      await notifier.setDuration(600);

      // Assert — both the live state and the value the next launch will read
      expect(notifier.state, 600);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('choke:default-match-duration'), 600);
    });

    test('normalizes an invalid duration to the default before persisting',
        () async {
      // Arrange
      final notifier = MatchDurationNotifier();

      // Act
      await notifier.setDuration(42);

      // Assert
      expect(notifier.state, defaultMatchDuration);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('choke:default-match-duration'),
          defaultMatchDuration);
    });
  });

  group('formatDuration', () {
    test('formats whole minutes as mm:ss', () {
      // Arrange + Act + Assert
      expect(formatDuration(300), '05:00');
      expect(formatDuration(600), '10:00');
    });

    test('pads seconds and minutes below ten', () {
      // Arrange + Act + Assert
      expect(formatDuration(65), '01:05');
      expect(formatDuration(0), '00:00');
    });
  });
}
