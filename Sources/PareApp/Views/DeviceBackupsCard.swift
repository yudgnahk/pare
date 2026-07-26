import SwiftUI
import PareCore

struct DeviceBackupsCard: View {
    @Environment(\.pareDisplayScale) private var scale
    @ObservedObject var viewModel: ScanDashboardViewModel
    @State private var isExpanded = true

    var body: some View {
        GlassCard {
            VStack(spacing: 0) {
                Button(action: { withAnimation(.spring(duration: 0.25)) { isExpanded.toggle() } }) {
                    HStack(spacing: 10) {
                        Image(systemName: "iphone.and.arrow.forward")
                            .font(scale.font(15, weight: .semibold))
                            .foregroundStyle(Color.indigo)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Device Backups")
                                .font(scale.font(14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(subtitle)
                                .font(scale.font(11, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(scale.font(10, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider().opacity(0.12).padding(.top, 12)
                    backupList
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
    }

    // MARK: Private

    private var subtitle: String {
        let findings = viewModel.deviceBackupFindings
        let total = findings.reduce(0) { $0 + $1.sizeBytes }
        let countStr = "\(findings.count) backup\(findings.count == 1 ? "" : "s")"
        return "\(countStr) · \(viewModel.formattedBytes(total)) reclaimable"
    }

    private var backupList: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.deviceBackupFindings) { finding in
                backupRow(finding)
            }
        }
        .padding(.top, 10)
    }

    private func backupRow(_ finding: ScanDashboardViewModel.FindingItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "iphone")
                .font(scale.font(14, weight: .medium))
                .foregroundStyle(Color.indigo.opacity(0.8))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(finding.reason)
                    .font(scale.font(12, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(viewModel.formattedBytes(finding.sizeBytes))
                        .font(scale.font(11, weight: .semibold))
                        .foregroundStyle(AppTheme.warning)

                    if let date = finding.lastUsed {
                        Text("·")
                            .foregroundStyle(AppTheme.textSecondary)
                        Text(viewModel.formattedDate(date))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .font(scale.font(11, weight: .medium))
            }

            Spacer(minLength: 8)

            Button("Show in Finder") {
                viewModel.revealInFinder(path: finding.path)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Color.indigo)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .fill(AppTheme.panelSecondary.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                        .strokeBorder(AppTheme.warning.opacity(0.15), lineWidth: 1)
                )
        )
    }
}
