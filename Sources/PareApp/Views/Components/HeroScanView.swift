import AppKit
import SwiftUI

/// App-B-style calm home: SF Symbol hero + ring Scan CTA + 3-step progress.
struct HeroScanView: View {
    @ObservedObject var viewModel: ScanDashboardViewModel
    var onOpenSettings: (() -> Void)? = nil

    @Environment(\.pareDisplayScale) private var scale
    @State private var appeared = false
    @State private var floatOffset: CGFloat = 0

    private let steps: [(icon: String, label: String)] = [
        ("internaldrive.fill", "System"),
        ("globe", "Apps & browsers"),
        ("chevron.left.forwardslash.chevron.right", "Developer")
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            VStack(spacing: scale.space(24)) {
                heroArt
                    .offset(y: floatOffset)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.92)
                    .animation(AppTheme.Motion.gentle, value: appeared)

                VStack(spacing: 10) {
                    Text(headline)
                        .font(scale.heroTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(subheadline)
                        .font(scale.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                        .fixedSize(horizontal: false, vertical: true)

                    if viewModel.isScanning {
                        scanStepsBar
                            .padding(.top, 8)
                        if !viewModel.scanStepTitle.isEmpty {
                            Text(viewModel.scanStepTitle)
                                .font(scale.caption)
                                .foregroundStyle(AppTheme.textTertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        if viewModel.scanRulesTotal > 0 {
                            ProgressView(
                                value: Double(viewModel.scanRulesCompleted),
                                total: Double(max(viewModel.scanRulesTotal, 1))
                            )
                            .tint(AppTheme.accent)
                            .frame(maxWidth: 280)
                        }
                    } else if let last = lastScanCaption {
                        Text(last)
                            .font(scale.caption)
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

                    if viewModel.showFullDiskAccessBanner, !viewModel.isScanning {
                        FullDiskAccessCard(
                            style: .fullDiskAccess,
                            onOpenSettings: { viewModel.openFullDiskAccessSettings() },
                            onDismiss: { viewModel.dismissFullDiskAccessBanner() },
                            onRescan: { viewModel.runScan(forceRescan: true) }
                        )
                        // Wider than the headline (440) so Open Settings + Rescan + Dismiss
                        // fit on one row and the card uses less empty side margin.
                        .frame(maxWidth: 560)
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(AppTheme.Motion.gentle.delay(0.14), value: appeared)
            }

            Spacer(minLength: 16)

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
            // FDA re-probe lives on ScanDashboardView (survives hero → results).
            withAnimation(AppTheme.Motion.ringPulse) {
                floatOffset = -6
            }
        }
    }

    private var scanStepsBar: some View {
        HStack(spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let stepNumber = index + 1
                let active = viewModel.scanStep == stepNumber
                let done = viewModel.scanStep > stepNumber
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(done || active ? AppTheme.accent.opacity(0.2) : AppTheme.Fill.subtle)
                            .frame(width: 44, height: 44)
                        Image(systemName: step.icon)
                            .font(scale.font(16, weight: .semibold))
                            .foregroundStyle(done || active ? AppTheme.accent : AppTheme.textTertiary)
                            .scaleEffect(active && viewModel.isScanning ? 1.06 : 1)
                            .animation(
                                active && viewModel.isScanning
                                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                    : .default,
                                value: active
                            )
                    }
                    Text(step.label)
                        .font(scale.font(11, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? AppTheme.textPrimary : AppTheme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: 100)
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(done ? AppTheme.accent.opacity(0.5) : AppTheme.Fill.hover)
                        .frame(width: 24, height: 2)
                        .offset(y: -10)
                }
            }
        }
    }

    private var headline: String {
        if viewModel.isScanning {
            switch viewModel.scanStep {
            case 1: return "Scanning system…"
            case 2: return "Scanning apps & browsers…"
            default: return "Scanning developer tools…"
            }
        }
        return "Welcome to Pare"
    }

    private var subheadline: String {
        if viewModel.isScanning {
            return "Real progress by scan rules — not a fake percentage."
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
                .frame(width: scale.scaled(240), height: scale.scaled(240))

            Image(systemName: "sparkle")
                .font(scale.font(20, weight: .light))
                .foregroundStyle(AppTheme.accent.opacity(0.45))
                .offset(x: -90, y: -50)

            Image(systemName: "sparkle")
                .font(scale.font(14, weight: .light))
                .foregroundStyle(AppTheme.success.opacity(0.4))
                .offset(x: 95, y: -30)

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
                    .frame(width: scale.scaled(130), height: scale.scaled(130))
                    .overlay(
                        RoundedRectangle(cornerRadius: scale.scaled(28), style: .continuous)
                            .strokeBorder(AppTheme.Hairline.strong, lineWidth: 1)
                    )
                    .shadow(color: AppTheme.accent.opacity(0.3), radius: 28, y: 12)

                Image(systemName: activeHeroIcon)
                    .font(scale.font(44, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.success],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolRenderingMode(.hierarchical)
                    .id(activeHeroIcon)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .animation(AppTheme.Motion.standard, value: viewModel.scanStep)
            }
        }
        .frame(height: scale.scaled(200))
        .accessibilityHidden(true)
    }

    private var activeHeroIcon: String {
        guard viewModel.isScanning else { return "internaldrive.fill" }
        switch viewModel.scanStep {
        case 1: return "internaldrive.fill"
        case 2: return "globe"
        default: return "chevron.left.forwardslash.chevron.right"
        }
    }
}
