import AppKit
import XCTest
@testable import PareApp

final class ThemeContrastTests: XCTestCase {

    // MARK: - WCAG formula sanity

    func testContrastRatioBlackWhiteIsTwentyOne() {
        XCTAssertEqual(WCAG.contrastRatio(RGBA(0x000000), RGBA(0xFFFFFF)), 21, accuracy: 0.01)
    }

    func testContrastRatioIsSymmetric() {
        let a = RGBA(0x5CC8BC)
        let b = RGBA(0x0D1520)
        XCTAssertEqual(WCAG.contrastRatio(a, b), WCAG.contrastRatio(b, a), accuracy: 0.0001)
    }

    // MARK: - Palette pairs, both modes

    private struct Pair {
        let name: String
        let text: KeyPath<ThemeSwatchTable, ThemeSwatch>
        let groundName: String
        let ground: KeyPath<ThemeSwatchTable, ThemeSwatch>
    }

    /// Bundles the swatches under test so the table below can address them by key path.
    private struct ThemeSwatchTable {
        let base = AppTheme.Swatch.base
        let panel = AppTheme.Swatch.panel
        let panelSecondary = AppTheme.Swatch.panelSecondary
        let textPrimary = AppTheme.Swatch.textPrimary
        let textSecondary = AppTheme.Swatch.textSecondary
        let textTertiary = AppTheme.Swatch.textTertiary
        let accentText = AppTheme.Swatch.accent
        let success = AppTheme.Swatch.success
        let warning = AppTheme.Swatch.warning
        let review = AppTheme.Swatch.review
    }

    private let table = ThemeSwatchTable()

    private let pairs: [Pair] = {
        let grounds: [(String, KeyPath<ThemeSwatchTable, ThemeSwatch>)] = [
            ("base", \.base), ("panel", \.panel), ("panelSecondary", \.panelSecondary)
        ]
        let texts: [(String, KeyPath<ThemeSwatchTable, ThemeSwatch>)] = [
            ("textPrimary", \.textPrimary),
            ("textSecondary", \.textSecondary),
            ("textTertiary", \.textTertiary),
            ("accentText", \.accentText),
            ("success", \.success),
            ("warning", \.warning),
            ("review", \.review)
        ]
        return texts.flatMap { name, text in
            grounds.map { groundName, ground in Pair(name: name, text: text, groundName: groundName, ground: ground) }
        }
    }()

    func testEveryTextTokenMeetsBodyContrastInBothModes() {
        for pair in pairs {
            let text = table[keyPath: pair.text]
            let ground = table[keyPath: pair.ground]

            let darkRatio = WCAG.contrastRatio(text.dark, ground.dark)
            XCTAssertGreaterThanOrEqual(
                darkRatio, 4.5,
                "\(pair.name) on \(pair.groundName) fails in dark mode: \(darkRatio)"
            )

            let lightRatio = WCAG.contrastRatio(text.light, ground.light)
            XCTAssertGreaterThanOrEqual(
                lightRatio, 4.5,
                "\(pair.name) on \(pair.groundName) fails in light mode: \(lightRatio)"
            )
        }
    }

    func testOnAccentMeetsContrastAgainstAccentInBothModes() {
        let onAccent = AppTheme.Swatch.onAccent
        let accent = AppTheme.Swatch.accent

        XCTAssertGreaterThanOrEqual(WCAG.contrastRatio(onAccent.dark, accent.dark), 4.5)
        XCTAssertGreaterThanOrEqual(WCAG.contrastRatio(onAccent.light, accent.light), 4.5)
    }

    // MARK: - Dynamic NSColor resolution

    func testSwatchResolvesDifferentComponentsPerAppearance() throws {
        let swatch = AppTheme.Swatch.textPrimary
        var lightComponents: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        var darkComponents: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)

        let aqua = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAqua = try XCTUnwrap(NSAppearance(named: .darkAqua))

        aqua.performAsCurrentDrawingAppearance {
            let resolved = swatch.nsColor.usingColorSpace(.sRGB)!
            lightComponents = (resolved.redComponent, resolved.greenComponent, resolved.blueComponent)
        }
        darkAqua.performAsCurrentDrawingAppearance {
            let resolved = swatch.nsColor.usingColorSpace(.sRGB)!
            darkComponents = (resolved.redComponent, resolved.greenComponent, resolved.blueComponent)
        }

        XCTAssertTrue(lightComponents != darkComponents)
    }
}
