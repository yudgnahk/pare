import SwiftUI
import PareCore

/// Results hero: disk ring with the reclaimable share, counting total, category bar, and scan controls.
struct ScanSummaryHero: View {
    @ObservedObject var viewModel: ScanDashboardViewModel
    @ObservedObject var volume: VolumeUsageModel
    let onManageExclusions: () -> Void
    let onManageProjectPaths: () -> Void

    @Environment(\.pareDisplayScale) private var scale

    private var reclaimableShareOfDisk: Double {
        volume.usage?.fraction(of: viewModel.totalReclaimableBytes) ?? 0
    }

    var body: some View {
        GlassCard(padding: scale.space(AppTheme.Spacing.xl), cornerRadius: AppTheme.Radius.hero) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: scale.space(AppTheme.Spacing.xl)) {
                    ring
                    summary
                    Spacer(minLength: 0)
                    controls
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    HStack(spacing: AppTheme.Spacing.lg) {
                        ring
                        summary
                    }
                    controls
                }
            }
        }
        .background(heroGlow)
    }

    private var ring: some View {
        DiskUsageRing(
            usedFraction: volume.usage?.usedFraction ?? 0,
            reclaimableFraction: reclaimableShareOfDisk,
            diameter: scale.space(AppTheme.Control.summaryRing),
            lineWidth: scale.space(12)
        ) {
            VStack(spacing: 0) {
                Text(percentText)
                    .font(scale.font(22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.warmText)
                Text("of disk")
                    .font(scale.font(11, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percentText) of the disk is reclaimable")
    }

    private var percentText: String {
        let percent = reclaimableShareOfDisk * 100
        return percent > 0 && percent < 1 ? "<1%" : "\(Int(percent.rounded()))%"
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(scale.eyebrow)
                .tracking(1.1)
                .foregroundStyle(viewModel.isScanning ? AppTheme.accentText : AppTheme.textTertiary)
                .lineLimit(1)

            CountingBytesText(bytes: viewModel.totalReclaimableBytes, font: scale.display)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("\(viewModel.isTotalSizePartial ? "or more " : "")ready to reclaim across \(viewModel.summaries.count) \(viewModel.summaries.count == 1 ? "category" : "categories")")
                .font(scale.body)
                .foregroundStyle(AppTheme.textSecondary)

            if let growth = viewModel.growthSinceLastScan {
                Text(growth)
                    .font(scale.body)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            CategoryShareBar(summaries: viewModel.summaries, formatBytes: viewModel.formattedBytes)
                .padding(.top, 6)
                .frame(maxWidth: 520)
        }
        .frame(minWidth: 280, alignment: .leading)
    }

    private var eyebrow: String {
        if viewModel.isScanning { return "RESCANNING…" }
        guard let date = viewModel.lastScanDate else { return "SCAN RESULTS" }
        let duration = viewModel.lastScanDuration.map { String(format: " · %.1fs", $0) } ?? ""
        return "SCANNED \(viewModel.formattedDate(date).uppercased())\(duration)"
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if viewModel.isScanning {
                ProgressView().controlSize(.small)
                SecondaryActionButton(title: "Cancel", systemImage: "xmark") { viewModel.cancelScan() }
            } else {
                SecondaryActionButton(title: "Rescan", systemImage: "sparkles", role: .accent) {
                    viewModel.runScan()
                }
                .help("Scan again using cached metadata where possible")
            }
            moreMenu
        }
        .fixedSize()
    }

    private var moreMenu: some View {
        Menu {
            Button {
                viewModel.runScan(forceRescan: true)
            } label: {
                Label("Force Full Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isScanning)
            Divider()
            Button(action: onManageExclusions) {
                Label("Excluded Paths…", systemImage: "eye.slash")
            }
            Button(action: onManageProjectPaths) {
                Label("Project Scan Paths…", systemImage: "folder.badge.plus")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(scale.font(14, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: scale.space(AppTheme.Control.secondaryHeight), height: scale.space(AppTheme.Control.secondaryHeight))
                .background(AppTheme.Fill.hover, in: Circle())
                .overlay(Circle().strokeBorder(AppTheme.Hairline.strong, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More scan options")
    }

    private var heroGlow: some View {
        RadialGradient(
            colors: [AppTheme.warm.opacity(0.14), .clear],
            center: .topLeading,
            startRadius: 10,
            endRadius: 360
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
        .allowsHitTesting(false)
    }
}
