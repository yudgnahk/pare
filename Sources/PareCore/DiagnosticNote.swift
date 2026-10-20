import Foundation

/// One short line and at most one button per explain-only diagnostic. Every deleted-files holder
/// folds into a single note that names apps and leaves macOS processes to a restart.
public struct DiagnosticNote: Identifiable, Sendable, Equatable {
    public let id: String
    public let headline: String
    /// What to do, shown as the button's tooltip.
    public let action: String?
    public let button: DiagnosticAction?
    /// The full reasons, for a tooltip on the headline.
    public let detail: String

    /// Apps named in the folded note's advice before "+N".
    static let maxNamedApps = 4

    public static func notes(from findings: [ScanFinding]) -> [DiagnosticNote] {
        let diagnostics = findings.filter { $0.category == .diagnostics }
        let holders = diagnostics.filter { holder(of: $0) != nil }
        var notes: [DiagnosticNote] = []
        var holdersAdded = false
        for finding in diagnostics {
            guard holder(of: finding) != nil else {
                notes.append(note(for: finding))
                continue
            }
            if !holdersAdded {
                notes.append(holderNote(for: holders))
                holdersAdded = true
            }
        }
        return notes
    }

    /// The text before " — " is the fact; what follows repeats the action or lists extra holders.
    private static func note(for finding: ScanFinding) -> DiagnosticNote {
        DiagnosticNote(
            id: finding.path,
            headline: finding.reason.components(separatedBy: " — ").first ?? finding.reason,
            action: explainOnlyAction(of: finding),
            button: button(of: finding),
            detail: finding.reason
        )
    }

    private static func holderNote(for findings: [ScanFinding]) -> DiagnosticNote {
        let pairs = findings.compactMap { finding in holder(of: finding).map { (finding, $0) } }
        let apps = pairs.filter { !$0.1.isSystem }
        let systemBytes = pairs.filter(\.1.isSystem).reduce(0) { $0 + $1.0.sizeBytes }
        if apps.count == 1, systemBytes == 0 { return note(for: apps[0].0) }

        let total = format(findings.reduce(0) { $0 + $1.sizeBytes })
        let detail = findings.map(\.reason).joined(separator: "\n")
        guard !apps.isEmpty else {
            return DiagnosticNote(
                id: "deleted-files-holders", headline: "\(total) held by deleted files in macOS",
                action: "Restart your Mac to reclaim it", button: nil, detail: detail
            )
        }
        let names = apps.map(\.1.displayName).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let named = names.prefix(maxNamedApps).joined(separator: ", ")
        let rest = names.count > maxNamedApps ? " +\(names.count - maxNamedApps)" : ""
        let appCount = names.count == 1 ? "1 app" : "\(names.count) apps"
        let macOS = systemBytes > 0 ? " and macOS" : ""
        let restart = systemBytes > 0 ? "; restart your Mac for the \(format(systemBytes)) macOS holds" : ""
        return DiagnosticNote(
            id: "deleted-files-holders",
            headline: "\(total) held by deleted files in \(appCount)\(macOS)",
            action: "Restart \(named)\(rest) to reclaim it\(restart)",
            button: .showProcesses(pids: Array(Set(apps.flatMap(\.1.pids))).sorted()),
            detail: detail
        )
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func holder(of finding: ScanFinding) -> DeletedFilesHolder? {
        finding.annotations.lazy.compactMap { annotation -> DeletedFilesHolder? in
            if case .deletedFilesHolder(let holder) = annotation { return holder }
            return nil
        }.first
    }

    private static func button(of finding: ScanFinding) -> DiagnosticAction? {
        finding.annotations.lazy.compactMap { annotation -> DiagnosticAction? in
            if case .noteAction(let action) = annotation { return action }
            return nil
        }.first
    }

    private static func explainOnlyAction(of finding: ScanFinding) -> String? {
        finding.annotations.lazy.compactMap { annotation -> String? in
            if case .explainOnly(let action) = annotation { return action }
            return nil
        }.first
    }
}
