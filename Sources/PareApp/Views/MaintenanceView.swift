import SwiftUI
import PareCore

struct MaintenanceView: View {
    @ObservedObject var viewModel: MaintenanceViewModel
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                destination: .maintenance,
                subtitle: "One-shot system actions. None of them delete your files."
            )
            ScrollView {
                actionCards
                    .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                    .padding(.top, AppTheme.Spacing.sm)
                    .padding(.bottom, AppTheme.Spacing.pageVertical)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { viewModel.onAppear() }
    }

    // MARK: - Action cards

    private var actionCards: some View {
        // Adaptive columns: 1 on compact 13–14", 2 on 15"+, 3 on wide desktops.
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: AppTheme.Breakpoint.cardMin), spacing: AppTheme.Spacing.lg, alignment: .top)
            ],
            spacing: AppTheme.Spacing.lg
        ) {
            ForEach(viewModel.visibleActions) { action in
                ActionCard(action: action, viewModel: viewModel)
            }
        }
    }
}

// MARK: - ActionCard

private struct ActionCard: View {
    let action: MaintenanceAction
    @ObservedObject var viewModel: MaintenanceViewModel
    @Environment(\.pareDisplayScale) private var scale

    @State private var logExpanded = false

    private var state: MaintenanceViewModel.ActionState { viewModel.state(for: action) }
    private var log: [String] { viewModel.log(for: action) }
    private var hasLog: Bool { !log.isEmpty }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                topRow
                descriptionRow
                metaRow
                if hasLog {
                    Divider().opacity(0.12).padding(.top, 14)
                    logView
                }
            }
        }
    }

    // MARK: Top row

    private var topRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: action.systemImage)
                .font(scale.font(17, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.14), in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .strokeBorder(iconColor.opacity(0.22), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(scale.font(14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                statusBadge
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: Description + meta

    private var descriptionRow: some View {
        Text(action.description)
            .font(scale.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(scale.font(11))
            Text("≈ \(action.estimatedSeconds)s")
                .font(scale.caption)
                .monospacedDigit()
            Spacer(minLength: 8)
            runButton
        }
        .foregroundStyle(AppTheme.textTertiary)
        .padding(.top, 12)
    }

    // MARK: Status badge

    @ViewBuilder
    private var statusBadge: some View {
        switch state {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 5) {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                Text("Running…")
            }
            .font(scale.font(11, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
        case .success:
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(scale.font(11, weight: .semibold))
                .foregroundStyle(AppTheme.success)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .font(scale.font(11, weight: .semibold))
                .foregroundStyle(AppTheme.review)
        }
    }

    // MARK: Run button

    private var runButton: some View {
        SecondaryActionButton(
            title: state == .running ? "Running…" : (state == .success ? "Run Again" : "Run"),
            systemImage: state == .success ? "arrow.clockwise" : "play.fill",
            isLoading: state == .running,
            role: .accent
        ) {
            viewModel.runAction(action)
        }
        .help(action.title)
    }

    // MARK: Log view

    private var logView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { logExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Text("Output")
                        .font(scale.font(11, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    Image(systemName: logExpanded ? "chevron.up" : "chevron.down")
                        .font(scale.font(9, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .onChange(of: log.count) { _ in
                if !logExpanded { logExpanded = true }
            }

            if logExpanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(scale.font(11, design: .monospaced))
                                    .foregroundStyle(logLineColor(line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(10)
                    }
                    .frame(maxHeight: 160)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                            .fill(AppTheme.Fill.subtle)
                    )
                    .onChange(of: log.count) { _ in
                        withAnimation { proxy.scrollTo("bottom") }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: Helpers

    private var iconColor: Color {
        switch state {
        case .idle: return AppTheme.accent
        case .running: return AppTheme.accent
        case .success: return AppTheme.success
        case .failed: return AppTheme.review
        }
    }


    private func logLineColor(_ line: String) -> Color {
        if line.hasPrefix("✓") || line.contains("done") || line.contains("complete") {
            return AppTheme.success
        } else if line.hasPrefix("✗") || line.hasPrefix("⚠") {
            return AppTheme.review
        } else if line.hasPrefix("→") {
            return AppTheme.accent
        }
        return AppTheme.textSecondary
    }
}
