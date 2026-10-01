import SwiftUI

/// Page ground: mist/ink base with a seafoam bloom top-trailing and an apricot counterweight bottom-leading.
struct AppBackgroundView: View {
    var body: some View {
        ZStack {
            AppTheme.pageGradient

            RadialGradient(
                colors: [AppTheme.Background.bloom, .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 560
            )

            RadialGradient(
                colors: [AppTheme.Background.warmBloom, .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 520
            )

            RadialGradient(
                colors: [.clear, AppTheme.Background.vignette],
                center: .center,
                startRadius: 240,
                endRadius: 960
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
