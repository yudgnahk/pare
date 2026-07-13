import SwiftUI
import PareCore

struct MaintenanceView: View {
    @StateObject private var viewModel = MaintenanceViewModel()

    var body: some View {
        ZStack {
            AppBackgroundView()

            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    headerCard
                    actionCards
                }
                .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
                .padding(.vertical, AppTheme.Spacing.pageVertical)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { viewModel.onAppear() }
    }

    // MARK: - Header

    private var headerCard: some View {
        GlassCard {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Maintenance")
                        .font(AppTheme.TypeScale.heroTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("One-shot system actions — no file deletions")
                        .font(AppTheme.TypeScale.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(AppTheme.accent.opacity(0.7))
            }
        }
    }

    // MARK: - Action cards

    private var actionCards: some View {
        // Adaptive columns: 1 on compact 13–14", 2 on 15"+, 3 on wide desktops.
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: AppTheme.Breakpoint.cardMin), spacing: AppTheme.Spacing.lg)
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
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(iconColor.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: action.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                statusBadge
            }

            Spacer(minLength: 8)
            runButton
                .layoutPriority(1)
        }
    }

    // MARK: Description + meta

    private var descriptionRow: some View {
        Text(action.description)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 10))
            Text("≈ \(action.estimatedSeconds)s")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
        .padding(.top, 6)
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
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
        case .success:
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.success)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.review)
        }
    }

    // MARK: Run button

    private var runButton: some View {
        Button(action: { viewModel.runAction(action) }) {
            Group {
                if state == .running {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.textPrimary)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: state == .success ? "arrow.clockwise" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(runButtonColor.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(runButtonColor.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(state == .running)
        .foregroundStyle(runButtonColor)
        .help(state == .success ? "Run again" : "Run")
    }

    // MARK: Log view

    private var logView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { logExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Text("Output")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    Image(systemName: logExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
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
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(logLineColor(line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(10)
                    }
                    .frame(maxHeight: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.25))
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

    private var runButtonColor: Color {
        switch state {
        case .idle: return AppTheme.accent
        case .running: return AppTheme.textSecondary
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
