import Foundation
import App BCore

@MainActor
final class ExclusionListViewModel: ObservableObject {
    @Published private(set) var entries: [ExclusionEntry] = []

    private let store: ExclusionStore

    init(store: ExclusionStore = .shared) {
        self.store = store
        load()
    }

    func load() {
        entries = (try? store.load())?.entries ?? []
    }

    func remove(id: UUID) {
        try? store.removeEntry(id: id)
        entries.removeAll { $0.id == id }
    }
}
