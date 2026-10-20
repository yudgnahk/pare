import XCTest
@testable import PareCore

/// One short line and at most one button per diagnostic; deleted-files holders fold into one note
/// that names apps and leaves macOS processes to a restart.
final class DiagnosticNoteTests: XCTestCase {

    private static func size(_ megabytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: megabytes * 1_000_000, countStyle: .file)
    }

    private static func holder(_ command: String, mb: Int64, pids: [Int32], system: Bool = false, app: String? = nil) -> ScanFinding {
        let name = app ?? command
        var annotations: [FindingAnnotation] = [
            .explainOnly(action: "Restart \(name) to reclaim the space"),
            .deletedFilesHolder(DeletedFilesHolder(command: command, displayName: name, pids: pids, isSystem: system)),
        ]
        if !system { annotations.append(.noteAction(.showProcesses(pids: pids))) }
        return ScanFinding(
            category: .diagnostics, riskLevel: .advanced,
            reason: "\(size(mb)) held by deleted files — restart \(name) to reclaim it (also held by A, B, C)",
            path: "/private/var/folders/\(command)", sizeBytes: mb * 1_000_000, lastUsed: nil, confidence: 0.9,
            annotations: annotations
        )
    }

    private static let loop = ScanFinding(
        category: .diagnostics, riskLevel: .advanced,
        reason: "sh.example.daemon restarted 33,782 times; last exit code 1 — check or remove the agent in /x.plist",
        path: "/x.plist", sizeBytes: 0, lastUsed: nil, confidence: 0.9,
        annotations: [.explainOnly(action: "Check or remove the agent in /x.plist"), .noteAction(.revealInFinder(path: "/x.plist"))]
    )

    func testHoldersFoldIntoOneNoteNamingAppsOnce() throws {
        let holders = [
            Self.holder("claude", mb: 250, pids: [10]),
            Self.holder("linkd", mb: 236, pids: [20], system: true),
            Self.holder("chronod", mb: 86, pids: [30], system: true),
            Self.holder("node", mb: 20, pids: [50]),
            Self.holder("Google Chrome Helper (Aperitif", mb: 13, pids: [40], app: "Google Chrome"),
            Self.holder("Google Chrome Helper", mb: 10, pids: [41], app: "Google Chrome"),
        ]
        let notes = DiagnosticNote.notes(from: [Self.loop] + holders)

        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].headline, "sh.example.daemon restarted 33,782 times; last exit code 1")
        XCTAssertEqual(notes[0].button, .revealInFinder(path: "/x.plist"))
        let folded = notes[1]
        XCTAssertEqual(folded.headline, "\(Self.size(615)) held by deleted files in 3 apps and macOS")
        XCTAssertEqual(folded.button, .showProcesses(pids: [10, 40, 41, 50]))
        XCTAssertEqual(folded.action, "Restart claude, node, Google Chrome to reclaim it; restart your Mac for the \(Self.size(322)) macOS holds")
        XCTAssertFalse(folded.headline.contains("linkd"), "system processes are not named")
        XCTAssertTrue(folded.detail.contains("also held by A, B, C"), "the long list stays in the tooltip")
    }

    func testOnlySystemHoldersMeanRestartTheMacWithoutAButton() throws {
        let notes = DiagnosticNote.notes(from: [
            Self.holder("linkd", mb: 236, pids: [20], system: true),
            Self.holder("chronod", mb: 86, pids: [30], system: true),
        ])

        let note = try XCTUnwrap(notes.first)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(note.headline, "\(Self.size(322)) held by deleted files in macOS")
        XCTAssertEqual(note.action, "Restart your Mac to reclaim it")
        XCTAssertNil(note.button)
    }

    func testSingleAppHolderKeepsItsOwnHeadline() {
        let notes = DiagnosticNote.notes(from: [Self.holder("claude", mb: 250, pids: [10])])

        XCTAssertEqual(notes.map(\.headline), ["\(Self.size(250)) held by deleted files"])
        XCTAssertEqual(notes.first?.button, .showProcesses(pids: [10]))
    }

    func testOneAppPlusMacOSStillFolds() {
        let notes = DiagnosticNote.notes(from: [
            Self.holder("claude", mb: 250, pids: [10]),
            Self.holder("linkd", mb: 50, pids: [20], system: true),
        ])

        XCTAssertEqual(notes.map(\.headline), ["\(Self.size(300)) held by deleted files in 1 app and macOS"])
        XCTAssertEqual(notes.first?.button, .showProcesses(pids: [10]))
    }

    func testNonDiagnosticsAreIgnoredAndNotesWithoutAnActionHaveNoButton() {
        let cache = ScanFinding(
            category: .userCaches, riskLevel: .safe, reason: "cache", path: "/c", sizeBytes: 1, lastUsed: nil, confidence: 1
        )
        let plain = ScanFinding(
            category: .diagnostics, riskLevel: .advanced, reason: "No dash here", path: "/p", sizeBytes: 0, lastUsed: nil, confidence: 1
        )
        let notes = DiagnosticNote.notes(from: [cache, plain])

        XCTAssertEqual(notes.map(\.headline), ["No dash here"])
        XCTAssertNil(notes.first?.action)
        XCTAssertNil(notes.first?.button)
    }
}
