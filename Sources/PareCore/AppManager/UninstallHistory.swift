import Foundation

/// Write-ahead undo record for one uninstall: saved before the first move and again after every move.
struct UninstallHistory {
    let id = UUID()
    private let timestamp = Date()
    private let profileName: String
    private let store: CleanupTransactionStore
    /// Last save failure; a later successful save clears it because each save holds every item so far.
    private(set) var saveError: String?

    init(appName: String, store: CleanupTransactionStore) {
        self.profileName = "Uninstall \(appName)"
        self.store = store
    }

    /// Writes the empty record; when this throws nothing may be moved.
    func begin() throws {
        try store.save(transaction([]))
    }

    mutating func record(_ items: [CleanupItem]) {
        do {
            try store.save(transaction(items))
            saveError = nil
        } catch {
            saveError = error.localizedDescription
            AppUninstaller.logger.error("Saving uninstall history failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops the placeholder when nothing was moved.
    func discard() {
        try? store.delete(id: id)
    }

    private func transaction(_ items: [CleanupItem]) -> CleanupTransaction {
        CleanupTransaction(id: id, timestamp: timestamp, profileName: profileName, isDryRun: false, items: items)
    }
}
