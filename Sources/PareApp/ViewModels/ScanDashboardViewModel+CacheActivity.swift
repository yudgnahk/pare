import Foundation
import PareCore

// MARK: - Hot cache rows (confirmation copy)

extension ScanDashboardViewModel {
    var selectedHotCount: Int { selection.selectedHotCount }

    /// Hot rows Quick Clean (safe only) or Deep Clean (safe + review) leaves for their own checkbox.
    func heldOutHotCount(includeReview: Bool) -> Int {
        selection.hotPaths.filter { path in
            guard let risk = selection.riskLevel(for: path) else { return false }
            return risk == .safe || (includeReview && risk == .review)
        }.count
    }

    /// Shown when the user ticked rows that were written to recently.
    var hotSelectionNotice: String? {
        let count = selectedHotCount
        guard count > 0 else { return nil }
        let days = CacheActivityClassifier.defaultHotDays
        return "\(count) item\(count == 1 ? " was" : "s were") written to in the last \(days) days, "
            + "so \(count == 1 ? "its app" : "their apps") will download or rebuild \(count == 1 ? "it" : "them") again."
    }

    /// Shown on Quick/Deep Clean when hot rows are left out.
    func heldOutHotNotice(includeReview: Bool) -> String? {
        let count = heldOutHotCount(includeReview: includeReview)
        guard count > 0 else { return nil }
        let days = CacheActivityClassifier.defaultHotDays
        return "\(count) cache\(count == 1 ? "" : "s") written to in the last \(days) days "
            + "\(count == 1 ? "is" : "are") left out; tick \(count == 1 ? "it" : "them") and use Clean Selected to include \(count == 1 ? "it" : "them")."
    }
}
