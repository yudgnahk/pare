import SwiftUI

/// Window-driven scale for type and control density.
/// Resolves from the live window size so 13" laptops stay compact while
/// 23–27" full-screen sessions get larger, more readable text.
struct DisplayScale: Equatable {
    enum Class: String, Equatable {
        case compact      // ~13–14"
        case regular      // ~15–16"
        case large        // ~17–23"
        case extraLarge   // ~27" / large desktop full screen
    }

    let sizeClass: Class
    /// Multiplier applied to base point sizes (13pt body → 13 × factor).
    let factor: CGFloat

    static let compact = DisplayScale(sizeClass: .compact, factor: 1.0)
    static let regular = DisplayScale(sizeClass: .regular, factor: 1.08)
    static let large = DisplayScale(sizeClass: .large, factor: 1.18)
    static let extraLarge = DisplayScale(sizeClass: .extraLarge, factor: 1.32)

    static func resolve(width: CGFloat, height: CGFloat) -> DisplayScale {
        // Prefer width (primary layout axis). Also promote when both axes
        // indicate a large desktop canvas (e.g. 27" fullscreen).
        if width >= 1800 || (width >= 1560 && height >= 980) {
            return .extraLarge
        }
        if width >= 1400 || (width >= 1280 && height >= 900) {
            return .large
        }
        if width >= 1100 {
            return .regular
        }
        return .compact
    }

    // MARK: - Scaled fonts

    var heroTitle: Font { font(28, weight: .bold, design: .rounded) }
    var sectionTitle: Font { font(18, weight: .bold, design: .rounded) }
    var body: Font { font(13, weight: .medium) }
    var caption: Font { font(12, weight: .medium) }
    var micro: Font { font(11, weight: .semibold) }
    var rowTitle: Font { font(13, weight: .semibold) }
    var rowMeta: Font { font(11, weight: .regular) }
    var rowMono: Font { font(12, weight: .regular, design: .monospaced) }
    var tableHeader: Font { font(11, weight: .semibold) }
    var chip: Font { font(13, weight: .bold, design: .rounded) }
    var chipSub: Font { font(11, weight: .medium) }
    var badge: Font { font(9, weight: .bold) }

    func font(
        _ base: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(
            size: scaled(base),
            weight: weight,
            design: design
        )
    }

    func scaled(_ base: CGFloat) -> CGFloat {
        max(10, (base * factor).rounded(.toNearestOrAwayFromZero))
    }

    /// Milder scale for padding / control heights so layout doesn't explode.
    var spacingFactor: CGFloat {
        1 + (factor - 1) * 0.45
    }

    func space(_ base: CGFloat) -> CGFloat {
        (base * spacingFactor).rounded(.toNearestOrAwayFromZero)
    }

    /// Column widths used by Apps / Homebrew tables.
    var colVersion: CGFloat { scaled(100) }
    var colSize: CGFloat { scaled(90) }
    var colDate: CGFloat { scaled(100) }
    var colActions: CGFloat { scaled(80) }
}

// MARK: - Environment

private struct DisplayScaleKey: EnvironmentKey {
    static let defaultValue = DisplayScale.regular
}

extension EnvironmentValues {
    var displayScale: DisplayScale {
        get { self[DisplayScaleKey.self] }
        set { self[DisplayScaleKey.self] = newValue }
    }
}

// MARK: - Root injection

/// Measures the window and injects `displayScale` for all descendants.
struct DisplayScaleReader<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var scale = DisplayScale.regular

    var body: some View {
        content()
            .environment(\.displayScale, scale)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: WindowSizePreferenceKey.self,
                            value: geo.size
                        )
                }
            )
            .onPreferenceChange(WindowSizePreferenceKey.self) { size in
                let next = DisplayScale.resolve(width: size.width, height: size.height)
                if next != scale {
                    scale = next
                }
            }
    }
}

private struct WindowSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
