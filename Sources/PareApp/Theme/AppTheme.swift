import SwiftUI

/// Central design tokens for Pare — teal / navy premium utility aesthetic.
///
/// Color source of truth: `docs/brand-guide.html`. Semantic tokens below point
/// at the brand palette; views must never hardcode colors, radii, or paddings.
enum AppTheme {
    // MARK: - Brand palette (docs/brand-guide.html)

    /// Raw brand colors. Prefer the semantic tokens (`base`, `panel`, `accent`,
    /// `textPrimary`, …) in views; reach for `Brand` only when defining new
    /// semantic tokens.
    enum Brand {
        /// Page ground.
        static let ink = Color(hex: 0x0D1520)
        /// Recessed / secondary surface.
        static let marine = Color(hex: 0x152030)
        /// Raised surface (cards, panels).
        static let surface = Color(hex: 0x1A2D40)
        /// Primary mark — Pare seafoam accent.
        static let seafoam = Color(hex: 0x5CC8BC)
        /// Highlight ("Mist").
        static let seafoamLight = Color(hex: 0x8DE8E0)
        /// Deep accent for gradients and pressed states.
        static let seafoamDeep = Color(hex: 0x238C82)
        /// Typography.
        static let chalk = Color(hex: 0xE4EDF2)
        /// Warm typography accents.
        static let chalkWarm = Color(hex: 0xEDF2F5)
        /// Secondary text (brand); use with care on dark grounds (contrast).
        static let fog = Color(hex: 0x7A9BB0)
    }

    // MARK: - Semantic colors

    static let base = Brand.ink
    static let panel = Brand.surface
    static let panelSecondary = Brand.marine
    static let sidebar = Brand.marine
    static let sidebarSelected = Color(hex: 0x1F4757)
    static let textPrimary = Brand.chalk
    static let textSecondary = Brand.chalk.opacity(0.72)
    static let textTertiary = Brand.chalk.opacity(0.48)
    /// Pare seafoam accent
    static let accent = Brand.seafoam
    static let accentDeep = Brand.seafoamDeep
    static let success = Color(red: 0.34, green: 0.86, blue: 0.58)
    static let warning = Color(red: 0.97, green: 0.74, blue: 0.31)
    static let review = Color(red: 0.98, green: 0.48, blue: 0.42)

    /// Column-header strip behind sortable tables (Apps, Homebrew).
    static let tableHeaderBackground = Color.black.opacity(0.12)

    static let pageGradient = LinearGradient(
        colors: [
            Brand.ink,
            Brand.marine,
            Brand.surface
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

    // MARK: - Hairlines (strokes / dividers)

    /// Consolidated hairline strokes — replaces the ad-hoc white alphas that
    /// used to be scattered across views.
    enum Hairline {
        /// Barely-there separators and resting row washes.
        static let faint = Color.white.opacity(0.04)
        /// Standard 1 pt strokes / dividers — brand `--border` (white 7%).
        static let standard = Color.white.opacity(0.07)
        /// Emphasized strokes (hovered capsules, prominent borders).
        static let strong = Color.white.opacity(0.14)
    }

    // MARK: - Translucent fills (chips, rows, controls)

    enum Fill {
        /// Resting chip / row background.
        static let subtle = Color.white.opacity(0.06)
        /// Slightly raised control background (capsule chips, pills).
        static let control = Color.white.opacity(0.08)
        /// Hover highlight for rows and controls.
        static let hover = Color.white.opacity(0.10)
        /// Selected segment / tab background.
        static let selected = Color.white.opacity(0.18)
    }

    // MARK: - Spacing

    enum Spacing {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let pageHorizontal: CGFloat = 28
        static let pageVertical: CGFloat = 22
        /// Default GlassCard content padding.
        static let card: CGFloat = 18
        /// Dense cards (selection bar, coaching cards).
        static let cardCompact: CGFloat = 14
        /// Fixed left nav column — always visible (not collapsible SplitView).
        static let sidebarWidth: CGFloat = 232
    }

    // MARK: - Radius

    enum Radius {
        static let sm: CGFloat = 8
        /// List / table rows and inline banners.
        static let row: CGFloat = 10
        static let md: CGFloat = 12
        /// Filter chips, sort menus, metric chips.
        static let chip: CGFloat = 10
        /// Compact chips (segmented tab highlight).
        static let chipCompact: CGFloat = 7
        /// Tiny status badges (pinned / auto / MAS).
        static let badge: CGFloat = 4
        static let xl: CGFloat = 20
    }

    // MARK: - Sheets

    enum Sheet {
        /// Single-purpose confirmations (Leave Homebrew).
        static let narrowWidth: CGFloat = 460
        /// Standard management sheets (exclusions, project paths, bulk confirm).
        static let standardWidth: CGFloat = 520
        /// Detail-heavy confirmations (uninstall with leftovers, deep clean).
        static let wideWidth: CGFloat = 560
        /// Streaming operation log sheet.
        static let operationWidth: CGFloat = 620
        static let standardHeight: CGFloat = 420
        static let operationHeight: CGFloat = 480
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
    }

    // MARK: - Breakpoints

    enum Breakpoint {
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
}

// MARK: - Hex color support

extension Color {
    /// Creates an opaque sRGB color from a 24-bit `0xRRGGBB` literal.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1
        )
    }
}
