import Foundation

/// Discovers project root directories by running an NSMetadataQuery Spotlight search
/// for well-known signal files (`ScanPolicy.projectDiscoverySignalNames`) under the user's
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
    private let spotlightSearch: @Sendable () async -> SpotlightSearchResult
    /// Whether the most recent `discover()` hit the Spotlight timeout, so its root list may be short.
    private(set) var lastDiscoveryTimedOut = false
    /// Set when init pruned roots that are now excluded from discovery; the next save persists it.
    private var needsSave = false
    private let now: @Sendable () -> Date
    /// Forces the next `discoverIfNeeded()` to search regardless of age (user-requested rescan).
    private var isStale = false
    /// Shared by overlapping callers so one Spotlight query serves them all.
    private var inFlight: Task<[URL], Never>?

    /// How long discovered roots are trusted before Spotlight is queried again.
    public static let refreshInterval: TimeInterval = 24 * 3600

    public init(storeURL: URL? = nil) {
        self.init(storeURL: storeURL, spotlightSearch: { await SpotlightQueryRunner.run() })
    }

    init(
        storeURL: URL?,
        spotlightSearch: @escaping @Sendable () async -> SpotlightSearchResult,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.spotlightSearch = spotlightSearch
        self.now = now
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
            let kept = knownRoots.filter { !Self.isExcludedRoot($0.key) }
            needsSave = kept.count != knownRoots.count
            knownRoots = kept
            manualRoots = decoded.manual
            lastDiscoveredAt = decoded.lastDiscoveredAt
        }
    }

    // MARK: - Public API

    /// All roots that are active (auto-discovered + confirmed, plus manual additions).
    public func confirmedRoots() -> [URL] {
        let auto = knownRoots
            .filter { $0.value && !Self.isExcludedRoot($0.key) }
            .map { URL(fileURLWithPath: $0.key) }
        let manual = manualRoots.map { URL(fileURLWithPath: $0) }
        return (auto + manual).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// All discovered roots paired with their confirmed state (for UI display).
    public var allDiscoveredRoots: [(url: URL, confirmed: Bool)] {
        knownRoots
            .filter { !Self.isExcludedRoot($0.key) && FileManager.default.fileExists(atPath: $0.key) }
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

    /// Runs Spotlight discovery when it never ran, is `refreshInterval` old, is dated in the future,
    /// or was marked stale. Returns whether a discovery ran (or was joined) during this call.
    @discardableResult
    public func discoverIfNeeded() async -> Bool {
        if needsSave { saveToDisk() }
        guard inFlight != nil || isDiscoveryDue else { return false }
        _ = await discover()
        return true
    }

    /// Makes the next `discoverIfNeeded()` query Spotlight even if the last discovery is recent.
    public func markStale() {
        isStale = true
    }

    private var isDiscoveryDue: Bool {
        guard let last = lastDiscoveredAt else { return true }
        let current = now()
        return isStale || last > current || current.timeIntervalSince(last) >= Self.refreshInterval
    }

    /// Run Spotlight query, deduplicate results, merge into the known-roots set,
    /// and return the full list of newly-discovered candidate roots.
    @discardableResult
    public func discover() async -> [URL] {
        if let inFlight { return await inFlight.value }
        let task = Task { await self.performDiscovery() }
        inFlight = task
        let roots = await task.value
        inFlight = nil
        return roots
    }

    private func performDiscovery() async -> [URL] {
        // Cleared before the search so a markStale() that lands mid-search still forces the next run.
        isStale = false
        let search = await spotlightSearch()
        lastDiscoveryTimedOut = search.timedOut
        let roots = Self.deduplicate(search.urls)

        for root in roots {
            if knownRoots[root.path] == nil {
                knownRoots[root.path] = true  // new root defaults to confirmed
            }
        }
        // Prune roots that no longer exist on disk.
        knownRoots = knownRoots.filter { FileManager.default.fileExists(atPath: $0.key) }

        // Advanced even after a timeout, so a machine without Spotlight is not re-queried every scan.
        lastDiscoveredAt = now()
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
        let rootPaths = Set(hits.map { projectRoot(forSignalHit: $0).path })

        // 2. Filter paths containing excluded path components (list lives in ScanPolicy — R1.4).
        let filtered = rootPaths.filter { path in
            !ScanPolicy.isExcludedFromProjectDiscovery(URL(fileURLWithPath: path))
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

    /// The hit's folder, or the folder holding an enclosing `.xcodeproj`/`.xcworkspace`
    /// (Xcode keeps `Package.resolved` several levels inside the bundle).
    static func projectRoot(forSignalHit hit: URL) -> URL {
        let components = hit.pathComponents
        let bundleIndex = components.dropLast().firstIndex { component in
            let lower = component.lowercased()
            return lower.hasSuffix(".xcodeproj") || lower.hasSuffix(".xcworkspace")
        }
        guard let bundleIndex else { return hit.deletingLastPathComponent() }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(components[..<bundleIndex])))
    }

    private static func isExcludedRoot(_ path: String) -> Bool {
        ScanPolicy.isExcludedFromProjectDiscovery(URL(fileURLWithPath: path))
    }

    // MARK: - Persistence

    private func saveToDisk() {
        needsSave = false
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

struct SpotlightSearchResult: Sendable {
    let urls: [URL]
    /// True when the timeout fired before Spotlight finished gathering.
    let timedOut: Bool
}

/// Bridges NSMetadataQuery (requires a RunLoop) to async/await.
/// Always runs on the main queue.
///
/// Lifetime: the runner must stay alive until `finish()` runs. Observer and timeout
/// callbacks capture `self` strongly so the instance is not deallocated mid-query
/// (a previous `[weak self]` pattern leaked the async continuation and hung scans forever).
///
/// Thread-safety: all mutable state is guarded by `lock`, making the
/// `@unchecked Sendable` claim sound. The locked `finished` flag guarantees the
/// completion runs exactly once even if the finish-gathering observer and the
/// timeout fire concurrently.
private final class SpotlightQueryRunner: NSObject, @unchecked Sendable {
    private let query = NSMetadataQuery()
    private let lock = NSLock()
    private var completion: ((SpotlightSearchResult) -> Void)?
    private var observer: NSObjectProtocol?
    private var finished = false
    /// Keeps `self` alive from `start` until `finish` even if local refs drop.
    private var retainUntilFinished: SpotlightQueryRunner?

    /// Maximum time to wait for Spotlight before completing with whatever results we have.
    private static let timeoutSeconds: TimeInterval = 10

    static func run() async -> SpotlightSearchResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let runner = SpotlightQueryRunner()
                runner.start { result in
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private func start(completion: @escaping (SpotlightSearchResult) -> Void) {
        lock.withLock {
            self.completion = completion
            // Self-retain until finish() so strong/weak callback mix cannot drop us early.
            self.retainUntilFinished = self
        }

        let predicates = ScanPolicy.projectDiscoverySignalNames.map { name in
            NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, name)
        }
        query.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        query.searchScopes = [NSMetadataQueryUserHomeScope]

        let observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [self] _ in
            self.finish(timedOut: false)
        }
        lock.withLock { self.observer = observer }

        query.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeoutSeconds) { [self] in
            self.finish(timedOut: true)
        }
    }

    private func finish(timedOut: Bool) {
        // Single-completion guarantee: first caller through the locked flag wins.
        let alreadyFinished: Bool = lock.withLock {
            if finished { return true }
            finished = true
            return false
        }
        guard !alreadyFinished else { return }

        query.stop()
        let observer = lock.withLock { () -> NSObjectProtocol? in
            defer { self.observer = nil }
            return self.observer
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }

        let items = (0..<query.resultCount).compactMap { query.result(at: $0) as? NSMetadataItem }
        let urls: [URL] = items.compactMap { item in
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            return URL(fileURLWithPath: path)
        }
        let completion = lock.withLock { () -> ((SpotlightSearchResult) -> Void)? in
            defer { self.completion = nil }
            return self.completion
        }
        completion?(SpotlightSearchResult(urls: urls, timedOut: timedOut))
        lock.withLock { retainUntilFinished = nil }
    }
}
