import PareCore
import XCTest
@testable import PareApp

final class IconTileGradientTests: XCTestCase {

    // MARK: - White glyph vs. lightest gradient stop (category tiles)

    func testWhiteGlyphMeetsThreeToOneAgainstLightestStopForEveryCategory() {
        let white = RGBA(0xFFFFFF)
        for category in ScanCategory.allCases {
            let swatch = CategoryStyle.swatch(for: category)

            let darkStop = IconTile.topGradientStop(for: swatch.dark)
            let darkRatio = WCAG.contrastRatio(white, darkStop)
            XCTAssertGreaterThanOrEqual(darkRatio, 3.0, "\(category) lightest stop fails glyph contrast in dark mode: \(darkRatio)")

            let lightStop = IconTile.topGradientStop(for: swatch.light)
            let lightRatio = WCAG.contrastRatio(white, lightStop)
            XCTAssertGreaterThanOrEqual(lightRatio, 3.0, "\(category) lightest stop fails glyph contrast in light mode: \(lightRatio)")
        }
    }

    // MARK: - White glyph vs. lightest gradient stop (sidebar destination tiles)

    func testWhiteGlyphMeetsThreeToOneAgainstLightestStopForEveryDestination() {
        let white = RGBA(0xFFFFFF)
        for destination in AppDestination.allCases {
            let swatch = DestinationStyle.swatch(for: destination)

            let darkStop = IconTile.topGradientStop(for: swatch.dark)
            let darkRatio = WCAG.contrastRatio(white, darkStop)
            XCTAssertGreaterThanOrEqual(darkRatio, 3.0, "\(destination) lightest stop fails glyph contrast in dark mode: \(darkRatio)")

            let lightStop = IconTile.topGradientStop(for: swatch.light)
            let lightRatio = WCAG.contrastRatio(white, lightStop)
            XCTAssertGreaterThanOrEqual(lightRatio, 3.0, "\(destination) lightest stop fails glyph contrast in light mode: \(lightRatio)")
        }
    }

    // MARK: - Gradient stops actually differ from the base swatch (not a no-op)

    func testTopStopIsLighterThanBaseAndBottomStopIsDarker() {
        let base = RGBA(0x2A9D92)
        let top = IconTile.topGradientStop(for: base)
        let bottom = IconTile.bottomGradientStop(for: base)

        XCTAssertGreaterThan(top.red, base.red)
        XCTAssertGreaterThan(top.green, base.green)
        XCTAssertGreaterThan(top.blue, base.blue)

        XCTAssertLessThan(bottom.red, base.red)
        XCTAssertLessThan(bottom.green, base.green)
        XCTAssertLessThan(bottom.blue, base.blue)
    }
}
