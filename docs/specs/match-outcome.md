# Spec: recording *how* a match was won

**Status:** DRAFT — for review (round 2)
**Date:** 2026-07-13
**Decisions taken:** apply the IBJJF penalty ladder (§5) · `dq_reason` as a
standard category plus optional free-text detail (§3.4) · always record
`ended_at` (§3.5)

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

Six new fields, all optional, all only meaningful once the match is over.

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

### 3.4 `dq_reason` — why they were disqualified

Present only when `method: "dq"`. This is where the research changed the shape
of the proposal.

**The categories are standard. The infractions are not.** IBJJF subdivides fouls
into *serious* (which accumulate penalties) and *severe* (immediate
disqualification), and severe fouls further into *technical* and *disciplinary*
— the difference being that a disciplinary foul disqualifies an athlete from the
**competition**, not merely the match. Those categories are stable and worth
encoding.

The specific infraction is not. Whether a knee reap is illegal depends on the
ruleset, the belt and the age division; ADCC's list is different from IBJJF's
again. Enumerating infractions would mean shipping a rulebook and versioning it.

So: a small enum for what a record actually needs to be sortable by, plus free
text for what happened.

| `dq_reason` | Meaning |
|---|---|
| `accumulated_penalties` | The fourth penalty (see §5) |
| `technical_foul` | Severe technical foul — illegal technique, illegal grip, improper attire. Disqualified from the **match**. |
| `disciplinary_foul` | Severe disciplinary foul — unsportsmanlike conduct. Disqualified from the **competition**. |

Plus `dq_detail`, optional free text, same shape as `submission`:
`"knee reap"`, `"slam"`, `"foul language"`.

```json
{ "method": "dq", "winner": "f1", "dq_reason": "technical_foul", "dq_detail": "knee reap" }
```

An `accumulated_penalties` DQ is the only one the app can raise **by itself**;
the other two are the referee's judgment and must be chosen.

### 3.5 `ended_at` — unix seconds

**Always recorded on a finished match**, including one that ran out the clock.
For a submission it is not derivable at all — `start_at + duration` is when the
clock *would* have expired, which is exactly what a submission prevents. For a
match that goes the distance it *is* computable, but writing it anyway means
every finished match has the same shape and no consumer has to special-case
one.

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

## 5. Penalties become real (decided)

Today the app **counts** penalties and applies none of their consequences. Under
IBJJF the ladder is cumulative, and each rung is automatic:

| Penalty | Consequence for the **opponent** |
|---|---|
| 1st | none — recorded only |
| 2nd | **+1 advantage** |
| 3rd | **+2 points** |
| 4th | **the offender is disqualified** |

Sources: [IBJJF rulebook](https://jjbqc.org/wp-content/uploads/2023/06/EN_IBJJF_RulesBook_MAR2022.pdf),
[summary](https://jiujitsulegacy.com/bjj-lifestyle/competition-tips/ibjjf-rules/).

This changes who wins, so it cannot be bolted on afterwards.

### 5.1 The raw counters stay raw

The penalty consequences are **derived, never baked in**. `f1_pen` keeps meaning
*"penalties given to fighter 1"*, and `f1_pt2`…`f1_pt4` keep meaning *"points
fighter 1 scored"*. The event stays a faithful record of what the referee
actually pressed.

What changes is that the app (and any consumer) reads an **effective** score:

```
effective_points(f1)     = 2·f1_pt2 + 3·f1_pt3 + 4·f1_pt4  +  (f2_pen ≥ 3 ? 2 : 0)
effective_advantages(f1) = f1_adv                          +  (f2_pen ≥ 2 ? 1 : 0)
```

Folding the two points into `f1_pt2` instead would corrupt the record — it would
claim fighter 1 scored a takedown they never scored, and the mistake would be
unrecoverable, because nothing would remember where the points came from.

### 5.2 The fourth penalty ends the match

Awarding a fourth penalty disqualifies the offender **immediately**: the app sets
`status: "finished"`, `method: "dq"`, `dq_reason: "accumulated_penalties"`, and
`winner` to the *other* fighter. It should say so plainly on screen — a referee
who did not realize they were on the third penalty must not be surprised by a
match that simply stops.

### 5.3 What is *not* in scope

IBJJF's penalty rules have more corners than this: penalties for lack of
combativeness restart the match standing when both fighters reach a third one,
and the distinction between serious and severe fouls decides whether a penalty
is even the right instrument. The referee is the authority on *whether* to give
a penalty; this spec is only about what the app does once one is given.

## 6. Backwards and forwards compatibility

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

## 7. The referee's hands

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

## 8. What this does *not* change

- Scoring, penalties, advantages: untouched.
- The `canceled` status: untouched.
- The event kind, the d-tag, addressable replacement, the convergence
  guarantees: untouched.

## 9. Open questions

Three of the four are now decided and folded in above:

- ~~**Penalties are only counted.**~~ → **Fixed.** §5 applies the IBJJF ladder.
- ~~**Should `dq` carry a reason?**~~ → **Yes, as a category + free text.** §3.4.
  The categories are standard; the infractions are not.
- ~~**Should `ended_at` be recorded for matches that expire on the clock?**~~ →
  **Yes, always.** §3.5.

Still open:

1. **Is `draw` real for us?** IBJJF has no draws in most brackets — a level match
   goes to referee decision. The value costs nothing to keep and some rulesets
   (and friendly in-house comps) do use it. **Kept for now**; say the word and it
   goes.

## 10. Proposed phasing

Each phase is a PR that leaves `main` shippable.

1. **Schema + model.** `winner`, `method`, `submission`, `dq_reason`,
   `dq_detail`, `ended_at` on `Match`, with JSON round-trips and the
   compatibility cases in §6 pinned as tests.

   The **penalty ladder** (§5) lands here too, as effective-score getters, and
   so does the tie-break ladder — both tested on their own. This is the phase
   that changes who wins, so it is the phase that has to be right.

   No UI: nothing sets the new fields yet.
2. **The outcome sheet.** Hold-to-finish opens it; the match finishes with an
   outcome. The fourth penalty ends the match on its own (§5.2). Strings in all
   four locales (`en`, `es`, `pt`, `ja`).
3. **Showing it.** The match list and the match screen say *"Carlos won by
   submission (armbar)"* instead of showing a scoreboard that lies, and the
   scoreboard itself shows the **effective** points and advantages, so a referee
   can see the penalty they just gave turn into the opponent's advantage. Update
   `docs/SPEC.md`, the event schema other clients read.
