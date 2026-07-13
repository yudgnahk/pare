import SwiftUI

/// Central design tokens for Pare — teal / navy premium utility aesthetic.
enum AppTheme {
    // MARK: - Color (Pare teal / navy)

    static let base = Color(red: 0.04, green: 0.09, blue: 0.14)
    static let panel = Color(red: 0.08, green: 0.16, blue: 0.22)
    static let panelSecondary = Color(red: 0.06, green: 0.13, blue: 0.18)
    static let sidebar = Color(red: 0.05, green: 0.11, blue: 0.16)
    static let sidebarSelected = Color(red: 0.12, green: 0.28, blue: 0.34)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary = Color.white.opacity(0.48)
    /// Pare teal accent
    static let accent = Color(red: 0.18, green: 0.82, blue: 0.78)
    static let accentDeep = Color(red: 0.10, green: 0.55, blue: 0.62)
    static let success = Color(red: 0.34, green: 0.86, blue: 0.58)
    static let warning = Color(red: 0.97, green: 0.74, blue: 0.31)
    static let review = Color(red: 0.98, green: 0.48, blue: 0.42)

    static let pageGradient = LinearGradient(
        colors: [
            Color(red: 0.03, green: 0.08, blue: 0.12),
            Color(red: 0.05, green: 0.16, blue: 0.22),
            Color(red: 0.07, green: 0.22, blue: 0.28)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGlow = RadialGradient(
        colors: [
            accent.opacity(0.35),
            accentDeep.opacity(0.12),
            .clear
        ],
        center: .center,
        startRadius: 20,
        endRadius: 280
    )

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let pageHorizontal: CGFloat = 28
        static let pageVertical: CGFloat = 22
        static let sidebarWidth: CGFloat = 220
    }

    // MARK: - Radius

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let pill: CGFloat = 999
    }

    // MARK: - Control sizes

    enum Control {
        static let primaryHeight: CGFloat = 36
        static let secondaryHeight: CGFloat = 32
        static let iconSize: CGFloat = 28
        static let primaryMinWidth: CGFloat = 112
        static let ringButtonSize: CGFloat = 96
    }

    // MARK: - Motion

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.18)
        static let standard = Animation.spring(response: 0.38, dampingFraction: 0.86)
        static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.88)
        static let ringPulse = Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)
        static func stagger(index: Int, base: Double = 0.05) -> Animation {
            .spring(response: 0.4, dampingFraction: 0.86).delay(Double(index) * base)
        }
    }

    // MARK: - Breakpoints

    enum Breakpoint {
        static let compact: CGFloat = 900
        static let regular: CGFloat = 1100
        static let wide: CGFloat = 1400
        static let metricMin: CGFloat = 200
        static let cardMin: CGFloat = 300
    }

    // MARK: - Window

    enum Window {
        static let minWidth: CGFloat = 980
        static let minHeight: CGFloat = 640
        static let defaultWidth: CGFloat = 1240
        static let defaultHeight: CGFloat = 800
    }

    // MARK: - Typography fallbacks

    enum TypeScale {
        static let heroTitle: Font = DisplayScale.compact.heroTitle
        static let sectionTitle: Font = DisplayScale.compact.sectionTitle
        static let body: Font = DisplayScale.compact.body
        static let caption: Font = DisplayScale.compact.caption
        static let micro: Font = DisplayScale.compact.micro
    }
}
