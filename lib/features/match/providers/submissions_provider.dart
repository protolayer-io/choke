import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:choke/features/match/models/submission_catalog.dart';

const _kCustomKey = 'choke:custom-submissions';
const _kHiddenKey = 'choke:hidden-submissions';

/// The submissions this referee is offered, in the order they see them.
///
/// Two pieces of state, because they mean different things: the ones the user
/// **added** (kept verbatim — that string is what gets published) and the ones
/// from [defaultSubmissions] they **hid**. Storing the resolved list flat would
/// freeze the catalog at install time, and a referee who never opened settings
/// would never see a submission we shipped later.
class SubmissionsState {
  const SubmissionsState({this.custom = const [], this.hidden = const {}});

  /// Submissions the user added, oldest first. Published exactly as typed.
  final List<String> custom;

  /// Catalog ids the user removed.
  final Set<String> hidden;

  /// What the picker shows: the catalog minus what they hid, then their own.
  List<String> get visible => [
        ...defaultSubmissions.where((s) => !hidden.contains(s)),
        ...custom,
      ];

  /// A copy with either half replaced.
  SubmissionsState copyWith({List<String>? custom, Set<String>? hidden}) {
    return SubmissionsState(
      custom: custom ?? this.custom,
      hidden: hidden ?? this.hidden,
    );
  }
}

/// Persists the referee's submission list.
///
/// Hydrated in main() before the first frame, the same way MatchDurationNotifier
/// is: a picker that pops up empty and fills a beat later is a picker a referee
/// taps through by accident.
final submissionsProvider =
    StateNotifierProvider<SubmissionsNotifier, SubmissionsState>((ref) {
  return SubmissionsNotifier();
});

/// Reads, edits and saves the referee's submission list.
class SubmissionsNotifier extends StateNotifier<SubmissionsState> {
  /// Starts from [initial], or from the catalog we ship.
  ///
  /// Pass the result of [loadSaved] via [hydrate] rather than here when the
  /// app is starting up; the provider builds this with no argument.
  SubmissionsNotifier([SubmissionsState? initial])
      : super(initial ?? const SubmissionsState());

  /// Every save so far, chained.
  ///
  /// The state is two preference keys, and a save has to leave them agreeing
  /// with each other. Two `_persist()` calls racing — a referee removing a
  /// technique and adding one in the same second — could otherwise land the
  /// custom list of one snapshot beside the hidden set of the other, and the
  /// list they see on the next launch would be a state that never existed.
  Future<void> _saves = Future.value();

  /// Resolves when every edit made so far is on disk.
  ///
  /// Mutations do not block on this: a chip must never wait for a write. This
  /// exists for the code that genuinely has to know — chiefly tests, which
  /// would otherwise sleep and hope.
  Future<void> get saved => _saves;

  /// Read the saved list. Call before runApp().
  static Future<SubmissionsState> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    return SubmissionsState(
      custom: prefs.getStringList(_kCustomKey) ?? const [],
      hidden: (prefs.getStringList(_kHiddenKey) ?? const []).toSet(),
    );
  }

  /// Adopt the state read back from disk, before the first frame.
  void hydrate(SubmissionsState saved) => state = saved;

  /// Add a submission the user typed.
  ///
  /// Returns false when it is already on the list. Typing back one they had
  /// removed **unhides the catalog entry** rather than adding a custom copy —
  /// otherwise the same technique would live under two names, one publishing
  /// `armbar` and the other `Armbar`.
  bool add(String submission) {
    final value = submission.trim();
    if (value.isEmpty) return false;

    final resurrected = _hiddenDefaultMatching(value);
    if (resurrected != null) {
      state = state.copyWith(hidden: {...state.hidden}..remove(resurrected));
      _persist();
      return true;
    }

    final folded = value.toLowerCase();
    if (state.visible.any((s) => s.toLowerCase() == folded)) return false;

    state = state.copyWith(custom: [...state.custom, value]);
    _persist();
    return true;
  }

  /// Remove a submission: a custom one is dropped, a catalog one is hidden.
  ///
  /// Hiding rather than deleting is what makes [restoreDefaults] possible — and
  /// what keeps a removed default from silently reappearing on the next update.
  void remove(String submission) {
    if (defaultSubmissions.contains(submission)) {
      state = state.copyWith(hidden: {...state.hidden, submission});
    } else {
      state = state.copyWith(
        custom: state.custom.where((s) => s != submission).toList(),
      );
    }
    _persist();
  }

  /// Bring back every built-in submission, leaving the user's own alone.
  void restoreDefaults() {
    state = state.copyWith(hidden: const {});
    _persist();
  }

  /// The catalog id a typed submission would resurrect, if any.
  String? _hiddenDefaultMatching(String value) {
    final folded = value.toLowerCase();
    for (final id in state.hidden) {
      if (id.toLowerCase() == folded) return id;
    }
    return null;
  }

  /// Save the state as it is *now*, after every save already queued.
  ///
  /// The snapshot is taken here rather than read inside the write, so a save
  /// always writes the state it was asked to write — not whatever the referee
  /// has tapped since. Chaining onto [_saves] keeps the two keys from
  /// interleaving across concurrent edits.
  void _persist() {
    final snapshot = state;
    _saves = _saves.then((_) => _write(snapshot)).catchError((Object e, StackTrace st) {
      // A failed write must not poison the chain: the next edit still deserves
      // its chance to be saved. Losing a submission from a list is a nuisance;
      // silently refusing to save anything ever again is a broken app.
      debugPrint('Saving submissions failed: $e\n$st');
    });
  }

  Future<void> _write(SubmissionsState snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kCustomKey, snapshot.custom);
    await prefs.setStringList(_kHiddenKey, snapshot.hidden.toList());
  }
}
