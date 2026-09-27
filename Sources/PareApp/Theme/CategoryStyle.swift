import SwiftUI
import PareCore

/// Single source of truth for category tile swatches, symbols, and ordered chart colors.
///
/// The category list ("Browse by category"), finding rows, and the Device Backups card
/// all consume this palette so tiles never disagree between views. `ScanCategory`
/// lives in PareCore (no UI dependencies), so the color mapping lives here.
enum CategoryStyle {
    // MARK: - Swatch (light/dark tile fill)

    /// Swatch for a scan category's icon tile — see "Category → color / symbol" in the redesign plan.
    static func swatch(for category: ScanCategory) -> ThemeSwatch {
        switch category {
        case .userCaches:
            return ThemeSwatch(light: RGBA(0x1F8A80), dark: RGBA(0x2A9D92))
        case .temporaryFiles:
            return ThemeSwatch(light: RGBA(0xB86E00), dark: RGBA(0xC27A12))
        case .logsAndCrashReports:
            return ThemeSwatch(light: RGBA(0xC4453A), dark: RGBA(0xD0584C))
        case .browserCaches:
            return ThemeSwatch(light: RGBA(0x2F7FD6), dark: RGBA(0x3D8BE0))
        case .developerBuildArtifacts:
            return ThemeSwatch(light: RGBA(0x7650D8), dark: RGBA(0x8660E0))
        case .developerPackageCaches:
            return ThemeSwatch(light: RGBA(0x1778A8), dark: RGBA(0x2A8AB8))
        case .developerSimulatorCaches:
            return ThemeSwatch(light: RGBA(0x8A6A3E), dark: RGBA(0x9C7A4A))
        case .designerCaches:
            return ThemeSwatch(light: RGBA(0xD14E7A), dark: RGBA(0xD85F88))
        case .videoBuilderCaches:
            return ThemeSwatch(light: RGBA(0x2E8B57), dark: RGBA(0x3A9863))
        case .aiToolCaches:
            return ThemeSwatch(light: RGBA(0x5A5FE0), dark: RGBA(0x6A6FE6))
        case .installerFiles:
            return ThemeSwatch(light: RGBA(0x9A7A12), dark: RGBA(0xA88720))
        case .applications:
            return ThemeSwatch(light: RGBA(0x9A4FC8), dark: RGBA(0xA75ED2))
        case .projectArtifacts:
            return ThemeSwatch(light: RGBA(0xB25E1E), dark: RGBA(0xBE6B2C))
        case .deviceBackups:
            return ThemeSwatch(light: RGBA(0x3F6F8F), dark: RGBA(0x5585A6))
        case .productivityCaches:
            return ThemeSwatch(light: RGBA(0x5E7F1E), dark: RGBA(0x6E9028))
        case .launchAgents:
            return ThemeSwatch(light: RGBA(0x5E6B78), dark: RGBA(0x6E7C8A))
        }
    }

    // MARK: - Symbol

    /// SF Symbol for a scan category's icon tile.
    static func symbol(for category: ScanCategory) -> String {
        switch category {
        case .userCaches:
            return "tray.full.fill"
        case .temporaryFiles:
            return "hourglass"
        case .logsAndCrashReports:
            return "doc.text.fill"
        case .browserCaches:
            return "globe"
        case .developerBuildArtifacts:
            return "hammer.fill"
        case .developerPackageCaches:
            return "shippingbox.fill"
        case .developerSimulatorCaches:
            return "iphone"
        case .designerCaches:
            return "paintbrush.pointed.fill"
        case .videoBuilderCaches:
            return "film.fill"
        case .aiToolCaches:
            return "brain.head.profile"
        case .installerFiles:
            return "arrow.down.doc.fill"
        case .applications:
            return "app.fill"
        case .projectArtifacts:
            return "folder.fill.badge.gearshape"
        case .deviceBackups:
            return "externaldrive.fill.badge.timemachine"
        case .productivityCaches:
            return "briefcase.fill"
        case .launchAgents:
            return "gearshape.2.fill"
        }
    }

    // MARK: - Category tint

    /// Tint for a scan category — kept for callers predating the swatch-based tile API.
    static func tint(for category: ScanCategory) -> Color {
        swatch(for: category).color
    }

    // MARK: - Ordered chart palette

    /// Ordered palette for index-colored charts (e.g. the tool-share donut), one entry per category.
    static let chartPalette: [Color] = ScanCategory.allCases.map { swatch(for: $0).color }

    /// Chart color for a slice / legend index (wraps around).
    static func chartColor(at index: Int) -> Color {
        chartPalette[index % chartPalette.count]
    }

    // MARK: - Deprecated named colors

    /// Deprecated: use `swatch(for: .developerPackageCaches)`. Kept only so pre-2.8 call sites still compile.
    @available(*, deprecated, message: "Use swatch(for:) instead")
    static let sky = Color(red: 0.50, green: 0.85, blue: 0.94)
}
