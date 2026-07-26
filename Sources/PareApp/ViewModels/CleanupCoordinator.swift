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
        case undone(restoredCount: Int)
        case error(String)
    }

    /// Non-nil drives the confirmation sheet (`.sheet(item:)`).
    @Published var pending: PendingCleanup?
    @Published private(set) var state: CleanupState = .idle

    /// Called after a cleanup or undo completes so the owner can rescan.
    var onCleanupCompleted: (() -> Void)?

    /// Most recent transaction, used to offer undo.
    private var lastTransaction: CleanupTransaction?
    private let engine = CleanupEngine()

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

    // MARK: - Lifecycle

    func request(_ kind: PendingCleanup) {
        pending = kind
        state = .confirming
    }

    func cancelPending() {
        pending = nil
        state = .idle
    }

    /// Runs the pending cleanup with the findings the owner resolved for it.
    func confirm(_ kind: PendingCleanup, findings: [ScanFinding]) {
        pending = nil
        state = .cleaning

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
                state = .done(
                    bytesFreed: result.totalBytesFreed,
                    skippedCount: result.skipped.count
                )
                // Re-run scan to refresh results after cleanup.
                onCleanupCompleted?()
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func undoLastCleanup() {
        guard let tx = lastTransaction, !tx.isDryRun else { return }
        state = .undoing

        Task(priority: .userInitiated) {
            let (restored, _) = await engine.restore(transaction: tx)
            lastTransaction = nil
            state = .undone(restoredCount: restored.count)
            onCleanupCompleted?()
        }
    }

    func dismissResult() {
        state = .idle
    }

    /// Fresh scan results supersede any stale done/error banner.
    func resetAfterScan() {
        state = .idle
    }
}
