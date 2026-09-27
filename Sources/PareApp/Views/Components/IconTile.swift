import SwiftUI
import PareCore

/// Squircle tile with a white SF Symbol glyph, used for category and destination icons everywhere.
struct IconTile: View {
    let symbol: String
    let swatch: ThemeSwatch
    var size: CGFloat = 28

    init(symbol: String, swatch: ThemeSwatch, size: CGFloat = 28) {
        self.symbol = symbol
        self.swatch = swatch
        self.size = size
    }

    /// Convenience for scan categories, resolving swatch and symbol from `CategoryStyle`.
    init(category: ScanCategory, size: CGFloat = 28) {
        self.init(symbol: CategoryStyle.symbol(for: category), swatch: CategoryStyle.swatch(for: category), size: size)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(swatch.color)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.06), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.58, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
