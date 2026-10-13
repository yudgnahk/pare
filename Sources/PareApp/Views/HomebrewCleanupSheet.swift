import SwiftUI
import PareCore

/// Previews `brew cleanup -n`, then runs `brew cleanup` after an explicit confirmation.
@MainActor
final class HomebrewCleanupModel: ObservableObject {
    enum Phase: Equatable {
        case previewing
        case ready(BrewCleanupPreview)
        case nothingToClean
        case failed(String)
        case running
        case finished(String)
    }

    @Published private(set) var phase: Phase = .previewing
    @Published private(set) var log: [String] = []

    private let action: BrewCleanupAction

    init(action: BrewCleanupAction = BrewCleanupAction()) {
        self.action = action
    }

    func loadPreview() async {
        phase = .previewing
        do {
            let preview = try await action.preview()
            phase = preview.isEmpty ? .nothingToClean : .ready(preview)
        } catch {
            phase = .failed("Could not preview Homebrew cleanup: \(error.localizedDescription)")
        }
    }

    /// Called only from the confirmation dialog.
    func cleanUp() async {
        phase = .running
        log = []
        do {
            let actedOn = try await action.run(confirmed: true) { [weak self] line in
                Task { @MainActor in self?.log.append(line) }
            }
            phase = .finished("Homebrew cleanup finished — about \(ScanReportPresenter.formatBytes(actedOn.totalBytes)) freed.")
        } catch BrewCleanupError.nothingToClean {
            phase = .nothingToClean
        } catch {
            phase = .failed("Homebrew cleanup failed: \(error.localizedDescription)")
        }
    }
}

struct HomebrewCleanupSheet: View {
    @StateObject var model: HomebrewCleanupModel
    let onDone: () -> Void
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Old Versions & Downloads")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("`brew cleanup` removes outdated versions and cached downloads Homebrew no longer needs, using its default age for downloads.")
                .font(.callout)
                .foregroundStyle(AppTheme.textSecondary)
            content
                .frame(minHeight: 180, maxHeight: 320)
            footer
        }
        .padding(20)
        .frame(width: 560)
        .task { await model.loadPreview() }
        .confirmationDialog("Clean up with Homebrew?", isPresented: $confirming) {
            Button("Clean Up", role: .destructive) { Task { await model.cleanUp() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if case .ready(let preview) = model.phase {
                Text("Homebrew will delete \(preview.items.count) item(s), about \(ScanReportPresenter.formatBytes(preview.totalBytes)). Homebrew deletes them directly; they do not go to the Trash.")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .previewing:
            ProgressView("Asking Homebrew what it would remove…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let preview):
            List(preview.items, id: \.path) { item in
                HStack {
                    Text(item.path).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(ScanReportPresenter.formatBytes(item.bytes)).font(.caption).foregroundStyle(AppTheme.textSecondary)
                }
            }
        case .nothingToClean:
            message("Homebrew has nothing to clean up.", color: AppTheme.textSecondary)
        case .failed(let text):
            message(text, color: AppTheme.warning)
        case .running, .finished:
            ScrollView {
                Text(model.log.joined(separator: "\n"))
                    .font(.caption.monospaced())
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var footer: some View {
        HStack {
            if case .ready(let preview) = model.phase {
                Text("Total: about \(ScanReportPresenter.formatBytes(preview.totalBytes))")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            } else if case .finished(let summary) = model.phase {
                Text(summary).font(.callout).foregroundStyle(AppTheme.accent)
            }
            Spacer()
            SecondaryActionButton(title: model.phase == .running ? "Running…" : "Done", isEnabled: model.phase != .running) {
                onDone()
            }
            if case .ready = model.phase {
                PrimaryActionButton(title: "Clean Up with Homebrew", systemImage: "sparkles", style: .compact, tint: .review) {
                    confirming = true
                }
            }
        }
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text).font(.callout).foregroundStyle(color).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
struct HomebrewCleanupSheet_Previews: PreviewProvider {
    static var previews: some View {
        HomebrewCleanupSheet(model: HomebrewCleanupModel(), onDone: {})
    }
}
#endif
