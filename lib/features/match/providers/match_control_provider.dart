import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/match.dart';
import '../../../services/nostr/nostr_service.dart';
import '../../home/providers/home_providers.dart';

/// State for the match control screen
class MatchControlState {
  final Match match;
  final int remainingSeconds;
  final bool isPublishing;
  final List<_UndoEntry> undoStack;

  MatchControlState({
    required this.match,
    required this.remainingSeconds,
    this.isPublishing = false,
    this.undoStack = const [],
  });

  bool get isWaiting => match.status == MatchStatus.waiting;
  bool get isRunning => match.status == MatchStatus.inProgress;
  bool get isFinished =>
      match.status == MatchStatus.finished ||
      match.status == MatchStatus.canceled;
  bool get canUndo => undoStack.isNotEmpty && isRunning;

  /// The match is under way but its clock is stopped (fighters off the mat).
  bool get isPaused => isRunning && match.pausedAt != null;

  MatchControlState copyWith({
    Match? match,
    int? remainingSeconds,
    bool? isPublishing,
    List<_UndoEntry>? undoStack,
  }) {
    return MatchControlState(
      match: match ?? this.match,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      isPublishing: isPublishing ?? this.isPublishing,
      undoStack: undoStack ?? this.undoStack,
    );
  }
}

/// Tracks which field was changed for undo
class _UndoEntry {
  /// 1 = fighter 1, 2 = fighter 2
  final int fighter;

  /// Field name: 'pt2', 'pt3', 'pt4', 'adv', 'pen'
  final String field;

  /// Applied change: +1 for an add, -1 for a subtract
  final int delta;

  _UndoEntry(this.fighter, this.field, [this.delta = 1]);
}

/// Manages match control: timer, scoring, publishing
class MatchControlNotifier extends StateNotifier<MatchControlState> {
  final NostrService _nostrService;
  final MatchFeedNotifier? _feedNotifier;
  Timer? _timer;
  bool _pendingPublish = false;

  MatchControlNotifier(Match match, this._nostrService, [this._feedNotifier])
      : super(MatchControlState(
          match: match,
          remainingSeconds: _calculateRemaining(match),
        )) {
    if (match.status == MatchStatus.inProgress) {
      if (match.pausedAt != null) {
        // A paused clock stays paused, however long the app was away.
        return;
      }
      // The clock may have run out while the app was closed — a match is
      // never left in progress past its own duration.
      if (state.remainingSeconds <= 0) {
        _finish();
      } else {
        _startTimer();
      }
    }
  }

  static int _calculateRemaining(Match match) {
    if (match.status == MatchStatus.waiting) {
      return match.duration;
    }
    if (match.startAt == null || match.startAt == 0) {
      return match.duration;
    }
    // While paused the clock reads as it did at the moment it was stopped.
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final elapsed = (match.pausedAt ?? now) - match.startAt!;
    return (match.duration - elapsed).clamp(0, match.duration);
  }

  /// Start the match: set status to inProgress, set startAt, start timer
  void startMatch() {
    if (!state.isWaiting) return;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final updated = state.match.copyWith(
      status: MatchStatus.inProgress,
      startAt: now,
    );

    state = state.copyWith(
      match: updated,
      remainingSeconds: updated.duration,
    );

    _startTimer();
    _publishState();
  }

  /// Stop the clock without ending the match — fighters left the mat, a
  /// grip needs resetting, the referee is conferring. Scoring stays open.
  void pauseMatch() {
    if (!state.isRunning || state.isPaused) return;

    _timer?.cancel();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final paused = state.match.copyWith(pausedAt: now);

    // Freeze the clock at what it actually reads now, not at the last tick:
    // the timer may have been throttled (app backgrounded, busy UI thread),
    // and a stale value would put seconds back on the clock.
    final remaining = _calculateRemaining(paused);
    if (remaining <= 0) {
      // Time ran out while the timer was stalled — the match is over, and a
      // finished match cannot be paused.
      _finish();
      return;
    }

    state = state.copyWith(match: paused, remainingSeconds: remaining);
    _publishState();
  }

  /// Restart the clock with the time that was left when it stopped.
  ///
  /// The stoppage is charged to [Match.startAt], not to the fighters: moving
  /// the start forward by the length of the pause leaves the remaining time
  /// exactly where it was.
  void resumeMatch() {
    if (!state.isPaused) return;

    final match = state.match;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final stoppage = now - match.pausedAt!;

    final resumed = match.copyWith(
      startAt: match.startAt! + stoppage,
      pausedAt: null,
    );

    state = state.copyWith(
      match: resumed,
      remainingSeconds: _calculateRemaining(resumed),
    );

    _startTimer();
    _publishState();
  }

  /// Score: +2 (takedown/sweep)
  void scorePt2(int fighter) => _score(fighter, 'pt2');

  /// Score: +3 (guard pass)
  void scorePt3(int fighter) => _score(fighter, 'pt3');

  /// Score: +4 (mount/back take)
  void scorePt4(int fighter) => _score(fighter, 'pt4');

  /// Add advantage
  void scoreAdv(int fighter) => _score(fighter, 'adv');

  /// Add penalty
  void scorePen(int fighter) => _score(fighter, 'pen');

  /// Subtract: -2 (takedown/sweep count)
  void subtractPt2(int fighter) => _subtract(fighter, 'pt2');

  /// Subtract: -3 (guard pass count)
  void subtractPt3(int fighter) => _subtract(fighter, 'pt3');

  /// Subtract: -4 (mount/back take count)
  void subtractPt4(int fighter) => _subtract(fighter, 'pt4');

  /// Remove advantage
  void subtractAdv(int fighter) => _subtract(fighter, 'adv');

  /// Remove penalty
  void subtractPen(int fighter) => _subtract(fighter, 'pen');

  void _score(int fighter, String field) {
    if (!state.isRunning) return;

    state = state.copyWith(
      match: _applyDelta(state.match, fighter, field, 1),
      undoStack: [...state.undoStack, _UndoEntry(fighter, field, 1)],
    );

    _publishState();
  }

  void _subtract(int fighter, String field) {
    if (!state.isRunning) return;
    if (_count(state.match, fighter, field) <= 0) return;

    state = state.copyWith(
      match: _applyDelta(state.match, fighter, field, -1),
      undoStack: [...state.undoStack, _UndoEntry(fighter, field, -1)],
    );

    _publishState();
  }

  /// Undo last scoring action (reverts adds and subtracts alike)
  void undo() {
    if (!state.canUndo) return;

    final stack = List<_UndoEntry>.from(state.undoStack);
    final entry = stack.removeLast();

    state = state.copyWith(
      match: _applyDelta(state.match, entry.fighter, entry.field, -entry.delta),
      undoStack: stack,
    );
    _publishState();
  }

  static int _count(Match m, int fighter, String field) {
    if (fighter == 1) {
      return switch (field) {
        'pt2' => m.f1Pt2,
        'pt3' => m.f1Pt3,
        'pt4' => m.f1Pt4,
        'adv' => m.f1Adv,
        'pen' => m.f1Pen,
        _ => 0,
      };
    }
    return switch (field) {
      'pt2' => m.f2Pt2,
      'pt3' => m.f2Pt3,
      'pt4' => m.f2Pt4,
      'adv' => m.f2Adv,
      'pen' => m.f2Pen,
      _ => 0,
    };
  }

  static Match _applyDelta(Match m, int fighter, String field, int delta) {
    int next(int v) => (v + delta).clamp(0, 999);

    if (fighter == 1) {
      return switch (field) {
        'pt2' => m.copyWith(f1Pt2: next(m.f1Pt2)),
        'pt3' => m.copyWith(f1Pt3: next(m.f1Pt3)),
        'pt4' => m.copyWith(f1Pt4: next(m.f1Pt4)),
        'adv' => m.copyWith(f1Adv: next(m.f1Adv)),
        'pen' => m.copyWith(f1Pen: next(m.f1Pen)),
        _ => m,
      };
    }
    return switch (field) {
      'pt2' => m.copyWith(f2Pt2: next(m.f2Pt2)),
      'pt3' => m.copyWith(f2Pt3: next(m.f2Pt3)),
      'pt4' => m.copyWith(f2Pt4: next(m.f2Pt4)),
      'adv' => m.copyWith(f2Adv: next(m.f2Adv)),
      'pen' => m.copyWith(f2Pen: next(m.f2Pen)),
      _ => m,
    };
  }

  /// Finish the match
  void finishMatch() => _finish();

  void _finish() {
    if (state.isFinished) return;

    _timer?.cancel();
    final updated = state.match.copyWith(
      status: MatchStatus.finished,
      pausedAt: null,
    );
    state = state.copyWith(match: updated, remainingSeconds: 0);
    _publishState();
  }

  /// Cancel the match
  void cancelMatch() {
    if (state.isFinished) return;

    _timer?.cancel();
    final updated = state.match.copyWith(
      status: MatchStatus.canceled,
      pausedAt: null,
    );
    state = state.copyWith(match: updated);
    _publishState();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _calculateRemaining(state.match);
      state = state.copyWith(remainingSeconds: remaining);

      // Regulation time is over: the match finishes on its own.
      if (remaining <= 0) {
        _finish();
      }
    });
  }

  /// Publish current match state to Nostr
  Future<void> _publishState() async {
    if (state.isPublishing) {
      _pendingPublish = true;
      return;
    }

    state = state.copyWith(isPublishing: true);

    try {
      final match = state.match;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Update home feed immediately (don't wait for relay round-trip)
      _feedNotifier?.addLocal(match);
      final expiration = now + 604800; // 1 week

      await _nostrService.publishAddressableEvent(
        dTag: match.id,
        content: match.toJsonString(),
        additionalTags: [
          ['expiration', expiration.toString()],
        ],
      );

      debugPrint(
          'MatchControl: published match ${match.id} (${match.status.name})');
    } catch (e) {
      debugPrint('MatchControl: publish failed: $e');
    } finally {
      state = state.copyWith(isPublishing: false);

      // If there was a queued publish, do it now
      if (_pendingPublish) {
        _pendingPublish = false;
        _publishState();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Provider for the currently active match being controlled.
/// Set this before navigating to MatchControlScreen.
final activeMatchProvider = StateProvider<Match?>((ref) => null);

/// Provider for the match control notifier.
/// Reads the active match from [activeMatchProvider].
final matchControlProvider =
    StateNotifierProvider<MatchControlNotifier, MatchControlState>((ref) {
  final match = ref.read(activeMatchProvider);
  if (match == null) {
    throw StateError(
        'activeMatchProvider must be set before using matchControlProvider');
  }
  final nostrService = ref.watch(nostrServiceProvider);
  final feedNotifier = ref.read(matchFeedProvider.notifier);
  return MatchControlNotifier(match, nostrService, feedNotifier);
});
