import Foundation
import PareCore

/// One explain-only diagnostic as a display line; never selectable and never part of a reclaimable total.
struct DiagnosticLine: Identifiable, Equatable {
    let id: String
    let headline: String
    let action: String
    let sizeBytes: Int64

    /// Diagnostics with an explain-only action, largest first.
    static func lines(from findings: [ScanFinding]) -> [DiagnosticLine] {
        findings
            .compactMap(line(from:))
            .sorted { $0.sizeBytes != $1.sizeBytes ? $0.sizeBytes > $1.sizeBytes : $0.id < $1.id }
    }

    private static func line(from finding: ScanFinding) -> DiagnosticLine? {
        guard finding.category == .diagnostics else { return nil }
        let action = finding.annotations.lazy.compactMap { annotation -> String? in
            if case .explainOnly(let action) = annotation { return action }
            return nil
        }.first
        guard let action else { return nil }
        return DiagnosticLine(
            id: finding.path, headline: headline(from: finding.reason), action: action, sizeBytes: finding.sizeBytes
        )
    }

    /// Rule reasons read "what is wrong — what to do"; the action is shown separately.
    private static func headline(from reason: String) -> String {
        let head = reason.components(separatedBy: " — ").first ?? reason
        return head.hasSuffix(".") ? String(head.dropLast()) : head
    }
}
