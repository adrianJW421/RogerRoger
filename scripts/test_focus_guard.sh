#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vibecast-focus-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -O -module-cache-path "${VIBECAST_MODULE_CACHE:-$TEST_DIR/module-cache}" \
  "$ROOT/mac/Sources/VibeCast/Accessibility/FocusController.swift" \
  "$ROOT/mac/Sources/VibeCast/Accessibility/TextWriter.swift" \
  "$ROOT/mac/Sources/VibeCast/Accessibility/SendAction.swift" \
  "$ROOT/mac/Sources/VibeCast/Session/SendGate.swift" \
  "$ROOT/scripts/focus-regression/main.swift" -o "$TEST_DIR/test-focus"
"$TEST_DIR/test-focus"
