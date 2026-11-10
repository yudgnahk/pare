import PareCore
import SwiftUI

/// Lets the user confirm which go/uv/pnpm scans may run; nothing unconfirmed is ever launched.
struct DeveloperToolsCard: View {
    @Environment(\.pareDisplayScale) private var scale
    @ObservedObject var model: DeveloperToolsViewModel

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Developer tools", systemImage: "hammer")
                        .font(scale.font(14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Pare runs these only after you confirm them.")
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                ForEach(model.rows) { row in
                    toolRow(row)
                }
                if let error = model.errorMessage {
                    Text(error)
                        .font(scale.caption)
                        .foregroundStyle(AppTheme.warning)
                }
            }
        }
        .task { await model.refresh() }
    }

    private func toolRow(_ row: DeveloperToolsViewModel.Row) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(row.tool.executableName)
                .font(scale.font(13, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(status(row.state))
                    .font(scale.caption)
                    .foregroundStyle(statusColor(row.state))
                if let path = path(row.state) {
                    Text(path)
                        .font(scale.font(11))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                }
            }
            Spacer(minLength: 8)
            action(for: row)
        }
    }

    @ViewBuilder
    private func action(for row: DeveloperToolsViewModel.Row) -> some View {
        let isBusy = model.busyTool == row.tool
        switch row.state {
        case .confirmed:
            SecondaryActionButton(title: "Forget", isLoading: isBusy, isEnabled: model.busyTool == nil) {
                Task { await model.forget(row.tool) }
            }
        case .available(let path, _):
            SecondaryActionButton(title: "Confirm", isLoading: isBusy, role: .accent, isEnabled: model.busyTool == nil) {
                Task { await model.confirm(row.tool, path: path) }
            }
        case .rejected, .notFound:
            EmptyView()
        }
    }

    private func status(_ state: ToolTrustState) -> String {
        switch state {
        case .confirmed: return "Confirmed"
        case .available(_, let changed): return changed ? "Changed since you confirmed it" : "Not confirmed"
        case .rejected(_, let reason): return reason.message
        case .notFound: return "Not found"
        }
    }

    private func statusColor(_ state: ToolTrustState) -> Color {
        switch state {
        case .confirmed: return AppTheme.success
        case .available(_, let changed): return changed ? AppTheme.warning : AppTheme.textSecondary
        case .rejected: return AppTheme.warning
        case .notFound: return AppTheme.textTertiary
        }
    }

    private func path(_ state: ToolTrustState) -> String? {
        switch state {
        case .confirmed(let path), .available(let path, _), .rejected(let path, _): return path
        case .notFound: return nil
        }
    }
}

#if DEBUG
struct DeveloperToolsCard_Previews: PreviewProvider {
    static var previews: some View {
        DeveloperToolsCard(model: DeveloperToolsViewModel(registry: ConfirmedToolRegistry(store: NoConfirmedToolStore())))
            .padding()
            .frame(width: 560)
    }
}
#endif
