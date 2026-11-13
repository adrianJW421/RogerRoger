import XCTest
import ApplicationServices
@testable import VibeCast

final class AXSupportTests: XCTestCase {
    // Run with release optimization too: an escaped temporary pointer can
    // appear correct in a debug build and corrupt every range in a release.
    func testTextRangeValuePreservesCoordinates() throws {
        for index in 0..<1000 {
            let expected = CFRangeMake(index * 3, index + 1)
            let value = try XCTUnwrap(AXSupport.textRangeValue(expected))
            var actual = CFRange()
            XCTAssertTrue(AXValueGetValue(value, .cfRange, &actual))
            XCTAssertEqual(actual.location, expected.location)
            XCTAssertEqual(actual.length, expected.length)
        }
    }

    func testTextRangeValueAcceptsCaretAndRejectsInvalidRanges() throws {
        let value = try XCTUnwrap(AXSupport.textRangeValue(CFRangeMake(5, 0)))
        var actual = CFRange()
        XCTAssertTrue(AXValueGetValue(value, .cfRange, &actual))
        XCTAssertEqual(actual.location, 5)
        XCTAssertEqual(actual.length, 0)
        XCTAssertNil(AXSupport.textRangeValue(CFRangeMake(-1, 0)))
        XCTAssertNil(AXSupport.textRangeValue(CFRangeMake(0, -1)))
    }
}
