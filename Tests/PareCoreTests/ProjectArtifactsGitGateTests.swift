import XCTest
@testable import PareCore

/// `build`, `dist`, `target` and `coverage` are only reclaimable with git-ignore evidence; other names are not gated.
final class ProjectArtifactsGitGateTests: XCTestCase {

    private static let allStatuses: [GitArtifactStatus?] = [
        .ignoredUntracked, .notIgnored, .containsTrackedFiles,
        .notInRepository, .gitUnavailable, .failed, nil,
    ]

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - ScanPolicy.gitEvidenceAllows

    func testGitEvidenceTruthTable() {
        for status in Self.allStatuses {
            for name in ["build", "dist", "target", "coverage", "Build", "Coverage"] {
                let url = URL(fileURLWithPath: "/Users/u/Projects/app/\(name)")
                XCTAssertEqual(
                    ScanPolicy.gitEvidenceAllows(artifact: url, status: status),
                    status == .ignoredUntracked,
                    "\(name) with \(String(describing: status))"
                )
            }
            for name in [".cache", ".next", "__pycache__"] {
                let url = URL(fileURLWithPath: "/Users/u/Projects/app/\(name)")
                XCTAssertTrue(
                    ScanPolicy.gitEvidenceAllows(artifact: url, status: status),
                    "\(name) is not gated (\(String(describing: status)))"
                )
            }
        }
    }

    // MARK: - ProjectArtifactsRule

    func testGatedNamesReportedOnlyWhenIgnoredUntracked() async throws {
        try makeArtifacts(["build", "dist", "target", "coverage", ".cache"])

        for status in Self.allStatuses {
            let findings = await scan(with: StubGitInspector(status: status))
            let names = Set(findings.map { URL(fileURLWithPath: $0.path).lastPathComponent })

            let expected: Set<String> = status == .ignoredUntracked
                ? ["build", "dist", "target", "coverage", ".cache"]
                : [".cache"]
            XCTAssertEqual(names, expected, String(describing: status))
        }
    }

    func testRiskLevelsUnchangedForIgnoredOutputs() async throws {
        try makeArtifacts(["build", "dist", "target"])

        let findings = await scan(with: StubGitInspector(status: .ignoredUntracked))
        let risk = Dictionary(uniqueKeysWithValues: findings.map {
            (URL(fileURLWithPath: $0.path).lastPathComponent, $0.riskLevel)
        })

        XCTAssertEqual(risk, ["build": .review, "dist": .review, "target": .safe])
    }

    func testInspectorCalledOnceWithGatedCandidatesOnly() async throws {
        try makeArtifacts(["build", "dist", ".cache", "__pycache__"])
        let inspector = StubGitInspector(status: .ignoredUntracked)

        _ = await scan(with: inspector)

        XCTAssertEqual(inspector.calls.count, 1)
        let names = Set((inspector.calls.first ?? []).map { URL(fileURLWithPath: $0).lastPathComponent })
        XCTAssertEqual(names, ["build", "dist"])
    }

    // MARK: - Helpers

    private func makeArtifacts(_ names: [String]) throws {
        let old = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        for name in names {
            let dir = tmp.appending(path: "myapp/\(name)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 0xAB, count: 1024).write(to: dir.appending(path: "content.bin"))
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: dir.path)
        }
    }

    private func scan(with inspector: StubGitInspector) async -> [ScanFinding] {
        let storeURL = tmp.appending(path: "store-\(UUID().uuidString)/project-roots.json")
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let store = ProjectRootsStore(confirmed: [], excluded: [], manual: [tmp.appending(path: "myapp").path], lastDiscoveredAt: Date())
        try? JSONEncoder().encode(store).write(to: storeURL)
        let suiteName = "pare.tests.git-gate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let rule = ProjectArtifactsRule(
            discovery: ProjectRootDiscovery(storeURL: storeURL),
            pathStore: ProjectScanPathStore(defaults: defaults),
            gitInspector: inspector
        )
        return await rule.customScan(environment: ScanEnvironment.current()) ?? []
    }
}
