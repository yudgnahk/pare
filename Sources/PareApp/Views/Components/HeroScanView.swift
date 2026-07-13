import SwiftUI

/// CleanMyMac-style calm home: SF Symbol hero + ring Scan CTA.
struct HeroScanView: View {
    @ObservedObject var viewModel: ScanDashboardViewModel
    var onOpenSettings: (() -> Void)? = nil

    @Environment(\.displayScale) private var scale
    @State private var appeared = false
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: scale.space(28)) {
                heroArt
                    .offset(y: floatOffset)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.92)
                    .animation(AppTheme.Motion.gentle, value: appeared)

                VStack(spacing: 10) {
                    Text(headline)
                        .font(scale.font(32, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(subheadline)
                        .font(scale.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                        .fixedSize(horizontal: false, vertical: true)

                    if let last = lastScanCaption {
                        Text(last)
                            .font(scale.micro)
                            .foregroundStyle(AppTheme.textTertiary)
                            .padding(.top, 4)
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(AppTheme.Motion.gentle.delay(0.08), value: appeared)

                VStack(spacing: 14) {
                    PrimaryRingButton(
                        title: viewModel.isScanning ? "…" : "Scan",
                        isLoading: viewModel.isScanning
                    ) {
                        viewModel.runScan()
                    }

                    if viewModel.isScanning {
                        SecondaryActionButton(title: "Cancel", systemImage: "xmark") {
                            viewModel.cancelScan()
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(AppTheme.Motion.gentle.delay(0.14), value: appeared)
            }

            Spacer(minLength: 20)

            HStack {
                Spacer()
                if let onOpenSettings {
                    Button(action: onOpenSettings) {
                        Label("Settings", systemImage: "gearshape")
                            .font(scale.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 28)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            appeared = true
            withAnimation(AppTheme.Motion.ringPulse) {
                floatOffset = -6
            }
        }
    }

    private var headline: String {
        if viewModel.isScanning { return "Scanning your Mac…" }
        return "Welcome to Pare"
    }

    private var subheadline: String {
        if viewModel.isScanning {
            return "Analyzing caches, build artifacts, and reclaimable space."
        }
        return "Find reclaimable space safely — with clear risk levels for every finding."
    }

    private var lastScanCaption: String? {
        guard !viewModel.isScanning, let date = viewModel.lastScanDate else { return nil }
        if let duration = viewModel.lastScanDuration {
            return "Last scan \(viewModel.formattedDate(date)) · \(String(format: "%.1fs", duration))"
        }
        return "Last scan \(viewModel.formattedDate(date))"
    }

    private var heroArt: some View {
        ZStack {
            Circle()
                .fill(AppTheme.heroGlow)
                .frame(width: scale.scaled(260), height: scale.scaled(260))

            // Soft decorative marks (SF Symbol composition — no custom assets)
            Image(systemName: "sparkle")
                .font(.system(size: scale.scaled(22), weight: .light))
                .foregroundStyle(AppTheme.accent.opacity(0.45))
                .offset(x: -90, y: -50)

            Image(systemName: "sparkle")
                .font(.system(size: scale.scaled(16), weight: .light))
                .foregroundStyle(AppTheme.success.opacity(0.4))
                .offset(x: 95, y: -30)

            Image(systemName: "sparkle")
                .font(.system(size: scale.scaled(14), weight: .light))
                .foregroundStyle(AppTheme.accent.opacity(0.35))
                .offset(x: 70, y: 70)

            ZStack {
                RoundedRectangle(cornerRadius: scale.scaled(28), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.panel.opacity(0.95),
                                AppTheme.accentDeep.opacity(0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: scale.scaled(140), height: scale.scaled(140))
                    .overlay(
                        RoundedRectangle(cornerRadius: scale.scaled(28), style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: AppTheme.accent.opacity(0.3), radius: 28, y: 12)

                Image(systemName: "internaldrive.fill")
                    .font(.system(size: scale.scaled(48), weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.success],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolRenderingMode(.hierarchical)

                Image(systemName: "leaf.fill")
                    .font(.system(size: scale.scaled(20), weight: .semibold))
                    .foregroundStyle(AppTheme.success)
                    .offset(x: 36, y: 36)
            }
        }
        .frame(height: scale.scaled(220))
        .accessibilityHidden(true)
    }
}
