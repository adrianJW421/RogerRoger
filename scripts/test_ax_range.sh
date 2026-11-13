#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vibecast-range-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cat > "$TEST_DIR/main.swift" <<'SWIFT'
import Foundation
import ApplicationServices

var cases = (0..<1000).map { CFRangeMake($0 * 3, $0 + 1) }
cases += [CFRangeMake(0, 0), CFRangeMake(5, 0), CFRangeMake(8, 4)]
for expected in cases {
    guard let value = AXSupport.textRangeValue(expected) else {
        fatalError("Valid range was rejected")
    }
    var actual = CFRange()
    guard AXValueGetValue(value, .cfRange, &actual),
          actual.location == expected.location, actual.length == expected.length else {
        fatalError("Range corrupted: expected \(expected), got \(actual)")
    }
}
precondition(AXSupport.textRangeValue(CFRangeMake(-1, 0)) == nil)
precondition(AXSupport.textRangeValue(CFRangeMake(0, -1)) == nil)
let snapshots = ["我试了", "我试了一下", "我试了一下它存在问题", "我试了一下它存在问题他在电脑上", "我试了一下，它存在问题，他在电脑上会出现大量的重复。"]
for (prefix, suffix) in [("", ""), ("已有内容🙂：", "\n后续内容")] {
    let document = NSMutableString(string: prefix + suffix)
    let anchor = (prefix as NSString).length
    var previousLength = 0
    for snapshot in snapshots {
        let value = AXSupport.textRangeValue(CFRangeMake(anchor, previousLength))!
        var actual = CFRange()
        precondition(AXValueGetValue(value, .cfRange, &actual))
        document.replaceCharacters(in: NSRange(location: actual.location, length: actual.length), with: snapshot)
        previousLength = (snapshot as NSString).length
        precondition(document as String == prefix + snapshot + suffix)
    }
}
print("PASS: \(cases.count) range round trips + 2 invalid ranges + progressive dictation in empty/existing text, release optimization")
SWIFT
swiftc -O -module-cache-path "${VIBECAST_MODULE_CACHE:-$TEST_DIR/module-cache}" \
  "$ROOT/mac/Sources/VibeCast/Accessibility/AXSupport.swift" \
  "$TEST_DIR/main.swift" -o "$TEST_DIR/test-ax-range"
"$TEST_DIR/test-ax-range"
