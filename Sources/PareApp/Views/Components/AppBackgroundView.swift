import SwiftUI

struct AppBackgroundView: View {
    var body: some View {
        ZStack {
            AppTheme.pageGradient
                .ignoresSafeArea()

            // Teal bloom — top trailing
            RadialGradient(
                colors: [
                    AppTheme.Background.bloom,
                    .clear
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 480
            )
            .ignoresSafeArea()

            // Deep navy / success bloom — bottom leading
            RadialGradient(
                colors: [
                    AppTheme.accentDeep.opacity(0.28),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 40,
                endRadius: 420
            )
            .ignoresSafeArea()

            // Subtle vignette for depth — clear in light mode
            RadialGradient(
                colors: [
                    .clear,
                    AppTheme.Background.vignette
                ],
                center: .center,
                startRadius: 200,
                endRadius: 900
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}
