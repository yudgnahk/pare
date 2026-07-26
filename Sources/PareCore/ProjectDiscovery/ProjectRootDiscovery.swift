import Foundation

/// Discovers project root directories by running an NSMetadataQuery Spotlight search
/// for well-known signal files (.git, Package.swift, Cargo.toml, etc.) under the user's
/// home directory.
///
/// Discovered roots are persisted to ~/Library/Application Support/Pare/project-roots.json.
/// All discovered roots are included by default; users can exclude individual roots or add
/// paths that Spotlight missed.
///
/// Thread-safety: actor-isolated. Call from any context.
public actor ProjectRootDiscovery {
    public static let shared = ProjectRootDiscovery()

    // knownRoots: path → confirmed (true) or excluded (false)
    private var knownRoots: [String: Bool] = [:]
    private var manualRoots: [String] = []
    private var lastDiscoveredAt: Date?
    private let storeURL: URL

    public init(storeURL: URL? = nil) {
        let defaultURL: URL = {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            return appSupport.appendingPathComponent("Pare/project-roots.json")
        }()
        let resolvedURL = storeURL ?? defaultURL
        self.storeURL = resolvedURL

        // Load persisted state synchronously during init.
        // `loadFromDisk` only reads from disk — no actor-isolated mutable state is mutated
        // by anyone else at this point (actor is not yet accessible externally).
        if let data = try? Data(contentsOf: resolvedURL),
           let decoded = try? JSONDecoder().decode(ProjectRootsStore.self, from: data) {
            knownRoots = [:]
            for path in decoded.confirmed { knownRoots[path] = true }
            for path in decoded.excluded  { knownRoots[path] = false }
            manualRoots = decoded.manual
            lastDiscoveredAt = decoded.lastDiscoveredAt
        }
    }

    // MARK: - Public API

    /// All roots that are active (auto-discovered + confirmed, plus manual additions).
    public func confirmedRoots() -> [URL] {
        let auto = knownRoots.filter { $0.value }.map { URL(fileURLWithPath: $0.key) }
        let manual = manualRoots.map { URL(fileURLWithPath: $0) }
        return (auto + manual).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// All discovered roots paired with their confirmed state (for UI display).
    public var allDiscoveredRoots: [(url: URL, confirmed: Bool)] {
        knownRoots
            .filter { FileManager.default.fileExists(atPath: $0.key) }
            .map { (URL(fileURLWithPath: $0.key), $0.value) }
            .sorted { $0.url.path < $1.url.path }
    }

    /// Manual additions (separate from discovered roots).
    public var manualAdditions: [URL] {
        manualRoots
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// When the last Spotlight scan completed (nil = never run).
    public var discoveryDate: Date? { lastDiscoveredAt }

    /// Run Spotlight discovery if it has never been run before.
    public func discoverIfNeeded() async {
        guard lastDiscoveredAt == nil else { return }
        _ = await discover()
    }

    /// Run Spotlight query, deduplicate results, merge into the known-roots set,
    /// and return the full list of newly-discovered candidate roots.
    @discardableResult
    public func discover() async -> [URL] {
        let hits = await SpotlightQueryRunner.run()
        let roots = Self.deduplicate(hits)

        for root in roots {
            if knownRoots[root.path] == nil {
                knownRoots[root.path] = true  // new root defaults to confirmed
            }
        }
        // Prune roots that no longer exist on disk.
        knownRoots = knownRoots.filter { FileManager.default.fileExists(atPath: $0.key) }

        lastDiscoveredAt = Date()
        saveToDisk()
        return roots
    }

    public func confirm(_ url: URL) {
        knownRoots[url.path] = true
        saveToDisk()
    }

    public func exclude(_ url: URL) {
        knownRoots[url.path] = false
        saveToDisk()
    }

    public func addManual(_ url: URL) {
        let path = url.path
        guard !manualRoots.contains(path) else { return }
        manualRoots.append(path)
        saveToDisk()
    }

    public func removeManual(_ url: URL) {
        manualRoots.removeAll { $0 == url.path }
        saveToDisk()
    }

    // MARK: - Deduplication (internal but exposed for tests)

    /// Converts Spotlight hits to project roots, filters excluded path components,
    /// and collapses submodule / monorepo nesting.
    static func deduplicate(_ hits: [URL]) -> [URL] {
        // 1. Resolve each hit to its project root.
        var rootPaths = Set<String>()
        for hit in hits {
            let parent = hit.deletingLastPathComponent()
            rootPaths.insert(parent.path)
        }

        // 2. Filter paths containing excluded path components.
        let excluded = ["/Library/", "/System/", "/node_modules/", "/vendor/",
                        "/venv/", "/.venv/", "/.Trash/", "/site-packages/",
                        "/.Trash", "/Applications/"]
        let filtered = rootPaths.filter { path in
            !excluded.contains { path.contains($0) }
        }

        // 3. Sort by depth ascending (shallowest first).
        var sorted = filtered.sorted { a, b in
            a.components(separatedBy: "/").count < b.components(separatedBy: "/").count
        }
        sorted = Array(Set(sorted)).sorted {
            $0.components(separatedBy: "/").count < $1.components(separatedBy: "/").count
                || ($0.components(separatedBy: "/").count == $1.components(separatedBy: "/").count && $0 < $1)
        }

        // 4. Submodule deduplication: discard any root nested within another root
        //    by ≤ 3 path components (treat deeper nesting as independent projects).
        var result: [String] = []
        for candidate in sorted {
            let candidateDepth = candidate.components(separatedBy: "/").count
            let isCollapsible = result.contains { parent in
                guard candidate.hasPrefix(parent + "/") else { return false }
                let parentDepth = parent.components(separatedBy: "/").count
                return candidateDepth - parentDepth <= 3
            }
            if !isCollapsible {
                result.append(candidate)
            }
        }

        return result.map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let store = ProjectRootsStore(
            confirmed: knownRoots.filter { $0.value  }.map(\.key).sorted(),
            excluded:  knownRoots.filter { !$0.value }.map(\.key).sorted(),
            manual: manualRoots,
            lastDiscoveredAt: lastDiscoveredAt
        )
        let dir = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(store).write(to: storeURL)
    }
}

// MARK: - Spotlight Query Runner

/// Bridges NSMetadataQuery (requires a RunLoop) to async/await.
/// Always runs on the main queue.
///
/// Lifetime: the runner must stay alive until `finish()` runs. Observer and timeout
/// callbacks capture `self` strongly so the instance is not deallocated mid-query
/// (a previous `[weak self]` pattern leaked the async continuation and hung scans forever).
private final class SpotlightQueryRunner: NSObject, @unchecked Sendable {
    private let query = NSMetadataQuery()
    private var completion: (([URL]) -> Void)?
    private var observer: NSObjectProtocol?
    private var finished = false
    /// Keeps `self` alive from `start` until `finish` even if local refs drop.
    private var retainUntilFinished: SpotlightQueryRunner?

    private static let signalNames = [
        ".git", "Package.swift", "Cargo.toml", "go.mod",
        "pyproject.toml", "setup.py", "Gemfile", "pom.xml", "build.gradle",
    ]

    /// Maximum time to wait for Spotlight before completing with whatever results we have.
    private static let timeoutSeconds: TimeInterval = 10

    static func run() async -> [URL] {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let runner = SpotlightQueryRunner()
                runner.start { urls in
                    continuation.resume(returning: urls)
                }
            }
        }
    }

    private func start(completion: @escaping ([URL]) -> Void) {
        self.completion = completion
        // Self-retain until finish() so strong/weak callback mix cannot drop us early.
        retainUntilFinished = self

        let predicates = Self.signalNames.map { name in
            NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, name)
        }
        query.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        query.searchScopes = [NSMetadataQueryUserHomeScope]

        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [self] _ in
            self.finish()
        }

        query.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeoutSeconds) { [self] in
            self.finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        query.stop()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }

        let items = (0..<query.resultCount).compactMap { query.result(at: $0) as? NSMetadataItem }
        let urls: [URL] = items.compactMap { item in
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            return URL(fileURLWithPath: path)
        }
        completion?(urls)
        completion = nil
        retainUntilFinished = nil
    }
}
