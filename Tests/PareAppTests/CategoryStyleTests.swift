import AppKit
import PareCore
import XCTest
@testable import PareApp

final class CategoryStyleTests: XCTestCase {

    // MARK: - Symbols resolve on this OS

    func testEveryCategorySymbolResolvesAsSystemImage() throws {
        for category in ScanCategory.allCases {
            let symbol = CategoryStyle.symbol(for: category)
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            XCTAssertNotNil(image, "\(category) symbol '\(symbol)' does not resolve on this macOS version")
        }
    }

    // MARK: - White glyph contrast on each tile

    func testWhiteGlyphMeetsThreeToOneOnEveryTileInBothModes() {
        let white = RGBA(0xFFFFFF)
        for category in ScanCategory.allCases {
            let swatch = CategoryStyle.swatch(for: category)

            let darkRatio = WCAG.contrastRatio(white, swatch.dark)
            XCTAssertGreaterThanOrEqual(darkRatio, 3.0, "\(category) tile fails glyph contrast in dark mode: \(darkRatio)")

            let lightRatio = WCAG.contrastRatio(white, swatch.light)
            XCTAssertGreaterThanOrEqual(lightRatio, 3.0, "\(category) tile fails glyph contrast in light mode: \(lightRatio)")
        }
    }

    // MARK: - Tile vs ground contrast

    func testTileMeetsThreeToOneOnPanelAndBaseInBothModes() {
        for category in ScanCategory.allCases {
            let swatch = CategoryStyle.swatch(for: category)

            let grounds: [(String, ThemeSwatch)] = [
                ("panel", AppTheme.Swatch.panel),
                ("base", AppTheme.Swatch.base)
            ]
            for (groundName, ground) in grounds {
                let darkRatio = WCAG.contrastRatio(swatch.dark, ground.dark)
                XCTAssertGreaterThanOrEqual(darkRatio, 3.0, "\(category) on \(groundName) fails in dark mode: \(darkRatio)")

                let lightRatio = WCAG.contrastRatio(swatch.light, ground.light)
                XCTAssertGreaterThanOrEqual(lightRatio, 3.0, "\(category) on \(groundName) fails in light mode: \(lightRatio)")
            }
        }
    }

    // MARK: - No two categories collide on both swatch and symbol

    func testNoTwoCategoriesShareBothSwatchAndSymbol() {
        var seen: Set<String> = []
        for category in ScanCategory.allCases {
            let swatch = CategoryStyle.swatch(for: category)
            let key = "\(CategoryStyle.symbol(for: category))|\(swatch.light.hex)|\(swatch.dark.hex)"
            XCTAssertTrue(seen.insert(key).inserted, "\(category) duplicates another category's swatch+symbol pair")
        }
    }

    // MARK: - Derived API stays consistent

    func testTintMatchesSwatchColorAndChartPaletteCoversAllCategories() {
        XCTAssertEqual(CategoryStyle.chartPalette.count, ScanCategory.allCases.count)
        for category in ScanCategory.allCases {
            let tint = NSColor(CategoryStyle.tint(for: category))
            let swatch = CategoryStyle.swatch(for: category).nsColor
            for appearance in [NSAppearance(named: .aqua)!, NSAppearance(named: .darkAqua)!] {
                XCTAssertEqual(resolvedHex(tint, appearance: appearance), resolvedHex(swatch, appearance: appearance))
            }
        }
    }

    private func resolvedHex(_ color: NSColor, appearance: NSAppearance) -> UInt32 {
        var hex: UInt32 = 0
        appearance.performAsCurrentDrawingAppearance {
            let resolved = color.usingColorSpace(NSColorSpace.deviceRGB)!
            let red = UInt32((resolved.redComponent * 255).rounded())
            let green = UInt32((resolved.greenComponent * 255).rounded())
            let blue = UInt32((resolved.blueComponent * 255).rounded())
            hex = (red << 16) | (green << 8) | blue
        }
        return hex
    }
}
