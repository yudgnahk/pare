import AppKit
import PareCore
import XCTest
@testable import PareApp

final class DiskKindStyleTests: XCTestCase {

    // MARK: - Symbols resolve on this OS

    func testEveryDiskKindSymbolResolvesAsSystemImage() throws {
        for kind in DiskKind.allCases {
            let symbol = DiskKindStyle.symbol(for: kind)
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            XCTAssertNotNil(image, "\(kind) symbol '\(symbol)' does not resolve on this macOS version")
        }
    }

    // MARK: - White glyph contrast on each tile

    func testWhiteGlyphMeetsThreeToOneOnEveryTileInBothModes() {
        let white = RGBA(0xFFFFFF)
        for kind in DiskKind.allCases {
            let swatch = DiskKindStyle.swatch(for: kind)

            let darkRatio = WCAG.contrastRatio(white, swatch.dark)
            XCTAssertGreaterThanOrEqual(darkRatio, 3.0, "\(kind) tile fails glyph contrast in dark mode: \(darkRatio)")

            let lightRatio = WCAG.contrastRatio(white, swatch.light)
            XCTAssertGreaterThanOrEqual(lightRatio, 3.0, "\(kind) tile fails glyph contrast in light mode: \(lightRatio)")
        }
    }
}
