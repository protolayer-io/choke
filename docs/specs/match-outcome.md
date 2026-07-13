# Spec: recording *how* a match was won

**Status:** DRAFT — for review
**Date:** 2026-07-13

---

## 1. The problem

Bob is beating Carlos 4–0. The clock is still running. Carlos catches an armbar
and Bob taps.

**Carlos won.** The app cannot say so.

Holding *Finish* sets `status: "finished"` and nothing else. The event published
to Nostr says Bob leads 4–0 and the match is over — so every dashboard, every
other client, and the app's own match list will show **Bob as the winner of a
match he lost**. The score is not merely incomplete; it is actively wrong, and
nothing in the event contradicts it.

This is not an edge case. Submission is the *point* of the sport, and it is the
one victory condition that **ignores the scoreboard entirely**. The same is true
of disqualification: the fighter who was ahead can still lose.

## 2. What is missing

The event content (kind 31415) currently carries:

```json
{
  "id": "abcd",
  "status": "waiting | in-progress | finished | canceled",
  "start_at": 1700000000,
  "paused_at": 1700000100,
  "duration": 300,
  "f1_name": "Bob", "f2_name": "Carlos",
  "f1_color": "#1BA34E", "f2_color": "#F5B800",
  "f1_pt2": 2, "f2_pt2": 0,
  "f1_pt3": 0, "f2_pt3": 0,
  "f1_pt4": 0, "f2_pt4": 0,
  "f1_adv": 0, "f2_adv": 0,
  "f1_pen": 0, "f2_pen": 0
}
```

Everything about **how the match ended** is absent: who won, and by what.

## 3. Proposal

Four new fields, all optional, all only meaningful once the match is over.

```json
{
  "…": "…",
  "status": "finished",
  "winner": "f2",
  "method": "submission",
  "submission": "armbar",
  "ended_at": 1700000180
}
```

### 3.1 `winner` — `"f1" | "f2" | "draw"`, absent while unfinished

Who won. Absent (or null) for a match that is `waiting`, `in-progress`, or
`canceled`.

### 3.2 `method` — how they won

| Value | Meaning | Beats the scoreboard? |
|---|---|---|
| `submission` | The opponent tapped, submitted verbally, or the referee stopped it (technical submission) | **Yes** |
| `points` | The clock ran out and one fighter had more points | No — it *is* the scoreboard |
| `advantages` | Points were level; advantages decided it | No |
| `penalties` | Points and advantages were level; the opponent had more penalties | No |
| `decision` | Referee's decision (still level after all of the above) | No |
| `dq` | The **loser** was disqualified | **Yes** |
| `forfeit` | The loser withdrew, no-showed, or could not continue (injury) | **Yes** |
| `draw` | No winner (formats that allow one) | — |

### 3.3 `submission` — the technique, optional free text

`"armbar"`, `"rear naked choke"`, `"triangle"`, … Present only when
`method: "submission"`, and only if the referee bothered to record it.
Deliberately **not** an enum: BJJ invents submissions faster than any spec can
enumerate them, and a referee must never be blocked from finishing a match
because the app has never heard of a *baratoplata*.

### 3.4 `ended_at` — unix seconds

When the match actually ended. Not derivable: `start_at + duration` is when the
clock *would* have run out, which is precisely what a submission prevents.

## 4. Why store the winner rather than compute it

The obvious objection: for `points`, `advantages` and `penalties`, the winner is
already implied by the numbers. Why write it down?

**Because for `submission`, `dq` and `forfeit`, it is implied by nothing.** A
consumer that computes the winner from the scoreboard gets Bob. The entire point
of this change is that it must get Carlos.

And even for the point-based endings, deriving the winner means every dashboard
re-implementing the tie-break ladder (points → advantages → fewer penalties →
referee decision) and getting it subtly different. The referee's device is the
only thing that was actually *at the match*. It should state the result, not
leave every reader to infer it.

## 5. Backwards and forwards compatibility

The fields are **additive**, and both directions already behave correctly:

- **An old app reading a new event.** `Match.fromJson` reads named keys and
  ignores everything else, so a new event parses fine. The old app shows the
  score and "finished" — no worse than today, and no crash.
- **A new app reading an old event.** The fields are absent → `winner` and
  `method` are null. The app falls back to computing the winner from the
  scoreboard, which is exactly what it does today.

No version bump on the event kind. No migration. Matches published before this
change stay readable; they simply cannot say how they ended — which is the truth
about them.

## 6. The referee's hands

The constraint that shapes the UI: a referee is standing over two people, one of
whom has just tapped, holding a phone in one hand. **The common case must be two
taps, and it must be impossible to record the wrong fighter by accident.**

Today, holding *Finish* ends the match immediately. Proposed:

```
   ┌──────────────────────────────────────┐
   │  How did it end?                     │
   │                                      │
   │  ┌────────────────────────────────┐  │
   │  │  SUBMISSION                    │  │  → then: which fighter?
   │  └────────────────────────────────┘  │
   │  ┌────────────────────────────────┐  │
   │  │  POINTS · Bob wins 4–0     ✓   │  │  ← pre-computed, one tap
   │  └────────────────────────────────┘  │
   │                                      │
   │  Disqualification · Forfeit · Draw   │  ← secondary, less common
   │  Referee decision                    │
   └──────────────────────────────────────┘
```

- **Hold-to-finish opens this sheet** rather than ending the match outright. The
  hold stays: it is what keeps a stray thumb from ending a live match.
- **Points is pre-computed and pre-selected**, showing the result the scoreboard
  implies. A match that goes to the clock is one tap.
- **Submission asks which fighter, in their own colours** — the same two colours
  the referee has been tapping all match. The technique is an optional text
  field, skippable.
- **The clock running out** does *not* open the sheet. It finishes on points
  automatically, as it does today, with the winner computed. A referee who wants
  to correct it can still amend the outcome.
- **Cancel** stays exactly as it is: a voided match, no winner, no method. It is
  not a result — it is the absence of one.

## 7. What this does *not* change

- Scoring, penalties, advantages: untouched.
- The `canceled` status: untouched.
- The event kind, the d-tag, addressable replacement, the convergence
  guarantees: untouched.

## 8. Open questions — decide before implementing

1. **Penalties are currently just counted.** Under IBJJF, the 2nd penalty gives
   an advantage to the opponent, the 3rd gives two points, and the 4th is a
   disqualification. The app counts them and applies none of that. That is a
   pre-existing simplification and this spec does **not** change it — but it
   means an automatically computed `points` winner can disagree with a real
   referee. Fix the penalty rules as part of this, or leave it and let the
   referee override?
2. **Is `draw` real for us?** IBJJF has no draws in most brackets — it goes to
   referee decision. Keeping the value costs nothing and some rulesets use it.
   Include, or drop?
3. **Should `dq` carry a reason?** (`"illegal knee reap"`, …) Same free-text
   shape as `submission`. Useful for a tournament record; one more thing to type
   at the worst possible moment.
4. **Should `ended_at` be filled in for matches that expire on the clock?** It is
   knowable (`start_at + duration`, adjusted for stoppages), and filling it in
   makes every finished match uniform.

## 9. Proposed phasing

Each phase is a PR that leaves `main` shippable.

1. **Schema + model.** `winner`, `method`, `submission`, `ended_at` on `Match`,
   with JSON round-trip tests and the compatibility cases in §5 pinned as tests.
   The winner-from-scoreboard tie-break ladder lands here, tested on its own. No
   UI: nothing sets the fields yet, so nothing changes.
2. **The outcome sheet.** Hold-to-finish opens it; the match finishes with an
   outcome. Strings in all four locales (`en`, `es`, `pt`, `ja`).
3. **Showing it.** The match list and the match screen say *"Carlos won by
   submission (armbar)"* instead of showing a scoreboard that lies. Update
   `docs/SPEC.md`, which is the event schema other clients read.
