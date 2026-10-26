import Foundation
import XCTest

@testable import ClashClientUI

final class CantoConfigCountTextTests: XCTestCase {
    func testUnknownCountDoesNotLeakOptionalText() {
        let subtitle = CantoConfigCountText.subtitle(
            format: "%@ rewrites",
            count: nil,
            suffix: "From modules and profiles",
            locale: Locale(identifier: "en")
        )

        XCTAssertFalse(subtitle.lowercased().contains("nil"))
        XCTAssertFalse(subtitle.contains("Optional"))
        XCTAssertFalse(subtitle.contains("·"))
        XCTAssertFalse(subtitle.isEmpty)
    }

    func testKnownCountIncludesNumberAndSource() {
        let subtitle = CantoConfigCountText.subtitle(
            format: "%@ rewrites",
            count: 12,
            suffix: "From modules and profiles",
            locale: Locale(identifier: "en")
        )

        XCTAssertTrue(subtitle.contains("12"))
        XCTAssertTrue(subtitle.contains("·"))
        XCTAssertFalse(subtitle.lowercased().contains("nil"))
    }
}
