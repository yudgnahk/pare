import SwiftUI

/// Central design tokens for Pare.
/// Tuned for native-feeling macOS utilities: clear hierarchy, restrained depth,
/// and layouts that work from 13" laptops through 27" displays.
enum AppTheme {
    // MARK: - Color

    static let base = Color(red: 0.05, green: 0.08, blue: 0.14)
    static let panel = Color(red: 0.10, green: 0.14, blue: 0.24)
    static let panelSecondary = Color(red: 0.08, green: 0.11, blue: 0.19)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.74)
    static let accent = Color(red: 0.20, green: 0.73, blue: 0.94)
    static let success = Color(red: 0.34, green: 0.83, blue: 0.55)
    static let warning = Color(red: 0.97, green: 0.74, blue: 0.31)
    static let review = Color(red: 0.98, green: 0.53, blue: 0.41)

    static let pageGradient = LinearGradient(
        colors: [
            Color(red: 0.03, green: 0.05, blue: 0.11),
            Color(red: 0.07, green: 0.14, blue: 0.22),
            Color(red: 0.12, green: 0.21, blue: 0.29)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Spacing (4pt base scale)

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        /// Standard horizontal page inset for dashboard content.
        static let pageHorizontal: CGFloat = 24
        /// Standard vertical page inset for dashboard content.
        static let pageVertical: CGFloat = 20
    }

    // MARK: - Radius

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let pill: CGFloat = 999
    }

    // MARK: - Control sizes (HIG-aligned)

    enum Control {
        /// Primary CTA height — comfortable hit target.
        static let primaryHeight: CGFloat = 36
        /// Secondary / toolbar control height.
        static let secondaryHeight: CGFloat = 32
        /// Compact icon-only control.
        static let iconSize: CGFloat = 28
        /// Minimum width for primary text buttons so labels don't feel cramped.
        static let primaryMinWidth: CGFloat = 112
    }

    // MARK: - Adaptive breakpoints

    /// Layout thresholds used with GeometryReader / adaptive grids.
    /// Sized for macOS point space across common displays:
    /// 13–14" ~1280–1512, 15–16" ~1728–1800, 17"+ ultrawide / desktop.
    enum Breakpoint {
        /// Below this width, multi-action headers stack and metrics go single-column.
        static let compact: CGFloat = 900
        /// Comfortable two-column card grids (Maintenance, etc.).
        static let regular: CGFloat = 1100
        /// Wide desktop layouts (23–27").
        static let wide: CGFloat = 1400
        /// Minimum useful width for a metric tile.
        static let metricMin: CGFloat = 200
        /// Minimum useful width for a maintenance / action card.
        static let cardMin: CGFloat = 300
    }

    // MARK: - Window

    /// Default and minimum window geometry.
    /// Minimum fits 13" MacBook content areas while still leaving room for
    /// title bar + tabs; no maximum — full screen is always available.
    enum Window {
        static let minWidth: CGFloat = 960
        static let minHeight: CGFloat = 640
        static let defaultWidth: CGFloat = 1200
        static let defaultHeight: CGFloat = 780
    }

    // MARK: - Typography

    enum TypeScale {
        static let heroTitle: Font = .system(size: 28, weight: .bold, design: .rounded)
        static let sectionTitle: Font = .system(size: 18, weight: .bold, design: .rounded)
        static let body: Font = .system(size: 13, weight: .medium)
        static let caption: Font = .system(size: 12, weight: .medium)
        static let micro: Font = .system(size: 11, weight: .semibold)
    }
}
