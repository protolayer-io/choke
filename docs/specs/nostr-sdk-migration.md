# Migration Spec: `nostr_tools` (Dart) → `nostr-sdk` (Rust) via `flutter_rust_bridge`

**Status:** APPROVED — Phase 0 complete, Phase 1 next
**Author:** prepared with Claude Code
**Date:** 2026-07-13
**Decisions locked (2026-07-13):** web target frozen (§5, W1) · own thin Rust
crate over official Flutter bindings (§9.2) · manual QA on Android (§9.3)

**Progress:** Phase 0 ✅ · Phases 1–8 pending

---

## 1. Motivation

The app depends on [`nostr_tools ^1.0.9`](https://pub.dev/packages/nostr_tools), a Dart
library whose last release is ~3 years old. Nostr has evolved substantially since then
(new NIPs, hardened relay behaviors, better client patterns), and an unmaintained
dependency is a liability for correctness, security (it implements secp256k1/Schnorr
crypto), and future features.

[`nostr-sdk`](https://crates.io/crates/nostr-sdk) (the `rust-nostr` project) is actively
maintained, widely used, audited by many eyes, and covers far more of the protocol.
It can be consumed from Flutter through [`flutter_rust_bridge`](https://pub.dev/packages/flutter_rust_bridge)
(FRB), which generates Dart bindings for a Rust crate and wires the native build into
every Flutter platform.

## 2. Current state (inventory)

### 2.1 What actually uses `nostr_tools`

The dependency surface is **small and entirely cryptographic**:

| File | API used | Purpose |
|---|---|---|
| `lib/services/key_management/key_manager.dart` | `KeyApi.generatePrivateKey()` | new keypair on first launch |
| | `KeyApi.getPublicKey(hex)` | derive pubkey (also on nsec import) |
| | `Nip19.npubEncode / nsecEncode / decode` | NIP-19 bech32 for Account screen + import |
| `lib/services/nostr/nostr_service.dart` | `Event`, `EventApi.finishEvent()` | compute event id + Schnorr signature |
| | `EventApi.verifySignature()` | self-check before publishing |
| `lib/features/match/models/match.dart` | *(import only — zero usages, dead import)* | — |

### 2.2 What is ours (and must be preserved)

The entire relay layer is hand-written Dart over `web_socket_channel`, **not**
`nostr_tools`: relay pool, `REQ`/`EVENT`/`OK` handling, publish-with-OK-confirmation,
reconnection, zombie-socket detection, per-relay convergence, addressable-event cache.
This code embeds hard-won behavioral fixes (PR #72, #77, #78) that the migration must
not regress — see §4.

**Consequence:** this migration is really two independent sub-migrations with very
different risk profiles:

- **(A) Crypto** — replace `nostr_tools` keys/NIP-19/signing with `nostr-sdk`.
  Small surface, easy to verify (deterministic outputs), removes the unmaintained
  dependency entirely.
- **(B) Relay transport** — replace the hand-rolled relay pool with `nostr-sdk`'s
  `Client`/relay pool. Bigger win long-term (native WebSocket pings, per-relay OK
  reporting, reconnection, future NIPs) but must re-prove all our convergence
  behaviors.

Phases 1–4 deliver (A). Phases 5–7 deliver (B). After Phase 4 the app no longer
depends on `nostr_tools` for anything critical; (B) can proceed at its own pace.

## 3. Target architecture

```
┌──────────────────────────────────────────────────────────┐
│ Flutter app (unchanged: providers, screens, Match model) │
├──────────────────────────────────────────────────────────┤
│ NostrService (Dart)                                      │
│  · outbox / retry / per-relay convergence (stays Dart)   │
│  · addressable cache, NIP-40 filtering (stays Dart)      │
├──────────────────┬───────────────────────────────────────┤
│ NostrCrypto      │ NostrRelayBackend                     │
│ (interface)      │ (interface)                           │
├──────────────────┼───────────────────────────────────────┤
│ RustNostrCrypto  │ RustRelayBackend                      │
│ (FRB bindings)   │ (FRB bindings → nostr-sdk Client)     │
├──────────────────┴───────────────────────────────────────┤
│ rust/ crate: thin API over nostr / nostr-sdk             │
│ (flutter_rust_bridge codegen, built via Cargokit)        │
└──────────────────────────────────────────────────────────┘
```

Design principles:

1. **Thin Rust API, owned by us.** The crate exposes only what the app needs
   (~10 functions + 1 event-stream). We do not re-export the whole SDK: smaller
   binary, fewer breaking changes when `nostr-sdk` (still 0.x, API churns between
   minor versions — pin the exact version) evolves.
2. **Interfaces in Dart, implementations swappable.** Both legacy and Rust
   implementations live side by side behind `NostrCrypto` / `NostrRelayBackend`,
   selected by a compile-time flag (`--dart-define=NOSTR_BACKEND=legacy|rust`)
   plus a debug-only Settings toggle. Every switch phase is a one-line default
   change, instantly revertible.
3. **Business logic stays in Dart.** Outbox coalescing, retry/backoff, per-relay
   convergence, monotonic `created_at` remain in `NostrService` /
   `MatchControlNotifier` regardless of backend. The backend is transport only.

## 4. Behavioral invariants (must hold before and after every phase)

These are pinned by the existing test suite (105 tests) and must never regress:

| # | Invariant | Pinned by |
|---|---|---|
| I1 | `created_at` strictly increases per d-tag within a session (NIP-01 tie-break) | `nextCreatedAt` tests |
| I2 | Publish succeeds when ≥1 relay accepts; UI never blocks on stragglers | provider tests |
| I3 | Every configured relay converges to the latest state per match (resend on reconnect + periodic sweep; only newest state is resent) | per-relay convergence tests (PR #78) |
| I4 | A relay that never answers OK is treated as dead and recycled; connections recycled on app resume | zombie detection tests (PR #78) |
| I5 | Pending state publishes the moment a relay reconnects (no backoff wait) | reconnect recovery tests (PR #78) |
| I6 | Incoming NIP-40 expired events ignored; addressable replacement keeps newest `(kind, pubkey, d)` | `_handleIncomingEvent` behavior |
| I7 | Keys: same nsec always derives the same npub; import/export round-trips | key manager tests |
| I8 | Event ids/signatures are valid NIP-01 (verifiable by any compliant relay) | differential tests (new, Phase 3) |

## 5. Platform support & the web question

The repo contains build targets for **android, ios, linux, macos, windows, web**.
FRB v2 supports all six (web via `wasm32` + wasm-bindgen), and `rust-nostr` supports
WASM — but web is by far the most fragile leg (build tooling, secp256k1 in WASM,
CI complexity).

**DECIDED (2026-07-13): Option W1 — freeze the web target.** The web build is not
shipped; the referee use case is a phone at the mat.

- **W1 — freeze the web target** *(chosen)*: the `web/` directory stays in the
  repo but web is not built in CI, not released, and not QA'd from Phase 1 onward.
  Phase 1 documents this in the README. Un-freezing later requires a WASM build of
  the crate (FRB v2 + `wasm32`), tracked as future work.
- ~~W2 — web via WASM~~: rejected for now; the most fragile leg of the migration
  for a target nobody uses.

## 6. Migration phases

Each phase is one atomic PR. Every PR leaves `main` shippable: green suite,
no behavior change unless the phase explicitly says so, and a documented rollback.

---

### Phase 0 — Spike & decision record — ✅ **DONE (2026-07-13)** *(PR: docs only)*

**Goal:** de-risk everything irreversible before writing production code.

Ran on a throwaway branch (`spike/frb-throwaway`, discarded): FRB integrated into
the real app, `nostr` wired in with three crypto functions, release APK built.
Results below; everything the spike learned is now Phase 1's job to reproduce
deliberately.

#### 0.1 Official bindings — sanity check (confirms §9.2)

[`rust-nostr/nostr-sdk-flutter`](https://github.com/rust-nostr/nostr-sdk-flutter):
7 stars, last push 2026-01-29 (~6 months stale), and its only "releases" are
precompiled-binary artifacts from early 2025. The `nostr_sdk` package on pub.dev
(v0.0.1) is a **different, unrelated author** — not the official binding.

→ **Own thin crate confirmed.** Adopting these would trade one unmaintained
dependency for another.

#### 0.2 Version pins

| Component | Pin | Notes |
|---|---|---|
| Rust toolchain | 1.94.0 | `rust-toolchain.toml` in Phase 1 |
| `flutter_rust_bridge` | **2.12.0** | codegen CLI, Rust crate and pub package must all match **exactly** |
| `nostr` crate | **0.44.4** | released 2026-07-06 — actively maintained |
| `nostr-sdk` crate | 0.44.1 | Phase 6 only; not needed for the crypto track |
| Dart SDK floor | **≥3.5.0** | see 0.4 |

`nostr` is pulled with `--no-default-features --features std`: NIP-19 lives in the
core (there is **no** `nip19` feature), so `std` alone covers keys, NIP-19 and
event signing.

#### 0.3 Size budget — measured ✅

Release APK, `--target-platform android-arm64`:

| Build | Size |
|---|---|
| Baseline (`main`) | 41.7 MB |
| With Rust + `nostr` | 42.5 MB |
| **Delta** | **+0.8 MB** |

`librust_lib_choke.so` (arm64, release) is **0.81 MB** — that is the whole cost:
FRB runtime + `nostr` + secp256k1. Well inside the ≤6 MB budget; no further
size work needed.

#### 0.4 Gotchas Phase 1 must handle (found the hard way)

1. **`flutter_rust_bridge_codegen integrate` comments out the whole of
   `lib/main.dart`** and replaces it with its demo app. It must be restored
   afterwards — verify with `git diff lib/main.dart` before committing.
2. **`integrate` runs `dart format` across the entire repo**, producing a large
   unrelated diff. Phase 1 must either revert that churn or land it as a separate
   commit so the review stays readable.
3. **Dart SDK floor must rise to ≥3.3** (Phase 1 sets `>=3.5.0 <4.0.0`). The
   generated `frb_generated.web.dart` uses *extension types*, which the previous
   `>=3.0.0` floor rejects — codegen fails to format it. This applies even with
   the web target frozen, because codegen still emits the file.
4. **Crate name:** FRB's `integrate` names it `rust_lib_choke` and wires that name
   into Cargokit's Gradle/CMake glue. Phase 1 keeps that name rather than the
   `choke_nostr` this spec first proposed — renaming buys nothing and fights the
   tooling.
5. **`flutter build linux` is already broken on this machine** (`ld.lld` missing
   from `/usr/lib/llvm-18/bin`) — verified to fail identically on a clean `main`
   worktree, so it is a pre-existing local environment gap, **unrelated to this
   migration**. Android (the QA platform) builds fine. Do not let it block Phase 1;
   fix it separately if desktop Linux ever matters.

**Deliverable:** ✅ this section.
**Acceptance:** reviewer signs off on the pins (0.2) and the measured size (0.3).
**Rollback:** n/a (no app code).

---

### Phase 1 — Rust scaffolding, zero app impact *(PR ~small, mostly generated/build files)*

**Goal:** the Rust toolchain lives in the repo and CI, invisible to the running app.

Steps (informed by the Phase 0 gotchas — read §0.4 first):
1. `rust/` crate **`rust_lib_choke`** (FRB's default name; see §0.4.4) depending on
   `nostr = "=0.44.4"` with `--no-default-features --features std` (crypto only;
   `nostr-sdk` arrives in Phase 6). Expose one smoke function:
   `fn verify_event(event_json: String) -> Result<bool, String>`.
2. FRB v2 integration (`flutter_rust_bridge_codegen integrate`): `flutter_rust_bridge.yaml`,
   generated Dart under `lib/src/rust/` (committed), Cargokit build wiring, `rust_builder/`.
   **Restore `lib/main.dart` afterwards** (§0.4.1) and keep the repo-wide `dart format`
   churn out of the review diff (§0.4.2).
3. Raise the Dart SDK floor to `>=3.5.0 <4.0.0` (§0.4.3) and add `rust-toolchain.toml`
   pinning Rust 1.94.0. Gitignore `rust/target/`.
4. `RustLib.init()` called lazily — **not** from `main()` yet; only tests touch it.
5. CI: new job — `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test`, plus
   one **Android** build to prove linking (no Linux desktop build — §0.4.5). Cache
   cargo artifacts.
6. `README` section: contributor setup (rustup + Android targets), how to re-run codegen.

**Tests:** `cargo test` for the crate; one Dart integration test (skipped where the
native lib is unavailable, e.g. plain `flutter test` on CI without the built binary —
use `@Tags(['rust'])` and a dedicated CI step).
**Acceptance:** app builds and behaves identically with the crate present; suite green;
release APK growth matches the ~0.8 MB measured in §0.3.
**Rollback:** revert the PR — nothing references the crate.

---

### Phase 2 — Crypto seam in Dart *(PR: pure refactor)*

**Goal:** one interface both crypto implementations can stand behind.

Steps:
1. New `lib/services/nostr/crypto/nostr_crypto.dart`:

   ```dart
   abstract class NostrCrypto {
     String generatePrivateKey();
     String getPublicKey(String privateKeyHex);
     String npubEncode(String publicKeyHex);
     String nsecEncode(String privateKeyHex);
     /// Returns hex private key, or null if [nsec] is not a valid nsec.
     String? nsecDecode(String nsec);
     /// Computes id, signs, returns the finished event.
     NostrEvent finishEvent(UnsignedNostrEvent event, String privateKeyHex);
     bool verifyEvent(NostrEvent event);
   }
   ```
2. `NostrToolsCrypto` implements it by moving the existing `KeyApi`/`Nip19`/
   `EventApi` calls out of `KeyManager` and `NostrService` (the only two call
   sites). `KeyManager` and `NostrService` receive a `NostrCrypto` via constructor
   (Riverpod provider `nostrCryptoProvider`).
3. Delete the dead `nostr_tools` import in `match.dart`.
4. Contract test suite `nostr_crypto_contract.dart`: a reusable group of tests
   written against the interface (round-trips, known NIP-19 vectors, event id
   against a hand-computed NIP-01 vector, sign→verify). Runs against
   `NostrToolsCrypto` in this PR.

**Tests:** existing 105 + contract suite. Zero behavior change.
**Acceptance:** `nostr_tools` imports exist **only** inside `NostrToolsCrypto`.
**Rollback:** revert; pure refactor.

---

### Phase 3 — Rust crypto implementation + differential tests *(PR: additive)*

**Goal:** a fully verified Rust implementation, not yet default.

Steps:
1. Extend the crate: `generate_secret_key`, `public_key_from_secret`,
   `npub_encode`, `nsec_encode`, `nsec_decode`, `finish_event(unsigned_json, sk)`,
   `verify_event(json)` — thin wrappers over `nostr::Keys`, `nostr::nips::nip19`,
   `nostr::EventBuilder`/`UnsignedEvent`.
2. `RustNostrCrypto implements NostrCrypto` over the generated bindings.
3. Run the Phase 2 contract suite against `RustNostrCrypto`.
4. **Differential tests** (the heart of this phase): for a corpus of fixed vectors
   and randomized inputs —
   - same private key ⇒ identical public key, npub, nsec across both impls;
   - identical unsigned event ⇒ **identical event id** across both impls
     (id is deterministic; catches JSON canonicalization/escaping divergence —
     include tags/content with UTF-8, quotes, newlines, emoji);
   - cross-verification: event signed by Rust verifies under `NostrToolsCrypto`
     and vice versa (signatures differ by nonce; validity must not).
5. Wire the backend selector: `nostrCryptoProvider` reads
   `String.fromEnvironment('NOSTR_BACKEND', defaultValue: 'legacy')`.

**Tests:** contract ×2 + differential suite (tagged `rust`, run in the CI job that
has the native lib).
**Acceptance:** both impls pass identical contracts; differential suite green.
**Rollback:** revert; default is still `legacy`.

---

### Phase 4 — Switch crypto default to Rust *(PR: one-line default + QA)*

**Goal:** production keys and signatures come from `nostr-sdk`.

Steps:
1. Flip default: `NOSTR_BACKEND` → `rust`. `RustLib.init()` moves into `main()`
   (before `KeyManager.initialize()`), with a fail-fast error if the native lib
   is missing.
2. Manual QA checklist (attach evidence to the PR):
   - fresh install → keypair generated, npub shown in Account;
   - existing install upgrade → **same npub as before** (keys read from secure
     storage, only derivation path changed);
   - nsec import (valid + malformed) and QR export;
   - create match, run full match lifecycle, verify events accepted by a real
     relay and readable by another Nostr client.
3. Keep `NostrToolsCrypto` + flag for one release cycle as rollback.

**Acceptance:** QA checklist green on Android (§9.3).
**Rollback:** build with `--dart-define=NOSTR_BACKEND=legacy` (no code revert
needed), or revert the PR.

---

### Phase 5 — Relay backend seam *(PR: pure refactor)*

**Goal:** the transport becomes swappable without touching business logic.

Steps:
1. Define `NostrRelayBackend`: the minimal transport contract —
   `connect(urls)`, `disconnect()`, `addRelay/removeRelay`, `reconnectAll()`,
   `subscribe(id, filter)/unsubscribe(id)`, `publishToRelay(url, event) → Future<bool>`
   (OK-confirmed), `Stream<NostrEvent> events`, `Stream<RelayStatus> relayStatus`,
   `List<String> get connectedRelays`.
2. Reshape today's `RelayConnection`-based code into `DartRelayBackend`.
   `NostrService` keeps owning: pending/ack maps (I3), resend sweep, monotonic
   `created_at` (I1), addressable cache + NIP-40 (I6). Zombie handling (I4) moves
   behind the backend (it is transport).
3. Re-point the 105-test suite; the PR #78 service tests (fake WebSocket channels)
   become `DartRelayBackend` tests.

**Tests:** suite green, zero behavior change.
**Acceptance:** `NostrService` contains no `web_socket_channel` import.
**Rollback:** revert; pure refactor.

---

### Phase 6 — `nostr-sdk` Client backend, shadow mode *(PR: additive)*

**Goal:** the Rust relay pool runs in real conditions without owning production traffic.

Steps:
1. Extend the crate with `nostr-sdk`: create `Client`, add/remove relays, connect,
   `send_event` returning **per-relay results** (`Output` success/failed maps —
   this is what lets Dart keep I2/I3 semantics), subscriptions streaming events
   back over an FRB `StreamSink`, relay status notifications.
2. `RustRelayBackend implements NostrRelayBackend`.
3. Port the backend test suite (Phase 5) to run against `RustRelayBackend` where
   possible; add a small integration test against a throwaway local relay
   (e.g. `nak serve` or dockerized strfry) in CI for **both** backends.
4. **Shadow mode** (debug builds only, off by default): rust backend connects and
   mirrors subscriptions **read-only** (no publishing — avoids double-publish and
   rate limits); logs divergence between what each backend receives.

**Acceptance:** backend contract tests green on both; shadow session shows no
divergence over a full manual match.
**Rollback:** revert; default backend unchanged.

---

### Phase 7 — Switch relay backend to Rust *(PR: one-line default + QA)*

**Goal:** `nostr-sdk` owns production traffic.

Steps:
1. Flip `NOSTR_RELAY_BACKEND` default to `rust`.
2. Re-run the Phase 4 QA checklist **plus** the failure drills that motivated
   PR #77/#78 (these are the reason this app exists — do not skip):
   - airplane mode mid-match → score more → disable → all relays converge;
   - kill one relay of two → rapid advantage presses → relay comes back →
     it receives the latest state;
   - app backgrounded 10 min mid-match → resume → next press publishes promptly;
   - relay that rate-limits: hammer advantages, confirm eventual convergence.
3. Keep `DartRelayBackend` + flag for one release cycle.

**Acceptance:** QA + failure drills green; relay monitor shows I2–I5 hold.
**Rollback:** `--dart-define=NOSTR_RELAY_BACKEND=legacy` or revert.

---

### Phase 8 — Removal & cleanup *(PR: deletions)*

**Goal:** one stack, no corpses.

Steps:
1. Remove `nostr_tools` from `pubspec.yaml`; delete `NostrToolsCrypto`,
   `DartRelayBackend`, `RelayConnection`, backend flags, shadow mode.
2. `web_socket_channel` becomes unused → remove.
3. Update `README`, `CHANGELOG`, bump version.

**Acceptance:** `grep -r nostr_tools` returns nothing; suite green; release build QA.
**Rollback:** revert (previous release still carries the flag as a safety net).

---

## 7. Risks & mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| `nostr-sdk` is 0.x with API churn | breakage on upgrade | pin exact version; upgrades are deliberate PRs; our thin crate isolates the app from SDK signatures |
| Web/WASM build | blocks Phase 1 or drops a platform | decided in Phase 0 before any code (§5) |
| Event id divergence (JSON canonicalization) | silently invalid events | Phase 3 differential tests with hostile content vectors |
| Convergence regressions in the SDK pool (our #77/#78 fixes) | the original bug returns | convergence logic stays in Dart above the seam; Phase 7 failure drills |
| Build complexity for contributors/CI | slower onboarding, flaky CI | Cargokit automates builds; README setup section; cargo caching in CI |
| Binary size growth | heavier APK | measured in Phase 0 with an explicit budget |
| FRB codegen/runtime version mismatch | cryptic build failures | both pinned together; codegen check in CI |
| Key continuity on upgrade (Phase 4) | user identity changes | keys live in secure storage untouched; QA asserts same npub pre/post |

## 8. Out of scope

- New Nostr features (NIP-65 outbox model, gossip, NIP-46 signers, DMs). The
  migration is behavior-preserving; new capabilities come after Phase 8.
- Changing the event schema (kind 31415, content JSON) or relay defaults.
- Rewriting `MatchControlNotifier` logic (outbox/undo/timer) — untouched.

## 9. Review decisions

1. **Web target:** ~~open~~ → **frozen** (2026-07-13). See §5.
2. **Official bindings vs own crate:** ~~open~~ → **own thin crate** (2026-07-13).
   Rationale: expose only the ~10 functions the app needs (smaller binary; track A
   can depend on the `nostr` crypto crate alone, no full SDK); insulation from 0.x
   API churn behind our own signatures; and no dependency on a third-party binding
   whose release cadence lags the core — the mature `rust-nostr` bindings are
   Kotlin/Swift/Python, Flutter's are the youngest. Phase 0 keeps a brief
   sanity-check of the official bindings.
3. **Platform QA matrix:** ~~open~~ → **Android** (2026-07-13). Linux builds are
   exercised in development; CI covers the rest at compile level.
4. **Timeline for (B) — still open:** Phases 5–7 are optional-when-ready. Ship (A)
   first and let the Dart relay layer live for a while, or run both tracks
   back-to-back? To be decided after Phase 4 ships.
