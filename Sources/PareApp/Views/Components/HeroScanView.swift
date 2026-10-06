import AppKit
import SwiftUI

/// Smart Scan home: live disk ring around the scan orb, which becomes an honest progress ring while scanning.
struct HeroScanView: View {
    @ObservedObject var viewModel: ScanDashboardViewModel
    @ObservedObject var volume: VolumeUsageModel
    var onOpenSettings: (() -> Void)? = nil

    @Environment(\.pareDisplayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var ringDiameter: CGFloat { scale.space(AppTheme.Control.heroRing) }
    private var ringLine: CGFloat { scale.space(16) }

    private var progress: Double { viewModel.scanProgress }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: scale.space(AppTheme.Spacing.xl)) {
                    headlineBlock
                        .modifier(RevealOnAppear(appeared: appeared, index: 0))
                    ringStack
                        .modifier(RevealOnAppear(appeared: appeared, index: 1))
                    footerBlock
                        .modifier(RevealOnAppear(appeared: appeared, index: 2))
                }
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.vertical, scale.space(AppTheme.Spacing.xxl))
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { settingsButton }
        .onAppear {
            volume.refresh()
            MotionPolicy.perform(AppTheme.Motion.gentle, reduceMotion: reduceMotion) { appeared = true }
        }
    }

    // MARK: Headline

    private var headlineBlock: some View {
        VStack(spacing: 10) {
            Text(viewModel.isScanning ? "SMART SCAN IN PROGRESS" : "SMART SCAN")
                .font(scale.eyebrow)
                .tracking(1.1)
                .foregroundStyle(AppTheme.accentText)

            Text(headline)
                .font(scale.heroTitle)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .id(headline)
                .transition(.opacity)

            Text(subheadline)
                .font(scale.body)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .fixedSize(horizontal: false, vertical: true)
        }
        .motionAwareAnimation(AppTheme.Motion.standard, value: headline)
    }

    // MARK: Ring

    @ViewBuilder
    private var ringStack: some View {
        if viewModel.isScanning {
            ZStack {
                ScanProgressRing(fraction: progress, diameter: ringDiameter, lineWidth: ringLine)
                scanningCenter
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            DiskUsageRing(
                usedFraction: volume.usage?.usedFraction ?? 0,
                diameter: ringDiameter,
                lineWidth: ringLine
            ) {
                ScanOrbButton(
                    title: "Scan",
                    subtitle: viewModel.lastScanDate == nil ? nil : "Scan again",
                    diameter: scale.space(AppTheme.Control.heroOrb)
                ) {
                    viewModel.runScan()
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private var scanningCenter: some View {
        VStack(spacing: 4) {
            CountingPercentText(fraction: progress, font: scale.display)
            Text(viewModel.isFinalizingScan
                 ? "all checks done"
                 : "\(viewModel.scanRulesCompleted) of \(max(viewModel.scanRulesTotal, 1)) checks")
                .font(scale.caption)
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footerBlock: some View {
        if viewModel.isScanning {
            VStack(spacing: 14) {
                ScanStepChips(activeStep: viewModel.scanStep)
                if !viewModel.scanStepTitle.isEmpty, !viewModel.isFinalizingScan {
                    Text(viewModel.scanStepTitle)
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }
                SecondaryActionButton(title: "Cancel", systemImage: "xmark") {
                    viewModel.cancelScan()
                }
            }
        } else {
            VStack(spacing: 16) {
                diskLegend
                trustChips
                if viewModel.showFullDiskAccessBanner {
                    FullDiskAccessCard(
                        style: .fullDiskAccess,
                        onOpenSettings: { viewModel.openFullDiskAccessSettings() },
                        onDismiss: { viewModel.dismissFullDiskAccessBanner() },
                        onRescan: { viewModel.runScan(forceRescan: true) }
                    )
                    .frame(maxWidth: 560)
                }
            }
        }
    }

    @ViewBuilder
    private var diskLegend: some View {
        if let usage = volume.usage {
            HStack(spacing: 18) {
                LegendDot(color: AppTheme.accentBright, label: "used", value: viewModel.formattedBytes(usage.usedBytes))
                LegendDot(
                    color: isLowOnSpace(usage) ? AppTheme.warm : AppTheme.Fill.selected,
                    label: isLowOnSpace(usage) ? "available · running low" : "available",
                    value: viewModel.formattedBytes(usage.availableBytes)
                )
                Text(usage.name)
                    .font(scale.font(12, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private func isLowOnSpace(_ usage: VolumeUsage) -> Bool {
        usage.totalBytes > 0 && Double(usage.availableBytes) / Double(usage.totalBytes) < StorageMeter.lowSpaceThreshold
    }

    private var trustChips: some View {
        HStack(spacing: 8) {
            TrustChip(icon: "checkmark.shield.fill", text: "Risk-labelled findings")
            TrustChip(icon: "trash.fill", text: "Trash first, never erased")
            TrustChip(icon: "arrow.uturn.backward", text: "Undo last clean")
        }
    }

    @ViewBuilder
    private var settingsButton: some View {
        if let onOpenSettings, !viewModel.isScanning {
            IconActionButton(systemImage: "slider.horizontal.3", help: "Manage excluded paths", action: onOpenSettings)
                .padding(.top, AppTheme.Spacing.pageVertical)
                .padding(.trailing, AppTheme.Spacing.pageHorizontal)
        }
    }

    // MARK: Copy

    private var headline: String {
        guard viewModel.isScanning else {
            return viewModel.lastScanDate == nil ? "Let's make some room" : "Ready for another look"
        }
        if viewModel.isFinalizingScan { return ScanDashboardViewModel.finalizingTitle }
        switch viewModel.scanStep {
        case 1: return "Checking system caches…"
        case 2: return "Checking apps & browsers…"
        default: return "Checking developer tools…"
        }
    }

    private var subheadline: String {
        if viewModel.isFinalizingScan {
            return "Every check is done. Grouping findings by folder and app."
        }
        if viewModel.isScanning {
            return "Progress counts real checks, not a guess. Nothing is touched while scanning."
        }
        if let date = viewModel.lastScanDate {
            return "Last scan \(viewModel.formattedDate(date)). Pare labels every finding by risk, and anything you clean goes to the Trash first."
        }
        return "Pare finds caches, build leftovers and installers you can safely let go. Every finding is labelled by risk."
    }
}

/// Fade-and-rise entrance, staggered by index; instant under Reduce Motion.
struct RevealOnAppear: ViewModifier {
    let appeared: Bool
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .animation(MotionPolicy.animation(AppTheme.Motion.stagger(index), reduceMotion: reduceMotion), value: appeared)
    }
}
