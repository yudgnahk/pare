import AppKit
import XCTest
@testable import PareApp

final class DestinationStyleTests: XCTestCase {

    // MARK: - Symbols resolve on this OS

    func testEveryDestinationSymbolResolvesAsSystemImage() throws {
        for destination in AppDestination.allCases {
            let image = NSImage(systemSymbolName: destination.systemImage, accessibilityDescription: nil)
            XCTAssertNotNil(image, "\(destination) symbol '\(destination.systemImage)' does not resolve on this macOS version")
        }
    }

    // MARK: - White glyph contrast on each tile

    func testWhiteGlyphMeetsThreeToOneOnEveryTileInBothModes() {
        let white = RGBA(0xFFFFFF)
        for destination in AppDestination.allCases {
            let swatch = DestinationStyle.swatch(for: destination)

            let darkRatio = WCAG.contrastRatio(white, swatch.dark)
            XCTAssertGreaterThanOrEqual(darkRatio, 3.0, "\(destination) tile fails glyph contrast in dark mode: \(darkRatio)")

            let lightRatio = WCAG.contrastRatio(white, swatch.light)
            XCTAssertGreaterThanOrEqual(lightRatio, 3.0, "\(destination) tile fails glyph contrast in light mode: \(lightRatio)")
        }
    }

    // MARK: - Derived API stays consistent

    func testTintMatchesSwatchColorForEveryDestination() {
        for destination in AppDestination.allCases {
            let tint = NSColor(DestinationStyle.tint(for: destination))
            let swatch = DestinationStyle.swatch(for: destination).nsColor
            for appearance in [NSAppearance(named: .aqua)!, NSAppearance(named: .darkAqua)!] {
                XCTAssertEqual(resolvedHex(tint, appearance: appearance), resolvedHex(swatch, appearance: appearance))
            }
        }
    }

    private func resolvedHex(_ color: NSColor, appearance: NSAppearance) -> UInt32 {
        let resolved = color.resolvedColor(with: appearance).usingColorSpace(.deviceRGB)!
        let red = UInt32((resolved.redComponent * 255).rounded())
        let green = UInt32((resolved.greenComponent * 255).rounded())
        let blue = UInt32((resolved.blueComponent * 255).rounded())
        return (red << 16) | (green << 8) | blue
    }
}
