import Foundation
import PareCore

/// Which cleanup confirmation sheet is pending. One value replaces the three
/// `@Published Bool` sheet flags (quick / deep / selected).
enum PendingCleanup: String, Identifiable, Equatable {
    case quick
    case deep
    case selected

    var id: String { rawValue }
}

/// Drives the cleanup lifecycle (confirm → clean → done/undo) against
/// `CleanupEngine`. One `perform` body replaces the three near-identical
/// `confirm*Clean` implementations.
@MainActor
final class CleanupCoordinator: ObservableObject {
    enum CleanupState: Equatable {
        case idle
        case confirming
        case cleaning
        case done(bytesFreed: Int64, skippedCount: Int)
        case undoing
        case undone(restoredCount: Int, failedCount: Int)
        case error(String)
    }

    /// Non-nil drives the confirmation sheet (`.sheet(item:)`).
    @Published var pending: PendingCleanup?
    @Published private(set) var state: CleanupState = .idle
    @Published private(set) var transactionSaveError: String?
    @Published private(set) var lastResult: CleanupResult?

    /// Run after every cleanup or undo; each screen sharing this coordinator registers one.
    private var completionHandlers: [() -> Void] = []

    /// Most recent transaction, used to offer undo.
    private var lastTransaction: CleanupTransaction?
    private let engine: CleanupEngine

    /// Engine is injectable so tests can pass one backed by a temp-directory store.
    init(engine: CleanupEngine = CleanupEngine()) {
        self.engine = engine
    }

    var isCleaning: Bool {
        if case .cleaning = state { return true }
        return false
    }

    var isUndoing: Bool {
        if case .undoing = state { return true }
        return false
    }

    var canUndo: Bool {
        if let tx = lastTransaction, !tx.isDryRun, !tx.items.isEmpty { return true }
        return false
    }

    func addCompletionHandler(_ handler: @escaping () -> Void) {
        completionHandlers = completionHandlers + [handler]
    }

    // MARK: - Lifecycle

    func request(_ kind: PendingCleanup) {
        guard !isCleaning, !isUndoing else { return }
        pending = kind
        state = .confirming
    }

    func cancelPending() {
        pending = nil
        if state == .confirming {
            state = .idle
        }
    }

    /// Runs the pending cleanup with the findings the owner resolved for it.
    func confirm(_ kind: PendingCleanup, findings: [ScanFinding]) {
        guard !isCleaning, !isUndoing else { return }
        pending = nil
        state = .cleaning
        lastResult = nil
        transactionSaveError = nil

        Task(priority: .userInitiated) {
            do {
                let result: CleanupResult
                switch kind {
                case .quick:
                    result = try await engine.quickClean(findings: findings, profileName: "all")
                case .deep:
                    result = try await engine.deepClean(
                        findings: findings,
                        profileName: "all",
                        confirmed: true
                    )
                case .selected:
                    result = try await engine.clean(findings: findings, profileName: "all")
                }
                lastTransaction = result.transaction
                lastResult = result
                transactionSaveError = result.transactionSaveError
                state = .done(
                    bytesFreed: result.totalBytesFreed,
                    skippedCount: result.skipped.count
                )
                notifyCompletion()
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func undoLastCleanup() {
        guard !isCleaning, !isUndoing, let tx = lastTransaction, !tx.isDryRun else { return }
        state = .undoing

        Task(priority: .userInitiated) {
            let (restored, failed) = await engine.restore(transaction: tx)
            lastTransaction = failed.isEmpty ? nil : tx
            // Undo honesty (R0.7): failed restores must never be presented as success.
            state = .undone(restoredCount: restored.count, failedCount: failed.count)
            notifyCompletion()
        }
    }

    func dismissResult() {
        state = .idle
    }

    #if DEBUG
    /// Lets the snapshot renderer show result states without touching the filesystem.
    func applySnapshotState(_ snapshot: CleanupState) {
        state = snapshot
    }
    #endif

    private func notifyCompletion() {
        completionHandlers.forEach { $0() }
    }
}
