#!/usr/bin/env bash
# Run the test suite with coverage and report the metric that matters:
# line coverage of hand-written code (generated sources excluded — see
# tool/filter_lcov.dart for the policy).
set -euo pipefail
cd "$(dirname "$0")/.."

# Build the native crate first: without the .so the rust-tagged suites
# (bridge, crypto, key-manager, relay contract, convergence drills) register
# as skipped and the run still exits 0 — silently shrinking the number this
# script exists to report. Same guard CI uses.
cargo build --manifest-path rust/Cargo.toml

flutter test --coverage
dart run tool/filter_lcov.dart coverage/lcov.info
