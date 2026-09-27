import SwiftUI
import PareCore

/// Squircle tile with a white SF Symbol glyph, used for category and destination icons everywhere.
struct IconTile: View {
    let symbol: String
    let swatch: ThemeSwatch
    var size: CGFloat = 28

    @Environment(\.colorScheme) private var colorScheme

    /// Top-stop lighten amount. Reduced from the 8-12% spec target because
    /// `userCaches`' dark swatch only clears 3:1 glyph contrast up to ~7%.
    static let gradientLightenAmount: Double = 0.06
    static let gradientDarkenAmount: Double = 0.08

    init(symbol: String, swatch: ThemeSwatch, size: CGFloat = 28) {
        self.symbol = symbol
        self.swatch = swatch
        self.size = size
    }

    /// Convenience for scan categories, resolving swatch and symbol from `CategoryStyle`.
    init(category: ScanCategory, size: CGFloat = 28) {
        self.init(symbol: CategoryStyle.symbol(for: category), swatch: CategoryStyle.swatch(for: category), size: size)
    }

    private var resolved: RGBA { colorScheme == .dark ? swatch.dark : swatch.light }
    private var topStop: RGBA { Self.topGradientStop(for: resolved) }
    private var bottomStop: RGBA { Self.bottomGradientStop(for: resolved) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)

        shape
            .fill(
                LinearGradient(
                    colors: [Color(nsColor: topStop.nsColor), Color(nsColor: bottomStop.nsColor)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: max(0.5, size * 0.03)
                )
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.58, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: Color(nsColor: bottomStop.nsColor).opacity(0.28), radius: size * 0.06, x: 0, y: size * 0.03)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    // MARK: - Gradient stop math (pure, testable)

    /// The gradient's lightest (top) stop — also the one checked for glyph contrast.
    static func topGradientStop(for base: RGBA) -> RGBA {
        base.lightened(by: gradientLightenAmount)
    }

    /// The gradient's darkest (bottom) stop.
    static func bottomGradientStop(for base: RGBA) -> RGBA {
        base.darkened(by: gradientDarkenAmount)
    }
}

private extension RGBA {
    /// Blends this color toward white by `amount` (0...1); used for icon-tile gradient stops.
    func lightened(by amount: Double) -> RGBA {
        blended(toward: RGBA(0xFFFFFF), amount: amount)
    }

    /// Blends this color toward black by `amount` (0...1); used for icon-tile gradient stops.
    func darkened(by amount: Double) -> RGBA {
        blended(toward: RGBA(0x000000), amount: amount)
    }

    private func blended(toward target: RGBA, amount: Double) -> RGBA {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * amount }
        let r = (mix(red, target.red) * 255).rounded()
        let g = (mix(green, target.green) * 255).rounded()
        let b = (mix(blue, target.blue) * 255).rounded()
        let hex = (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
        return RGBA(hex, alpha: alpha)
    }
}

#if DEBUG
struct IconTile_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            grid.environment(\.colorScheme, .light).background(Color.white).previewDisplayName("Light")
            grid.environment(\.colorScheme, .dark).background(Color.black).previewDisplayName("Dark")
        }
    }

    static var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 8), spacing: 12) {
            ForEach(ScanCategory.allCases, id: \.self) { category in
                IconTile(category: category, size: 28)
            }
        }
        .padding(24)
    }
}
#endif
