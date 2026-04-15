import SwiftUI

struct AppBackgroundView: View {
    var body: some View {
        ZStack {
            AppTheme.pageGradient
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    AppTheme.accent.opacity(0.24),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 440
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    AppTheme.success.opacity(0.18),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 50,
                endRadius: 360
            )
            .ignoresSafeArea()
        }
    }
}
