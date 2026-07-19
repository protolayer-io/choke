#!/usr/bin/env bash
# Run the test suite with coverage and report the metric that matters:
# line coverage of hand-written code (generated sources excluded — see
# tool/filter_lcov.dart for the policy).
set -euo pipefail
cd "$(dirname "$0")/.."

flutter test --coverage
dart run tool/filter_lcov.dart coverage/lcov.info
