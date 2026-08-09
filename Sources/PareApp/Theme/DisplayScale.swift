import SwiftUI

/// Window-driven base scale for type and control density, multiplied by the
/// user zoom factor (`TextZoomController`).
///
/// Automatic size classes keep 13" laptops compact and 27" desktops readable;
/// users can further adjust with ⌘+/⌘− (persisted).
struct DisplayScale: Equatable {
    enum Class: String, Equatable {
        case compact      // ~13–14"
        case regular      // ~15–16"
        case large        // ~17–23"
        case extraLarge   // ~27" / large desktop full screen
    }

    let sizeClass: Class
    /// Combined multiplier: automatic size-class base × user zoom.
    let factor: CGFloat
    /// Automatic base only (before user zoom) — useful for debugging.
    let baseFactor: CGFloat
    /// User zoom multiplier (1.0 = 100%).
    let userZoom: CGFloat

    /// Base factors chosen so 27" full screen is comfortable out of the box.
    static let compactBase: CGFloat = 1.0
    static let regularBase: CGFloat = 1.12
    static let largeBase: CGFloat = 1.30
    static let extraLargeBase: CGFloat = 1.55

    static let compact = DisplayScale(sizeClass: .compact, baseFactor: compactBase, userZoom: 1)
    static let regular = DisplayScale(sizeClass: .regular, baseFactor: regularBase, userZoom: 1)
    static let large = DisplayScale(sizeClass: .large, baseFactor: largeBase, userZoom: 1)
    static let extraLarge = DisplayScale(sizeClass: .extraLarge, baseFactor: extraLargeBase, userZoom: 1)

    init(sizeClass: Class, baseFactor: CGFloat, userZoom: CGFloat) {
        self.sizeClass = sizeClass
        self.baseFactor = baseFactor
        self.userZoom = userZoom
        self.factor = baseFactor * userZoom
    }

    static func resolve(
        width: CGFloat,
        height: CGFloat,
        userZoom: CGFloat = 1.0
    ) -> DisplayScale {
        // Prefer width (primary layout axis). Also promote when both axes
        // indicate a large desktop canvas (e.g. 27" fullscreen).
        let sizeClass: Class
        let base: CGFloat
        if width >= 1800 || (width >= 1560 && height >= 980) {
            sizeClass = .extraLarge
            base = extraLargeBase
        } else if width >= 1400 || (width >= 1280 && height >= 900) {
            sizeClass = .large
            base = largeBase
        } else if width >= 1100 {
            sizeClass = .regular
            base = regularBase
        } else {
            sizeClass = .compact
            base = compactBase
        }
        return DisplayScale(sizeClass: sizeClass, baseFactor: base, userZoom: userZoom)
    }

    // MARK: - Scaled fonts
    //
    // Hierarchy is intentionally tight so module titles don’t dwarf body/list text.
    // pageTitle (modules) < heroTitle (welcome only); body/rows sit close to section.

    /// Welcome / marketing headline only (Smart Scan home).
    var heroTitle: Font { font(26, weight: .bold, design: .rounded) }
    /// Module screen titles (Apps, Homebrew, Settings, …).
    var pageTitle: Font { font(21, weight: .bold, design: .rounded) }
    /// Confirmation / management sheet titles.
    var sheetTitle: Font { font(22, weight: .bold, design: .rounded) }
    /// Monospaced log output lines (brew / maintenance streams).
    var logMono: Font { font(11, design: .monospaced) }
    /// Card / section headings inside a page.
    var sectionTitle: Font { font(16, weight: .semibold, design: .rounded) }
    /// Primary readable content.
    var body: Font { font(14, weight: .medium) }
    /// Secondary labels under titles, filter text.
    var caption: Font { font(13, weight: .medium) }
    /// Compact chips, badges, meta labels.
    var micro: Font { font(12, weight: .semibold) }
    /// List / table primary row text.
    var rowTitle: Font { font(14, weight: .semibold) }
    /// List secondary line (dates, descriptions).
    var rowMeta: Font { font(12, weight: .regular) }
    /// Monospaced version / path fragments in rows.
    var rowMono: Font { font(13, weight: .regular, design: .monospaced) }
    /// Column headers in Apps / Homebrew tables.
    var tableHeader: Font { font(12, weight: .semibold) }
    var chip: Font { font(14, weight: .bold, design: .rounded) }
    var chipSub: Font { font(12, weight: .medium) }
    var badge: Font { font(10, weight: .bold) }

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
    /// Pare's window-driven type/density scale.
    ///
    /// Named `pareDisplayScale` so it no longer shadows SwiftUI's built-in
    /// `\.displayScale` (`CGFloat` backing-scale factor).
    var pareDisplayScale: DisplayScale {
        get { self[DisplayScaleKey.self] }
        set { self[DisplayScaleKey.self] = newValue }
    }
}

// MARK: - Root injection

/// Measures the window, multiplies by user zoom, and injects `pareDisplayScale`.
struct DisplayScaleReader<Content: View>: View {
    @EnvironmentObject private var textZoom: TextZoomController
    @ViewBuilder let content: () -> Content

    @State private var windowSize: CGSize = .zero
    @State private var scale = DisplayScale.regular

    var body: some View {
        content()
            .environment(\.pareDisplayScale, scale)
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
                windowSize = size
                recompute()
            }
            .onChange(of: textZoom.factor) { _ in
                recompute()
            }
            .overlay(alignment: .top) {
                TextZoomHUD(message: textZoom.hudMessage)
                    .padding(.top, 28)
                    .animation(.easeOut(duration: 0.18), value: textZoom.hudMessage)
            }
    }

    private func recompute() {
        let next = DisplayScale.resolve(
            width: windowSize.width,
            height: windowSize.height,
            userZoom: textZoom.factor
        )
        if next != scale {
            scale = next
        }
    }
}

private struct WindowSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
