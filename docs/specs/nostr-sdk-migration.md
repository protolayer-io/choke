# Migration Spec: `nostr_tools` (Dart) → `nostr-sdk` (Rust) via `flutter_rust_bridge`

**Status:** APPROVED — Phases 0-4 complete (crypto track done), Phase 5 next
**Author:** prepared with Claude Code
**Date:** 2026-07-13
**Decisions locked (2026-07-13):** web target frozen (§5, W1) · own thin Rust
crate over official Flutter bindings (§9.2) · manual QA on Android (§9.3)


**Progress:** Phases 0 ✅ 1 ✅ 2 ✅ 3 ✅ 4 ✅ 5 ✅ · Phases 6–8 pending
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
| I7 | Keys: same nsec always derives the same npub; import/export round-trips | key manager tests (added in Phase 2 — see §2.2) |
| I8 | Event ids/signatures are valid NIP-01: the id hashes the event **and** the signature is the pubkey's (verifiable by any compliant relay) | `NostrCrypto` contract (Phase 2) + differential tests (Phase 3) — see §2.1 |

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

> **Updated in Phase 1 (2026-07-13):** the shipped crate measures **+2.1 MB**
> (APK 41.7 → 43.8 MB; `librust_lib_choke.so` = 2.01 MB). The spike only
> exercised key generation and bech32; `verify_event` additionally pulls in
> event JSON parsing (serde and the full `Event` machinery), which accounts
> for the difference. Still comfortably inside the ≤6 MB budget — but the
> budget is now ~35% spent, so Phase 3 and Phase 6 should re-measure rather
> than assume headroom.

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

### Phase 1 — Rust scaffolding, zero app impact — ✅ **DONE (2026-07-13)** *(PR: scaffolding)*

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
release APK growth stays inside the ≤6 MB budget (measured: +2.1 MB — see the §0.3 note).
**Rollback:** revert the PR — nothing references the crate.

---

### Phase 2 — Crypto seam in Dart — ✅ **DONE (2026-07-13)** *(PR: pure refactor)*

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

#### 2.1 What the contract turned up: `nostr_tools` under-verifies events

Writing the contract first surfaced a real flaw in the incumbent library.
`EventApi.verifySignature` checks the signature **against the event id, but
never checks that the id describes the event**. Per NIP-01 the id *is* the hash
of the event's fields, so an event whose content is rewritten after signing —
keeping the original id and signature — is forged. `nostr_tools` calls it valid.
The Rust `nostr` crate rejects it (Phase 1's tampering test already proved this),
so the two implementations would not have been interchangeable.

`NostrToolsCrypto.verifyEvent` therefore also recomputes the id (via
`getEventHash`) and rejects a mismatch. This is a **deliberate, small hardening**
rather than a pure move: it is what makes the contract satisfiable by both
backends, and it cannot regress the app, whose only use of verification is a
self-check on events it just signed itself (where the id always matches).

Two consequences:
- **I8 gets stronger**: event verification now means *id integrity + signature*,
  in both implementations.
- **Phase 8 gains urgency**: the app is currently shipping a signature check
  that the library alone would have gotten wrong. Nothing else in the app calls
  it, so exposure is nil — but it is exactly the class of bug that motivated
  this migration.

#### 2.2 I7 was not actually pinned

The spec claimed invariant I7 (same nsec ⇒ same npub; import round-trips) was
"pinned by key manager tests" — there were none. Phase 2 adds
`test/services/key_management/key_manager_test.dart` (in-memory secure storage),
covering first launch, reopening, npub/nsec round-trips, nsec import (valid and
malformed), and the repair path for a stored pubkey that disagrees with its
private key. Phase 4 swaps the crypto backend underneath exactly this code, so
the invariant needed teeth before then, not after.

**Tests:** 136 passing (110 existing + 19 contract + 7 key manager).
**Acceptance:** `package:nostr_tools` is imported in **exactly one file**,
`nostr_tools_crypto.dart`. ✅
**Rollback:** revert; behavior-preserving apart from §2.1.

---

### Phase 3 — Rust crypto implementation + differential tests — ✅ **DONE (2026-07-13)** *(PR: additive)*

**Goal:** a fully verified Rust implementation, not yet default.

Steps:
1. Extend the crate: `generate_secret_key`, `public_key_from_secret`,
   `npub_encode`, `nsec_encode`, `nsec_decode`, plus — over **typed** FFI
   structs rather than JSON, for the reason in §3.1 —
   `finish_event(UnsignedEventData, secret_hex) -> SignedEventData` and
   `verify_event_data(SignedEventData) -> bool`. Thin wrappers over
   `nostr::Keys`, `nostr::nips::nip19` and `nostr::UnsignedEvent`.
   (`verify_event(json)` from Phase 1 stays, unused by the app but handy as a
   smoke test of the bridge.)
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

#### 3.1 Events cross the bridge as structs, not JSON

The event id is a hash of the event's canonical serialization. Passing events
over FFI as JSON would have put a **second** serializer in the path (Dart's
`jsonEncode` on one side, `serde` on the other) — a silent canonicalization the
differential tests could only have caught by luck. The bridge therefore carries
the *fields* (`UnsignedEventData` / `SignedEventData`), and the `nostr` crate
performs the only serialization that counts.

#### 3.2 Results

Both implementations pass the **identical** Phase 2 contract — 19 tests, not a
line of it changed — plus 10 differential tests. `nostr_tools` and the Rust
crate agree on:

- the public key, npub and nsec derived from the same private key (20 random
  keys per run), and each accepts the other's generated keys;
- **the event id**, for every hostile content vector tried — empty, accented,
  CJK, emoji, embedded quotes, newlines, tabs, back- and forward-slashes, and
  raw match JSON — and for tag sets from empty to unicode d-tags. Identical ids
  mean both libraries serialize to identical canonical bytes;
- `created_at` preserved exactly across the FFI boundary (0 → 4102444800),
  which matters because NIP-01 replacement ordering turns on it (I1);
- rejecting a post-signing tamper, keeping §2.1's divergence closed.

Signatures are *not* compared byte for byte — Schnorr signing uses a random
nonce, so they legitimately differ. What is asserted instead is the property
that actually matters: **each library verifies the other's signatures**, which
is what a relay and every other Nostr client will do.

**Size, re-measured** (§0.3 asked Phase 3 not to assume headroom): release APK
`43.9 MB` (baseline `41.7`, so +2.2 MB); `librust_lib_choke.so` = 2.09 MB. The
seven new crypto functions cost ~0.08 MB — the bulk was already paid for by
secp256k1 in Phase 1. Comfortably inside the ≤6 MB budget.

**Backend selector:** `--dart-define=NOSTR_BACKEND=rust|legacy`, defaulting to
`legacy`. `main.dart` initializes `RustLib` only when Rust is selected. Both
APKs build.

**Tests:** contract ×2 + differential suite (tagged `rust`; CI's `bridge` job
already runs `flutter test --tags rust`, so it picks them up with no workflow
change). 165 Dart tests + 10 Rust unit tests.
**Acceptance:** both impls pass identical contracts; differential suite green. ✅
**Rollback:** revert; default is still `legacy`.

---

### Phase 4 — Switch crypto default to Rust — ✅ **DONE (2026-07-13)** *(PR: one-line default + QA)*

**Goal:** production keys and signatures come from the Rust `nostr` crate.

Steps:
1. Flip default: `NOSTR_BACKEND` → `rust`. `RustLib.init()` runs in `main()`
   before `KeyManager.initialize()`, deliberately **not** wrapped in a
   try/catch — see §4.1.
2. Keep `NostrToolsCrypto` + the flag for one release cycle as rollback:
   `--dart-define=NOSTR_BACKEND=legacy`. Removed in Phase 8.

#### 4.1 Failing to load the native library is fatal, on purpose

Every other initialization in `main()` is wrapped in a try/catch that logs and
limps on. Crypto is not, and must not be: without it nothing can be signed, so
the app would run perfectly while publishing **nothing** — a referee would score
an entire match into the void and find out afterwards. A crash on launch is the
honest failure, and it is one no release can ship with, because CI's Android job
builds and links exactly this path.

#### 4.2 The riskiest QA item is now a test, not a memory

The QA checklist's sharpest item — *"an existing install upgrades and keeps the
same npub"* — is the one nobody can really verify by eye: it asks a human to
remember what their npub looked like yesterday. It is now
`key_manager_backend_swap_test.dart` (tagged `rust`), which pre-populates secure
storage with keys generated by `nostr_tools`, re-reads them through the Rust
backend, and asserts the npub, nsec and private key are unchanged. It also pins
the reverse (rollback keeps the npub), an nsec imported on one backend being
readable on the other, and both backends repairing a corrupted stored pubkey to
the same value.

The identity is never *migrated* — it is re-read from secure storage. So the
only way to lose it was for the new backend to derive something different from
the same bytes, and that is precisely what the test forbids.

**Tests:** 169 Dart (36 of them tagged `rust`) + 10 Rust. Release APK builds on
the new default; the `legacy` rollback flag still builds.

**Manual QA still outstanding** (needs a device; cannot be automated here):
- [ ] fresh install → keypair generated, npub shown in Account
- [ ] nsec import (valid + malformed) and QR export
- [ ] full match lifecycle against a live relay, events readable by another
      Nostr client
- [ ] upgrade over an existing install (automated in §4.2, worth confirming once
      on a real device)

**Acceptance:** QA checklist green on Android (§9.3).
**Rollback:** build with `--dart-define=NOSTR_BACKEND=legacy` (no code revert
needed), or revert the PR.

---

### Phase 5 — Relay backend seam — ✅ **DONE (2026-07-13)** *(PR: pure refactor)*

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

#### 5.1 What stayed above the seam, and why

The interface is deliberately narrow: connect, subscribe, publish-to-one-relay,
report what that relay said. Everything that makes publishing *trustworthy*
stayed in `NostrService` — the outbox, per-relay convergence and its ack
bookkeeping, the resend sweep, supersession, monotonic `created_at`, the
addressable cache and NIP-40 filtering.

That split is the whole point. Those behaviors were each bought with a
production bug (#77, #78), and none of them is a property of a *transport*. Had
they been pushed down into the backend, Phase 6 would have had to re-implement
and re-prove them against `nostr-sdk`'s relay pool — and the bug that started
this whole thread (a relay quietly serving a stale scoreboard) would have had a
fresh place to hide.

Two things the transport *does* own, because they are genuinely about sockets:
the OK-confirmed publish, and treating a silent relay as dead rather than slow.

#### 5.2 Results

`NostrService` no longer imports `web_socket_channel` — it cannot form an
opinion about sockets any more. `RelayConnection` moved verbatim into
`DartRelayBackend` (its subtleties intact), and its tests moved with it into
`relay/dart_relay_backend_test.dart`, where they now read as what they are:
transport regressions, not service tests.

**Tests:** 165 passing, zero behavior change. **Acceptance:** ✅
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
