import Foundation
import App BCore

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var transactions: [CleanupTransaction] = []
    @Published private(set) var restoringItemID: String? = nil
    @Published var errorMessage: String? = nil

    private let store: CleanupTransactionStore
    private let engine = CleanupEngine()

    init(store: CleanupTransactionStore = .shared) {
        self.store = store
        load()
    }

    func load() {
        transactions = (try? store.loadAll()) ?? []
    }

    func restoreItem(_ item: CleanupItem) async {
        restoringItemID = item.originalPath
        let success = await engine.restoreItem(item)
        restoringItemID = nil
        if !success {
            errorMessage = "Could not restore \((item.originalPath as NSString).lastPathComponent) — the Trash item may no longer exist."
        }
    }

    func clearAll() {
        try? store.deleteAll()
        transactions = []
    }

    func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
