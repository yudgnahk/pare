import XCTest
@testable import PareCore

/// The app shows one short line per diagnostic and folds every deleted-files holder into one note.
final class DiagnosticNoteTests: XCTestCase {

    private static func holder(_ command: String, mb: Int64, also: String = "") -> ScanFinding {
        let size = ByteCountFormatter.string(fromByteCount: mb * 1_000_000, countStyle: .file)
        return ScanFinding(
            category: .diagnostics, riskLevel: .advanced,
            reason: "\(size) held by deleted files — restart \(command) to reclaim it\(also)",
            path: "/private/var/folders/\(command)", sizeBytes: mb * 1_000_000, lastUsed: nil, confidence: 0.9,
            annotations: [.explainOnly(action: "Restart \(command) to reclaim the space"), .deletedFilesHolder(command: command)]
        )
    }

    private static let loop = ScanFinding(
        category: .diagnostics, riskLevel: .advanced,
        reason: "sh.example.daemon restarted 33,782 times; last exit code 1 — check or remove the agent in /x.plist",
        path: "/x.plist", sizeBytes: 0, lastUsed: nil, confidence: 0.9,
        annotations: [.explainOnly(action: "Check or remove the agent in /x.plist")]
    )

    func testHoldersFoldIntoOneNoteAtTheFirstHolder() throws {
        let holders = ["claude", "linkd", "chronod", "Siri AI", "corespotlightd", "Chrome Helper"].enumerated().map {
            Self.holder($1, mb: Int64(100 - $0 * 10), also: $0 == 1 ? " (also held by A, B, C)" : "")
        }
        let notes = DiagnosticNote.notes(from: [Self.loop] + holders)

        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].headline, "sh.example.daemon restarted 33,782 times; last exit code 1")
        XCTAssertEqual(notes[0].action, "Check or remove the agent in /x.plist")
        let folded = notes[1]
        let total = ByteCountFormatter.string(fromByteCount: 450_000_000, countStyle: .file)
        XCTAssertEqual(folded.headline, "\(total) held by deleted files in 6 apps")
        XCTAssertEqual(folded.action, "Restart claude, linkd, chronod, Siri AI +2 to reclaim it")
        XCTAssertTrue(folded.detail.contains("also held by A, B, C"), "the long list stays in the tooltip")
        XCTAssertFalse(folded.headline.contains("also held by"))
    }

    func testSingleHolderKeepsItsOwnHeadline() {
        let notes = DiagnosticNote.notes(from: [Self.holder("claude", mb: 250, also: " (also held by node)")])
        let size = ByteCountFormatter.string(fromByteCount: 250_000_000, countStyle: .file)

        XCTAssertEqual(notes.map(\.headline), ["\(size) held by deleted files"])
        XCTAssertEqual(notes.first?.action, "Restart claude to reclaim the space")
    }

    func testNonDiagnosticsAreIgnoredAndPlainReasonsPassThrough() {
        let cache = ScanFinding(
            category: .userCaches, riskLevel: .safe, reason: "cache", path: "/c", sizeBytes: 1, lastUsed: nil, confidence: 1
        )
        let plain = ScanFinding(
            category: .diagnostics, riskLevel: .advanced, reason: "No dash here", path: "/p", sizeBytes: 0, lastUsed: nil, confidence: 1
        )
        let notes = DiagnosticNote.notes(from: [cache, plain])

        XCTAssertEqual(notes.map(\.headline), ["No dash here"])
        XCTAssertNil(notes.first?.action)
    }
}
