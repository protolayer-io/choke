<p align="center">
  <img src="logo.png" width="200" alt="Choke logo" />
</p>

# Choke 🥋⚡

A modern decentralized BJJ match scoring and publishing app via Nostr.

## What is Choke?

Choke lets you create, score, and publish Brazilian Jiu-Jitsu matches in real time using the Nostr protocol. Every scoring action is broadcast as a Nostr event, making match data open, verifiable, and accessible from any compatible dashboard.

## Features

- **Real-time scoring** — Takedowns (2pts), Guard Passes (3pts), Mount/Back Takes (4pts), Advantages, Penalties
- **Countdown timer** — Configurable match duration with second-by-second countdown
- **Decentralized** — All data published via Nostr (kind 31415 addressable events)
- **No accounts needed** — Nostr keypair generated on install
- **Delegation without nsec sharing** — Ephemeral match keys for team scoring
- **Live dashboard** — Web viewer for spectators and tournament projection (coming soon)

## Tech Stack

- **Mobile**: Flutter (Android & iOS)
- **State Management**: Riverpod
- **Protocol**: Nostr — the Rust [`nostr`](https://crates.io/crates/nostr) and [`nostr-sdk`](https://crates.io/crates/nostr-sdk) crates (crypto and relay pool)
- **Native**: Rust crate bridged with `flutter_rust_bridge`
- **Security**: flutter_secure_storage for key management
- **Design**: Custom BJJ-inspired theme

## Brand Colors

| Color | HEX | Usage |
|-------|-----|-------|
| Navy Black | `#121A2E` | Backgrounds |
| BJJ Green | `#1BA34E` | Actions & CTAs |
| Championship Gold | `#F5B800` | Accents & Awards |
| Pure White | `#FFFFFF` | Text & Cards |

See [BJJ_STYLE_GUIDE.md](BJJ_STYLE_GUIDE.md) for complete style guide.

## Getting Started

### Prerequisites

- Flutter SDK (^3.11.0)
- Dart SDK (>=3.5.0)
- Android Studio / Xcode (for mobile builds)
- **Rust** — the app links a native crate. Install [rustup](https://rustup.rs);
  the pinned version and Android targets are installed for you from
  `rust-toolchain.toml`.
- **Linux desktop builds need a complete Clang toolchain** — see
  [Building for Linux desktop](#building-for-linux-desktop).

### Installation

```bash
# Clone the repository
git clone https://github.com/protolayer-io/choke.git
cd choke

# Install dependencies
flutter pub get

# Run code generation (if needed)
flutter pub run build_runner build

# Run the app — the Rust crate is compiled and linked automatically
flutter run
```

### The Rust crate

The app's Nostr stack — key handling, NIP-19, event signing, and the relay pool
it publishes through — is the Rust [`nostr`](https://crates.io/crates/nostr) and
[`nostr-sdk`](https://crates.io/crates/nostr-sdk) crates, reached from Dart
through `flutter_rust_bridge`. Rust is therefore **required** to build or test
the app. See the [migration spec](docs/specs/nostr-sdk-migration.md) for how it
got here.

| Path | What it is |
|---|---|
| `rust/` | the crate — the app's whole native surface |
| `lib/src/rust/` | generated Dart bindings (committed; never edit by hand) |
| `rust_builder/` | Cargokit glue that builds the crate for each platform |

Building the app compiles the crate; no separate step is needed. Two cases do
need a command:

```bash
# After changing anything under rust/src/api/, regenerate the bindings.
# The codegen CLI version must match the flutter_rust_bridge version in
# pubspec.yaml and rust/Cargo.toml — all three are pinned together.
cargo install flutter_rust_bridge_codegen --version 2.12.0 --locked
flutter_rust_bridge_codegen generate

# Tests that exercise crypto or the relay pool need the native library on disk.
# Without it they skip themselves — so a plain `flutter test` still runs, it
# just covers less. Build the crate first to run everything:
cargo build --manifest-path rust/Cargo.toml
flutter test --tags rust
```

### Building for Linux desktop

Linux needs more setup than the other targets, and the reason is the Rust crate.
Because the app ships a native library, Flutter builds it through its
**native-assets** path, which requires a complete Clang toolchain rather than
just a working compiler. Flutter locates `clang++` on your `PATH`, resolves any
symlinks, and then insists that `clang`, `llvm-ar`, and a linker (`ld.lld`,
falling back to `ld`) all live in **that same directory**.

Targets without native assets never take this path, so a machine that builds
other Flutter Linux apps fine can still fail here.

```bash
# Flutter's own Linux desktop requirements
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev

# Additionally required by this project
sudo apt install lld libstdc++-14-dev
```

Those last two are the ones people hit, because a stock install has neither:

| Symptom | Cause | Fix |
|---|---|---|
| `Failed to find any of [ld.lld, ld] in /usr/lib/llvm-N/bin` | Clang ships without a linker; the system `ld` lives in `/usr/bin`, not next to `clang` | `lld` (must match your Clang's major version) |
| `'type_traits' file not found` | Clang selects the newest GCC it can find; if that GCC's libstdc++ headers are missing, every C++ compile fails | the matching `libstdc++-N-dev` |

The second one is worth explaining, since the error looks unrelated to your
setup. Clang picks the highest-numbered GCC installation present, but a GCC
*runtime* can be installed without its C++ *headers* — so Clang selects a
toolchain whose headers do not exist. Check which one it chose:

```bash
clang++ -v 2>&1 | grep 'Selected GCC installation'
# .../lib/gcc/x86_64-linux-gnu/14  ->  install libstdc++-14-dev
```

Verify the toolchain is complete before building:

```bash
# All four must resolve, and the linker must sit beside clang
CLANG_DIR=$(dirname "$(readlink -f "$(which clang++)")")
ls "$CLANG_DIR"/{clang,llvm-ar,ld.lld}
echo '#include <type_traits>
int main() { return 0; }' | clang++ -x c++ - -o /dev/null && echo "C++ toolchain OK"
```

Then:

```bash
flutter build linux --release
```

The build produces a relocatable bundle under
`build/linux/x64/release/bundle/`, with the executable at its root and the
desktop entry plus hicolor icons in `share/`.

### Build for Production

```bash
# Android
flutter build apk --release
flutter build appbundle --release

# iOS
flutter build ios --release

# Linux — see Building for Linux desktop above for required packages
flutter build linux --release
```

## Architecture

```
lib/
├── features/       # Feature-based modules
├── data/          # Models and repositories
├── services/      # Nostr and key management
└── shared/        # Theme, widgets, utilities
```

## Nostr Integration

Choke uses Nostr addressable events for match data.

### Event Kinds

- `31415` — Match events (addressable/replaceable)

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

See [AGENTS.md](AGENTS.md) for development conventions.

### Translations

Choke is fully localized (English, Spanish, Portuguese, Japanese). Want to fix
wording or add your own language? See the
[Translations & i18n guide](docs/translations.md) — no Dart experience needed to
translate.

## License

GNU General Public License v3.0 — see the [LICENSE](LICENSE) file for details.

Copyright (C) 2026 ProtoLayer OÜ.

## Connect

- GitHub: [@protolayer-io/choke](https://github.com/protolayer-io/choke)
- Nostr: `npub14e8x7ggcvgy4j0wcsqh6kv4pfmtax7rkryenux9u7ytemjcuce7q9qpjtk`

---

Built with 🥋 and ⚡ by the BJJ & Bitcoin community.
