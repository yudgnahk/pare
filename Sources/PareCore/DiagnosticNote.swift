import Foundation

/// One short line per explain-only diagnostic, with every deleted-files holder folded into a single note.
public struct DiagnosticNote: Identifiable, Sendable, Equatable {
    public let id: String
    public let headline: String
    public let action: String?
    /// The full reasons, for a tooltip.
    public let detail: String

    /// Holders named in the folded note's action before "+N".
    static let maxNamedHolders = 4

    public static func notes(from findings: [ScanFinding]) -> [DiagnosticNote] {
        let diagnostics = findings.filter { $0.category == .diagnostics }
        let holders = diagnostics.filter { holderCommand(of: $0) != nil }
        var notes: [DiagnosticNote] = []
        var holdersAdded = false
        for finding in diagnostics {
            guard holderCommand(of: finding) != nil else {
                notes.append(note(for: finding))
                continue
            }
            if !holdersAdded {
                notes.append(holders.count == 1 ? note(for: finding) : foldedHolderNote(for: holders))
                holdersAdded = true
            }
        }
        return notes
    }

    /// The text before " — " is the fact; what follows repeats the action or lists extra holders.
    private static func note(for finding: ScanFinding) -> DiagnosticNote {
        let headline = finding.reason.components(separatedBy: " — ").first ?? finding.reason
        return DiagnosticNote(id: finding.path, headline: headline, action: action(of: finding), detail: finding.reason)
    }

    private static func foldedHolderNote(for holders: [ScanFinding]) -> DiagnosticNote {
        let commands = holders.compactMap(holderCommand(of:))
        let named = commands.prefix(maxNamedHolders).joined(separator: ", ")
        let rest = commands.count > maxNamedHolders ? " +\(commands.count - maxNamedHolders)" : ""
        let total = ByteCountFormatter.string(fromByteCount: holders.reduce(0) { $0 + $1.sizeBytes }, countStyle: .file)
        return DiagnosticNote(
            id: "deleted-files-holders",
            headline: "\(total) held by deleted files in \(commands.count) apps",
            action: "Restart \(named)\(rest) to reclaim it",
            detail: holders.map(\.reason).joined(separator: "\n")
        )
    }

    private static func holderCommand(of finding: ScanFinding) -> String? {
        finding.annotations.lazy.compactMap { annotation -> String? in
            if case .deletedFilesHolder(let command) = annotation { return command }
            return nil
        }.first
    }

    private static func action(of finding: ScanFinding) -> String? {
        finding.annotations.lazy.compactMap { annotation -> String? in
            if case .explainOnly(let action) = annotation { return action }
            return nil
        }.first
    }
}
