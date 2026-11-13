#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rogerroger-pairing-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -O -module-cache-path "${VIBECAST_MODULE_CACHE:-$TEST_DIR/module-cache}" \
  "$ROOT/mac/Sources/VibeCast/App/PairingQRCode.swift" \
  "$ROOT/mac/Sources/VibeCast/App/PairingWindowController.swift" \
  "$ROOT/mac/Sources/VibeCast/App/MacI18n.swift" \
  "$ROOT/scripts/pairing-regression/main.swift" -o "$TEST_DIR/test-pairing"
"$TEST_DIR/test-pairing" "$@"
