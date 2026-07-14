import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:choke/features/match/models/submission_catalog.dart';
import 'package:choke/features/match/providers/submissions_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('what the referee is offered', () {
    test('starts as the catalog we ship', () {
      final notifier = SubmissionsNotifier();

      expect(notifier.state.visible, defaultSubmissions);
    });

    test('their own submissions come after ours', () {
      // Arrange
      final notifier = SubmissionsNotifier();

      // Act
      notifier.add('baratoplata');

      // Assert — the fifteen they never have to think about stay put, and the
      // one they invented is where they left it
      expect(notifier.state.visible.last, 'baratoplata');
      expect(notifier.state.visible.length, defaultSubmissions.length + 1);
    });
  });

  group('adding', () {
    test('keeps a new technique exactly as typed', () {
      final notifier = SubmissionsNotifier();

      expect(notifier.add('Baratoplata'), isTrue);
      expect(notifier.state.custom, ['Baratoplata']);
    });

    test('refuses one already on the list, whatever the case', () {
      final notifier = SubmissionsNotifier();

      expect(notifier.add('ARMBAR'), isFalse);
      expect(notifier.state.custom, isEmpty);
    });

    test('refuses a blank', () {
      final notifier = SubmissionsNotifier();

      expect(notifier.add('   '), isFalse);
      expect(notifier.state.custom, isEmpty);
    });

    test('typing back one they removed brings ours back, not a copy', () {
      // Arrange — they removed the heel hook (a kids' division, say) and later
      // type it back in
      final notifier = SubmissionsNotifier();
      notifier.remove('heel_hook');

      // Act
      expect(notifier.add('heel_hook'), isTrue);

      // Assert — it is the CATALOG entry again. A custom copy would sit on the
      // list beside the original, and only one of the two would ever be
      // translated: two chips, one technique, one of them broken in Japanese.
      expect(notifier.state.custom, isEmpty);
      expect(notifier.state.hidden, isEmpty);
      expect(notifier.state.visible, defaultSubmissions);
    });
  });

  group('removing', () {
    test('hides one of ours', () {
      final notifier = SubmissionsNotifier();

      notifier.remove('toe_hold');

      expect(notifier.state.visible, isNot(contains('toe_hold')));
      expect(notifier.state.hidden, {'toe_hold'});
    });

    test('drops one of theirs outright', () {
      final notifier = SubmissionsNotifier();
      notifier.add('baratoplata');

      notifier.remove('baratoplata');

      expect(notifier.state.custom, isEmpty);
      expect(notifier.state.visible, defaultSubmissions);
    });

    test('restoring brings back ours and leaves theirs alone', () {
      // Arrange
      final notifier = SubmissionsNotifier();
      notifier.add('baratoplata');
      notifier.remove('heel_hook');
      notifier.remove('toe_hold');

      // Act
      notifier.restoreDefaults();

      // Assert
      expect(notifier.state.visible, [...defaultSubmissions, 'baratoplata']);
    });
  });

  group('across restarts', () {
    test('survives, added and removed alike', () async {
      // Arrange — a referee sets their list up once
      final notifier = SubmissionsNotifier();
      notifier.add('baratoplata');
      notifier.remove('heel_hook');
      await notifier.saved;

      // Act — the app is killed and comes back
      final reloaded = await SubmissionsNotifier.loadSaved();

      // Assert — a list you have to rebuild every morning is a list nobody
      // bothers editing
      expect(reloaded.custom, ['baratoplata']);
      expect(reloaded.hidden, {'heel_hook'});
      expect(reloaded.visible, isNot(contains('heel_hook')));
      expect(reloaded.visible.last, 'baratoplata');
    });

    test('edits made in the same breath are saved as one state', () async {
      // Arrange — the state is two preference keys, and they have to agree with
      // each other. A referee editing quickly fires overlapping saves.
      final notifier = SubmissionsNotifier();

      // Act — no awaits between them, exactly as the UI calls them
      notifier.add('baratoplata');
      notifier.remove('heel_hook');
      notifier.add('cejudo choke');
      notifier.remove('toe_hold');
      await notifier.saved;

      // Assert — what is on disk is the state the referee is looking at, not
      // the custom list of one snapshot beside the hidden set of another. That
      // combination is a state that never existed, and it is what they would
      // have found on the next launch.
      final reloaded = await SubmissionsNotifier.loadSaved();
      expect(reloaded.custom, notifier.state.custom);
      expect(reloaded.hidden, notifier.state.hidden);
      expect(reloaded.visible, notifier.state.visible);
    });

    test('a fresh install gets the catalog', () async {
      final loaded = await SubmissionsNotifier.loadSaved();

      expect(loaded.visible, defaultSubmissions);
    });

    test('an old install does not miss submissions we ship later', () async {
      // Arrange — saved state from a build that had never heard of, say, the
      // north–south choke
      SharedPreferences.setMockInitialValues({
        'choke:custom-submissions': <String>['baratoplata'],
        'choke:hidden-submissions': <String>[],
      });

      // Act
      final loaded = await SubmissionsNotifier.loadSaved();

      // Assert — this is why the resolved list is not what gets stored: storing
      // it flat would freeze the catalog at install time, and a referee who
      // never opened settings would never see anything we added since.
      expect(loaded.visible, containsAll(defaultSubmissions));
    });
  });
}
