import XCTest
@testable import PareCore

/// Dependency folders of inactive projects: `.review` only, lockfile required, activity from project markers.
final class ProjectDependencyReclaimTests: XCTestCase {

    private var root: URL!
    private let now = Date()
    private let day: TimeInterval = 24 * 60 * 60

    override func setUpWithError() throws {
        // Canonical `/private/var/…` spelling, as the engine sees it.
        root = ScanPolicy.canonicalPathURL(FileManager.default.temporaryDirectory)
            .appending(path: "pare_deps_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Pressure tiers

    func testPressureTierBoundaries() {
        let gb: Int64 = 1_000_000_000
        let cases: [(name: String, free: Int64, total: Int64, expected: DiskPressureTier)] = [
            ("plenty", 100 * gb, 245 * gb, .comfortable),
            ("exactly 15% and over 25 GB", 45 * gb, 300 * gb, .comfortable),
            ("under 15%", 30 * gb, 245 * gb, .low),
            ("under 25 GB but 24%", 24 * gb, 100 * gb, .low),
            ("under 5%", 11 * gb, 245 * gb, .critical),
            ("under 10 GB but 9%", 9 * gb, 100 * gb, .critical),
            ("unknown capacity is the strictest tier", 0, 0, .comfortable),
        ]
        for c in cases {
            XCTAssertEqual(ScanPolicy.diskPressureTier(freeBytes: c.free, totalBytes: c.total), c.expected, c.name)
        }
    }

    func testPressureTierFromAVolumeReading() {
        let gb: Int64 = 1_000_000_000
        let cases: [(name: String, reading: VolumeFreeSpace?, expected: DiskPressureTier)] = [
            ("unreadable volume", nil, .comfortable),
            ("no total capacity", VolumeFreeSpace(importantUsageBytes: 1 * gb, availableBytes: 1 * gb), .comfortable),
            ("Finder's figure wins", VolumeFreeSpace(importantUsageBytes: 100 * gb, availableBytes: 5 * gb, totalBytes: 245 * gb),
             .comfortable),
            ("available when Finder's is missing", VolumeFreeSpace(importantUsageBytes: nil, availableBytes: 5 * gb, totalBytes: 245 * gb),
             .critical),
        ]
        for testCase in cases {
            XCTAssertEqual(DiskPressure.tier(for: testCase.reading), testCase.expected, testCase.name)
        }
        for tier in DiskPressureTier.allCases {
            XCTAssertEqual(DiskPressure.current(volume: root, freeSpace: FixedVolumeFreeSpace.tier(tier)), tier)
        }
    }

    func testInactivityThresholdPerTierNeverUnder72Hours() {
        XCTAssertEqual(ScanPolicy.projectDependencyInactivitySeconds(for: .comfortable), 14 * day)
        XCTAssertEqual(ScanPolicy.projectDependencyInactivitySeconds(for: .low), 7 * day)
        XCTAssertEqual(ScanPolicy.projectDependencyInactivitySeconds(for: .critical), 3 * day)
        for tier in DiskPressureTier.allCases {
            XCTAssertGreaterThanOrEqual(ScanPolicy.projectDependencyInactivitySeconds(for: tier), 72 * 60 * 60)
        }
    }

    // MARK: - Project activity

    func testActivityIgnoresTheDependencyFolderOwnDate() throws {
        let project = try makeProject("old-project", lockfile: "package-lock.json", inactiveDays: 30)
        let deps = project.appending(path: "node_modules")
        try setAge(deps, days: 0)

        let activity = try XCTUnwrap(ScanPolicy.projectActivityDate(projectRoot: project))
        XCTAssertEqual(now.timeIntervalSince(activity) / day, 30, accuracy: 0.01)

        let fresh = try makeProject("fresh-manifest", lockfile: "package-lock.json", inactiveDays: 30)
        try setAge(fresh.appending(path: "node_modules"), days: 400)
        try setAge(fresh.appending(path: "package.json"), days: 1)
        let freshActivity = try XCTUnwrap(ScanPolicy.projectActivityDate(projectRoot: fresh))
        XCTAssertEqual(now.timeIntervalSince(freshActivity) / day, 1, accuracy: 0.01)
    }

    /// Trap: a non-git project edited daily deep under `src/` must not look idle from its top-level dates.
    func testActivitySeesNestedEditsButNotDependencyOrBuildFolders() throws {
        let project = try makeProject("deep-edit", lockfile: "package-lock.json", inactiveDays: 30)
        try makeFile(project.appending(path: "build/out.js"), ageDays: 0)
        try makeFile(project.appending(path: ".next/cache/x"), ageDays: 0)
        try makeFile(project.appending(path: "node_modules/pkg/index.js"), ageDays: 0)
        try backdateTopLevel(of: project, days: 30)

        let idle = try XCTUnwrap(ScanPolicy.projectActivityDate(projectRoot: project))
        XCTAssertEqual(now.timeIntervalSince(idle) / day, 30, accuracy: 0.01, "dependency and build output never count")

        try makeFile(project.appending(path: "src/components/Button.tsx"), ageDays: 1)
        try setAge(project.appending(path: "src/components"), days: 30)
        try setAge(project.appending(path: "src"), days: 30)
        let edited = try XCTUnwrap(ScanPolicy.projectActivityDate(projectRoot: project))
        XCTAssertEqual(now.timeIntervalSince(edited) / day, 1, accuracy: 0.01)
        XCTAssertFalse(isReclaimable(project.appending(path: "node_modules"), tier: .critical))
    }

    func testActivityWalkOutOfBudgetCountsAsActive() throws {
        let project = try makeProject("huge", lockfile: "package-lock.json", inactiveDays: 30)
        for index in 0..<10 {
            try makeFile(project.appending(path: "data/file-\(index).txt"), ageDays: 30)
        }

        XCTAssertNotNil(ScanPolicy.projectActivityDate(projectRoot: project))
        XCTAssertNil(ScanPolicy.projectActivityDate(projectRoot: project, entryBudget: 5), "entry budget")
        XCTAssertNil(ScanPolicy.projectActivityDate(projectRoot: project, timeBudget: 0), "time budget")
    }

    func testActivityUsesGitIndexAndLog() throws {
        for marker in ["index", "logs/HEAD"] {
            let project = try makeProject("git-\(marker.replacingOccurrences(of: "/", with: "-"))",
                                          lockfile: "pnpm-lock.yaml", inactiveDays: 30, git: true)
            try setAge(project.appending(path: ".git/\(marker)"), days: 1)

            let activity = try XCTUnwrap(ScanPolicy.projectActivityDate(projectRoot: project))
            XCTAssertEqual(now.timeIntervalSince(activity) / day, 1, accuracy: 0.01, marker)
        }
    }

    /// Trap: in a git worktree `.git` is a file; activity must follow `gitdir:` to the worktree's index.
    func testWorktreeFollowsGitdirToItsIndex() throws {
        let main = try makeProject("main", lockfile: "pnpm-lock.yaml", inactiveDays: 30, git: true)
        let worktreeGitDir = main.appending(path: ".git/worktrees/feature")
        try makeFile(worktreeGitDir.appending(path: "index"), ageDays: 1)
        let worktree = try makeProject("main-wt/feature", lockfile: "pnpm-lock.yaml", inactiveDays: 30)
        try write("gitdir: \(worktreeGitDir.path)\n", to: worktree.appending(path: ".git"), ageDays: 30)

        let activity = try XCTUnwrap(ScanPolicy.projectActivityDate(projectRoot: worktree))
        XCTAssertEqual(now.timeIntervalSince(activity) / day, 1, accuracy: 0.01)
        XCTAssertFalse(isReclaimable(worktree.appending(path: "node_modules"), tier: .critical))
    }

    /// Trap: a nested project with no `.git` of its own uses the enclosing repo's markers.
    func testNestedProjectUsesEnclosingRepository() throws {
        let mono = try makeProject("mono", lockfile: "bun.lock", inactiveDays: 30, git: true)
        let nested = try makeProject("mono/tools/py-inspect", lockfile: "uv.lock", inactiveDays: 30,
                                     dependency: ".venv")
        try backdateTopLevel(of: mono, days: 30)
        let venv = nested.appending(path: ".venv")

        XCTAssertTrue(isReclaimable(venv, tier: .comfortable, roots: [mono]))

        try setAge(mono.appending(path: ".git/index"), days: 1)
        XCTAssertFalse(isReclaimable(venv, tier: .critical, roots: [mono]),
                       "an active enclosing repo keeps its nested projects")
    }

    // MARK: - Restore evidence

    func testLockfileIsRequired() throws {
        let manifestOnly = try makeProject("manifest-only", lockfile: nil, inactiveDays: 30)
        XCTAssertFalse(isReclaimable(manifestOnly.appending(path: "node_modules"), tier: .critical))

        let locked = try makeProject("locked", lockfile: "yarn.lock", inactiveDays: 30)
        XCTAssertTrue(isReclaimable(locked.appending(path: "node_modules"), tier: .critical))
    }

    func testLockfileMustMatchTheDependencyKind() throws {
        let project = try makeProject("wrong-kind", lockfile: "Gemfile.lock", inactiveDays: 30)
        XCTAssertFalse(isReclaimable(project.appending(path: "node_modules"), tier: .critical))
    }

    /// Trap: a bundled runtime's `lib/node_modules` has no lockfile next to it.
    func testBundledRuntimeIsNeverReclaimable() throws {
        let runner = try makeProject("actions-runner", lockfile: nil, inactiveDays: 30)
        let bundled = runner.appending(path: "externals/node20/lib/node_modules")
        try makeFile(bundled.appending(path: "npm/package.json"), ageDays: 30)
        try backdateTopLevel(of: runner, days: 30)

        XCTAssertFalse(isReclaimable(bundled, tier: .critical, roots: [runner]))
    }

    /// Trap: a pnpm workspace member's `node_modules` has no lockfile of its own; only the root's is offered.
    func testWorkspaceMemberIsNotOfferedSeparately() throws {
        let workspace = try makeProject("workspace", lockfile: "pnpm-lock.yaml", inactiveDays: 30)
        let member = workspace.appending(path: "apps/web")
        try makeFile(member.appending(path: "package.json"), ageDays: 30)
        try makeFile(member.appending(path: "node_modules/.modules.yaml"), ageDays: 30)
        try backdateTopLevel(of: workspace, days: 30)

        XCTAssertTrue(isReclaimable(workspace.appending(path: "node_modules"), tier: .critical, roots: [workspace]))
        XCTAssertFalse(isReclaimable(member.appending(path: "node_modules"), tier: .critical, roots: [workspace]))
    }

    func testOutsideConfirmedRootsIsNeverReclaimable() throws {
        let project = try makeProject("unregistered", lockfile: "package-lock.json", inactiveDays: 30)
        XCTAssertFalse(isReclaimable(project.appending(path: "node_modules"), tier: .critical, roots: []))
    }

    func testOnlyDependencyNamesQualify() throws {
        let project = try makeProject("named", lockfile: "package-lock.json", inactiveDays: 30, dependency: "vendor")
        XCTAssertFalse(isReclaimable(project.appending(path: "vendor"), tier: .critical))
    }

    func testTierDecidesHowLongAProjectMustBeIdle() throws {
        let project = try makeProject("five-days", lockfile: "package-lock.json", inactiveDays: 5)
        let deps = project.appending(path: "node_modules")
        XCTAssertTrue(isReclaimable(deps, tier: .critical))
        XCTAssertFalse(isReclaimable(deps, tier: .low))
        XCTAssertFalse(isReclaimable(deps, tier: .comfortable))

        let recent = try makeProject("two-days", lockfile: "package-lock.json", inactiveDays: 2)
        XCTAssertFalse(isReclaimable(recent.appending(path: "node_modules"), tier: .critical),
                       "nothing touched within 72 hours, at any tier")
    }

    func testRestoreCommandPerLockfile() {
        let cases: [(String, String)] = [
            ("pnpm-lock.yaml", "pnpm install"), ("yarn.lock", "yarn install"), ("bun.lock", "bun install"),
            ("bun.lockb", "bun install"), ("package-lock.json", "npm ci"), ("uv.lock", "uv sync"),
            ("poetry.lock", "poetry install"), ("Pipfile.lock", "pipenv install"), ("Gemfile.lock", "bundle install"),
        ]
        for (lockfile, command) in cases {
            XCTAssertEqual(ScanPolicy.projectDependencyRestoreCommand(lockfile: lockfile), command, lockfile)
        }
    }

    // MARK: - Rule

    func testRuleOffersInactiveDependencyAsReviewWithReason() async throws {
        let project = try makeProject("idle", lockfile: "pnpm-lock.yaml", inactiveDays: 5, payloadBytes: 2_000_000)

        let critical = await scan(roots: [root], tier: .critical)
        XCTAssertEqual(critical.map(\.path), [project.appending(path: "node_modules").path])
        let finding = try XCTUnwrap(critical.first)
        XCTAssertEqual(finding.riskLevel, .review)
        XCTAssertEqual(finding.category, .projectArtifacts)
        XCTAssertTrue(finding.reason.contains("Inactive 5 days"), finding.reason)
        XCTAssertTrue(finding.reason.contains("3-day"), finding.reason)
        XCTAssertTrue(finding.reason.contains("pnpm install"), finding.reason)

        let comfortable = await scan(roots: [root], tier: .comfortable)
        XCTAssertTrue(comfortable.isEmpty)
    }

    /// Trap: test fixtures (`testdata/…/node_modules`) are tiny; the size floor drops them.
    func testRuleSkipsTinyFixtures() async throws {
        let fixtureProject = try makeProject("tool/testdata/node-app", lockfile: "package-lock.json",
                                             inactiveDays: 30, payloadBytes: 10)
        try backdateTopLevel(of: root.appending(path: "tool"), days: 30)

        let findings = await scan(roots: [root.appending(path: "tool")], tier: .critical)
        XCTAssertFalse(findings.contains { $0.path.hasPrefix(fixtureProject.path) })
    }

    func testRuleNeverReportsSafe() async throws {
        _ = try makeProject("a", lockfile: "uv.lock", inactiveDays: 40, dependency: ".venv", payloadBytes: 2_000_000)
        _ = try makeProject("b", lockfile: "Gemfile.lock", inactiveDays: 40, dependency: ".bundle", payloadBytes: 2_000_000)

        let findings = await scan(roots: [root], tier: .comfortable)
        XCTAssertEqual(findings.count, 2)
        XCTAssertTrue(findings.allSatisfy { $0.riskLevel == .review })
    }

    /// Trap: a manual root can reach app data or a bundled runtime; neither is a project.
    func testLibraryAndAppBundlePathsAreNeverReclaimable() throws {
        let appData = try makeProject("Library/Application Support/Tool/app", lockfile: "package-lock.json", inactiveDays: 30)
        let bundled = try makeProject("Tools.app/Contents/Resources/app", lockfile: "package-lock.json", inactiveDays: 30)
        let lowercase = try makeProject("library/app", lockfile: "package-lock.json", inactiveDays: 30)
        let plain = try makeProject("code/app", lockfile: "package-lock.json", inactiveDays: 30)

        for project in [appData, bundled, lowercase] {
            XCTAssertTrue(ScanPolicy.isInsideLibraryOrAppBundle(project.appending(path: "node_modules")), project.path)
            XCTAssertFalse(isReclaimable(project.appending(path: "node_modules"), tier: .critical), project.path)
        }
        XCTAssertFalse(ScanPolicy.isInsideLibraryOrAppBundle(plain.appending(path: "node_modules")))
        XCTAssertTrue(isReclaimable(plain.appending(path: "node_modules"), tier: .critical))
    }

    func testRuleWalkStopsAtItsEntryBudgetAndSaysSo() async throws {
        _ = try makeProject("budget/a", lockfile: "package-lock.json", inactiveDays: 30, payloadBytes: 2_000_000)

        let full = await scanResult(roots: [root], tier: .critical)
        XCTAssertEqual(full.findings.count, 1)
        XCTAssertNil(full.incompleteMessage)

        let cut = await scanResult(roots: [root], tier: .critical, entryBudget: 1)
        XCTAssertTrue(cut.findings.isEmpty)
        XCTAssertNotNil(cut.incompleteMessage)
    }

    func testRuleFlagsADeadlineCutSizeAsALowerBound() async throws {
        let project = try makeProject("slow", lockfile: "package-lock.json", inactiveDays: 30, payloadBytes: 2_000_000)
        let expired = DirectorySizeIndex(budgetSeconds: 0, now: { Date(timeIntervalSinceReferenceDate: 0) })

        let findings = await scanResult(roots: [root], tier: .critical, sizeIndex: expired).findings

        let finding = try XCTUnwrap(findings.first { $0.path == project.appending(path: "node_modules").path })
        XCTAssertFalse(finding.isSizeComplete)
    }

    // MARK: - Cleanup re-verification

    func testEngineRecheckAtCleanupTime() async throws {
        let project = try makeProject("engine", lockfile: "package-lock.json", inactiveDays: 5, payloadBytes: 2_000_000)
        let deps = project.appending(path: "node_modules")
        try setAge(deps, days: 0)
        let finding = ScanFinding(category: .projectArtifacts, riskLevel: .review, reason: "test", path: deps.path,
                                  sizeBytes: 2_000_000, lastUsed: nil, confidence: 0.8)

        let quick = try await engine(tier: .critical).quickClean(findings: [finding], profileName: "test", dryRun: true)
        XCTAssertTrue(quick.succeeded.isEmpty, "never part of Quick Clean")

        let selected = try await engine(tier: .critical).clean(findings: [finding], profileName: "test", dryRun: true)
        XCTAssertEqual(selected.succeeded.map(\.originalPath), [deps.path],
                       "a freshly installed folder in an idle project still qualifies")

        let calmer = try await engine(tier: .comfortable).clean(findings: [finding], profileName: "test", dryRun: true)
        XCTAssertTrue(calmer.succeeded.isEmpty, "the tier is re-read at cleanup time")

        try setAge(project.appending(path: "package-lock.json"), days: 0)
        let touched = try await engine(tier: .critical).clean(findings: [finding], profileName: "test", dryRun: true)
        XCTAssertTrue(touched.succeeded.isEmpty, "a project touched since the scan is skipped")
    }

    /// Trap: a `/temp/` path is low-impact and a dependency finding may carry any category; neither skips the gate.
    func testDependencyGateIsMandatoryUnderAllowListedPaths() async throws {
        let busy = try makeProject("temp/busy", lockfile: "package-lock.json", inactiveDays: 1)
        let idle = try makeProject("temp/idle", lockfile: "package-lock.json", inactiveDays: 30)
        try backdateTopLevel(of: root.appending(path: "temp"), days: 30)
        let busyDeps = busy.appending(path: "node_modules")
        let idleDeps = idle.appending(path: "node_modules")
        XCTAssertTrue(ScanPolicy.isLowImpactPath(busyDeps), "fixture must sit on an allow-listed path")

        for category in [ScanCategory.projectArtifacts, .userCaches] {
            let findings = [busyDeps, idleDeps].map {
                ScanFinding(category: category, riskLevel: .review, reason: "test", path: $0.path,
                            sizeBytes: 1024, lastUsed: nil, confidence: 0.8)
            }
            let result = try await engine(tier: .critical).clean(findings: findings, profileName: "test", dryRun: true)
            XCTAssertEqual(result.succeeded.map(\.originalPath), [idleDeps.path], "\(category)")
            XCTAssertEqual(result.skipped.map(\.path), [busyDeps.path], "\(category)")
        }
    }

    /// A tracked or unignored `node_modules` may be vendored on purpose; only ignored or repo-less folders pass.
    func testEngineRequiresGitEvidenceForDependencyFolders() async throws {
        let project = try makeProject("vendored", lockfile: "package-lock.json", inactiveDays: 30)
        let deps = project.appending(path: "node_modules")
        let finding = ScanFinding(category: .projectArtifacts, riskLevel: .review, reason: "test", path: deps.path,
                                  sizeBytes: 1024, lastUsed: nil, confidence: 0.8)
        let cases: [(status: GitArtifactStatus?, allowed: Bool)] = [
            (.ignoredUntracked, true), (.notInRepository, true),
            (.notIgnored, false), (.containsTrackedFiles, false), (.failed, false), (.gitUnavailable, false), (nil, false),
        ]
        for testCase in cases {
            let inspector = StubGitInspector(status: testCase.status)
            let result = try await engine(tier: .critical, gitInspector: inspector)
                .clean(findings: [finding], profileName: "test", dryRun: true)

            XCTAssertEqual(inspector.calls, [[deps.path]], "\(String(describing: testCase.status))")
            XCTAssertEqual(result.succeeded.count, testCase.allowed ? 1 : 0, "\(String(describing: testCase.status))")
            XCTAssertEqual(ScanPolicy.gitEvidenceAllows(dependency: deps, status: testCase.status), testCase.allowed)
            if !testCase.allowed {
                guard case .some(.notGitIgnored) = result.skipped.first?.error else {
                    return XCTFail("expected .notGitIgnored for \(String(describing: testCase.status))")
                }
            }
        }
    }

    func testEngineSkipsWhenAProcessRunsInsideTheProject() async throws {
        let project = try makeProject("served", lockfile: "uv.lock", inactiveDays: 30, dependency: ".venv")
        let venv = project.appending(path: ".venv")
        let finding = ScanFinding(category: .projectArtifacts, riskLevel: .review, reason: "test", path: venv.path,
                                  sizeBytes: 1024, lastUsed: nil, confidence: 0.8)
        let serving = OpenFileSnapshot(lsofFieldOutput: "p77\ncmcp-server\nfcwd\nn\(project.path)\n")

        let result = try await engine(tier: .critical, openFiles: CountingSnapshotProvider(snapshot: serving))
            .clean(findings: [finding], profileName: "test", dryRun: true)

        XCTAssertTrue(result.succeeded.isEmpty)
        guard case .some(.inUse(_, let holder)) = result.skipped.first?.error else {
            return XCTFail("expected .inUse, got \(String(describing: result.skipped.first?.error))")
        }
        XCTAssertEqual(holder, "mcp-server (pid 77)")
    }

    /// Without an open-file snapshot a running dev server is invisible, so dependency folders are held back.
    func testEngineRefusesDependencyFoldersWhenTheOpenFileCheckIsUnavailable() async throws {
        let project = try makeProject("unknown-use", lockfile: "yarn.lock", inactiveDays: 30)
        let deps = project.appending(path: "node_modules")
        let finding = ScanFinding(category: .projectArtifacts, riskLevel: .review, reason: "test", path: deps.path,
                                  sizeBytes: 1024, lastUsed: nil, confidence: 0.8)

        let result = try await engine(tier: .critical, openFiles: CountingSnapshotProvider(snapshot: nil))
            .clean(findings: [finding], profileName: "test", dryRun: true)

        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertTrue(result.inUseCheckUnavailable)
        guard case .some(.inUse(_, let holder)) = result.skipped.first?.error else {
            return XCTFail("expected .inUse, got \(String(describing: result.skipped.first?.error))")
        }
        XCTAssertEqual(holder, InUseGate.unavailableProjectHolder)
    }

    // MARK: - Helpers

    private func isReclaimable(_ url: URL, tier: DiskPressureTier, roots: [URL]? = nil) -> Bool {
        ScanPolicy.isReclaimableProjectDependency(
            url,
            registeredRootPaths: (roots ?? [root]).map(\.path),
            tier: tier,
            now: now
        )
    }

    private func scan(roots: [URL], tier: DiskPressureTier) async -> [ScanFinding] {
        await scanResult(roots: roots, tier: tier).findings
    }

    private func scanResult(
        roots: [URL],
        tier: DiskPressureTier,
        entryBudget: Int = ProjectDependenciesRule.defaultEntryBudget,
        sizeIndex: DirectorySizeIndex = DirectorySizeIndex()
    ) async -> ScanRuleResult {
        let rule = ProjectDependenciesRule(
            rootsProvider: { roots }, diskPressure: { tier }, now: { [now] in now }, entryBudget: entryBudget
        )
        let env = ScanEnvironment(homeDirectory: root.appending(path: "home"), sizeIndex: sizeIndex)
        return (try? await rule.customScanResult(environment: env)) ?? ScanRuleResult(findings: [])
    }

    private func engine(
        tier: DiskPressureTier,
        openFiles: any OpenFileSnapshotProviding = CountingSnapshotProvider(snapshot: .nothingOpen),
        gitInspector: any GitArtifactInspecting = StubGitInspector(status: .notInRepository)
    ) -> CleanupEngine {
        let rootPath: String = root.path
        return CleanupEngineFixture.make(
            store: CleanupTransactionStore(directory: root.appending(path: "store-\(UUID().uuidString)")),
            projectRootsProvider: { [rootPath] },
            exclusionsProvider: { .empty },
            now: { [now] in now },
            gitInspector: gitInspector,
            openFiles: openFiles,
            freeSpace: FixedVolumeFreeSpace.tier(tier)
        )
    }

    /// A project with a manifest, an optional lockfile and one dependency folder, every top-level entry aged.
    @discardableResult
    private func makeProject(
        _ relative: String,
        lockfile: String?,
        inactiveDays: Double,
        git: Bool = false,
        dependency: String = "node_modules",
        payloadBytes: Int = 1024
    ) throws -> URL {
        let project = root.appending(path: relative)
        let manifest = [".venv": "pyproject.toml", "venv": "pyproject.toml", ".bundle": "Gemfile"][dependency]
            ?? "package.json"
        try makeFile(project.appending(path: manifest), ageDays: inactiveDays)
        try makeFile(project.appending(path: "src/main.txt"), ageDays: inactiveDays)
        if let lockfile { try makeFile(project.appending(path: lockfile), ageDays: inactiveDays) }
        try write(String(repeating: "x", count: payloadBytes), to: project.appending(path: "\(dependency)/payload.bin"),
                  ageDays: inactiveDays)
        if git {
            try makeFile(project.appending(path: ".git/index"), ageDays: inactiveDays)
            try makeFile(project.appending(path: ".git/logs/HEAD"), ageDays: inactiveDays)
        }
        try backdateTopLevel(of: project, days: inactiveDays)
        return project
    }

    private func backdateTopLevel(of directory: URL, days: Double) throws {
        for entry in try FileManager.default.contentsOfDirectory(atPath: directory.path) where entry != ".git" {
            try setAge(directory.appending(path: entry), days: days)
        }
    }

    private func makeFile(_ url: URL, ageDays: Double) throws {
        try write("x", to: url, ageDays: ageDays)
    }

    private func write(_ text: String, to url: URL, ageDays: Double) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try setAge(url, days: ageDays)
    }

    private func setAge(_ url: URL, days: Double) throws {
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-days * day)],
                                              ofItemAtPath: url.path)
    }
}
