import SwiftUI
import PareCore

/// Single source of truth for category tints and ordered chart colors.
///
/// The category list ("Browse by category") and the tool-share donut chart both
/// consume this palette so colors never disagree between views. `ScanCategory`
/// lives in PareCore (no UI dependencies), so the color mapping lives here.
enum CategoryStyle {
    // MARK: - Named palette values

    /// Developer Build Artifacts.
    static let lavender = Color(red: 0.68, green: 0.57, blue: 0.96)
    /// Developer Package Caches.
    static let sky = Color(red: 0.50, green: 0.85, blue: 0.94)
    /// Developer Simulator Caches.
    static let sand = Color(red: 0.86, green: 0.66, blue: 0.44)
    /// Designer Caches.
    static let coral = Color(red: 0.92, green: 0.62, blue: 0.41)
    /// Video Builder Caches.
    static let sage = Color(red: 0.48, green: 0.77, blue: 0.61)
    /// AI Tool Caches.
    static let periwinkle = Color(red: 0.56, green: 0.76, blue: 0.98)
    /// Installer Files.
    static let gold = Color(red: 0.85, green: 0.75, blue: 0.45)
    /// Applications.
    static let violet = Color(red: 0.72, green: 0.55, blue: 0.88)
    /// Project Artifacts.
    static let amber = Color(red: 0.94, green: 0.72, blue: 0.37)

    // MARK: - Category tint

    /// Tint for a scan category — used by category dots, rows, and charts.
    static func tint(for category: ScanCategory) -> Color {
        switch category {
        case .userCaches:
            return AppTheme.accent
        case .temporaryFiles:
            return AppTheme.warning
        case .logsAndCrashReports:
            return AppTheme.review
        case .browserCaches:
            return AppTheme.success
        case .developerBuildArtifacts:
            return lavender
        case .developerPackageCaches:
            return sky
        case .developerSimulatorCaches:
            return sand
        case .designerCaches:
            return coral
        case .videoBuilderCaches:
            return sage
        case .aiToolCaches:
            return periwinkle
        case .installerFiles:
            return gold
        case .applications:
            return violet
        case .projectArtifacts:
            return amber
        case .deviceBackups:
            return Color.indigo
        case .productivityCaches:
            return Color.teal
        case .launchAgents:
            return Color.orange
        }
    }

    // MARK: - Ordered chart palette

    /// Ordered palette for index-colored charts (e.g. the tool-share donut).
    /// Drawn from the same named values as `tint(for:)` so list and chart agree.
    static let chartPalette: [Color] = [
        AppTheme.accent,
        sky,
        lavender,
        AppTheme.success,
        AppTheme.warning,
        coral,
        sage,
        sand,
        Color.teal,
        Color.indigo.opacity(0.85)
    ]

    /// Chart color for a slice / legend index (wraps around).
    static func chartColor(at index: Int) -> Color {
        chartPalette[index % chartPalette.count]
    }
}
