import Foundation
import PareCore

@MainActor
final class ExclusionListViewModel: ObservableObject {
    @Published private(set) var entries: [ExclusionEntry] = []
    /// Non-nil when a store operation failed (R0.9 — no silent failures).
    @Published var errorMessage: String?

    private let store: ExclusionStore

    init(store: ExclusionStore = .shared) {
        self.store = store
        load()
    }

    func load() {
        do {
            entries = try store.load().entries
            errorMessage = nil
        } catch {
            entries = []
            errorMessage = "Could not load exclusions: \(error.localizedDescription)"
        }
    }

    func remove(id: UUID) {
        do {
            try store.removeEntry(id: id)
            entries.removeAll { $0.id == id }
            errorMessage = nil
        } catch {
            // Keep the entry visible — the persisted store still contains it.
            errorMessage = "Could not remove exclusion: \(error.localizedDescription)"
        }
    }
}
