import Foundation

/// Discovers all installed applications and collects per-app metadata.
/// Scans /Applications, /System/Applications, ~/Applications, and uses
/// NSMetadataQuery results for apps in non-standard locations (e.g. Setapp).
public actor AppInventory {

    public init() {}

    /// Returns all installed apps. Safe to call from any async context.
    public func scan() async -> [InstalledApp] {
        let locations: [URL] = Self.standardLocations()
        var apps: [InstalledApp] = []

        // Concurrent per-location scans
        await withTaskGroup(of: [InstalledApp].self) { group in
            for dir in locations {
                group.addTask {
                    Self.discoverApps(in: dir)
                }
            }
            for await batch in group {
                apps.append(contentsOf: batch)
            }
        }

        // Supplement with metadata-indexed apps (Setapp, etc.)
        let metadataApps = await Self.discoverViaMetadataQuery()
        let knownPaths = Set(apps.map { $0.path })
        for app in metadataApps where !knownPaths.contains(app.path) {
            apps.append(app)
        }

        // Mark Homebrew-managed apps using Caskroom receipts (cheap).
        let caskTokens = HomebrewCaskroom.installedTokens()
        for i in apps.indices {
            if HomebrewCaskroom.manages(
                appName: apps[i].name,
                path: apps[i].path,
                installedTokens: caskTokens
            ) {
                apps[i].isHomebrewManaged = true
            }
        }

        // Fetch sizes concurrently — expensive disk walk, do it in parallel
        var sized: [InstalledApp] = []
        await withTaskGroup(of: InstalledApp.self) { group in
            for app in apps {
                group.addTask {
                    var mutable = app
                    if mutable.sizeBytes == 0 {
                        mutable.sizeBytes = Self.totalAllocatedSize(at: URL(fileURLWithPath: app.path))
                    }
                    return mutable
                }
            }
            for await app in group {
                sized.append(app)
            }
        }

        return sized.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Private

    private static func standardLocations() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            home.appendingPathComponent("Applications")
        ]
    }

    /// Synchronous by design: `FileManager.DirectoryEnumerator` iteration is
    /// unavailable from async contexts under strict concurrency. Callers run
    /// this inside task-group children to keep per-location scans parallel.
    private static func discoverApps(in directory: URL) -> [InstalledApp] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isDirectoryKey, .creationDateKey, .contentModificationDateKey
            ],
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        ) else { return [] }

        var result: [InstalledApp] = []
        let isSystem = directory.path.hasPrefix("/System/")

        for case let url as URL in enumerator {
            guard url.pathExtension == "app" else { continue }
            if let app = makeApp(from: url, isSystem: isSystem) {
                result.append(app)
            }
        }
        return result
    }

    private static func discoverViaMetadataQuery() async -> [InstalledApp] {
        await MetadataQueryRunner.run()
    }

    static func makeApp(from url: URL, isSystem: Bool) -> InstalledApp? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: plistURL) else { return nil }

        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let bundleID = plist["CFBundleIdentifier"] as? String
        let version = (plist["CFBundleShortVersionString"] as? String) ?? ""
        let buildVersion = (plist["CFBundleVersion"] as? String) ?? version

        let resourceKeys: Set<URLResourceKey> = [.creationDateKey]
        let resourceValues = try? url.resourceValues(forKeys: resourceKeys)
        let installDate = resourceValues?.creationDate

        let isMAS = FileManager.default.fileExists(
            atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path
        )

        let lastUsed = Self.lastUsedDate(for: url)

        return InstalledApp(
            name: name,
            bundleID: bundleID,
            version: version,
            buildVersion: buildVersion,
            path: url.path,
            sizeBytes: 0,  // filled in later
            installDate: installDate,
            lastUsed: lastUsed,
            isMAS: isMAS,
            isSystemApp: isSystem || url.path.hasPrefix("/System/")
        )
    }

    private static func lastUsedDate(for url: URL) -> Date? {
        let item = NSMetadataItem(url: url)
        return item?.value(forAttribute: kMDItemLastUsedDate as String) as? Date
    }

    // MARK: - Spotlight bridge

    /// Bridges NSMetadataQuery (requires a RunLoop) to async/await for apps in
    /// non-standard locations (Setapp, etc.).
    ///
    /// The finish-gathering observer and the 5-second timeout race each other;
    /// a locked `finished` flag guarantees the continuation is resumed exactly
    /// once (the previous implementation could double-resume and crash).
    /// All query interaction happens on the main queue. The runner retains
    /// itself until `finish` runs so callbacks can never outlive it.
    private final class MetadataQueryRunner: NSObject, @unchecked Sendable {
        private let query = NSMetadataQuery()
        private let lock = NSLock()
        private var finished = false
        private var completion: (([InstalledApp]) -> Void)?
        private var observer: NSObjectProtocol?
        /// Keeps `self` alive from `start` until `finish` even if local refs drop.
        private var retainUntilFinished: MetadataQueryRunner?

        /// Maximum time to wait for Spotlight before completing empty.
        private static let timeoutSeconds: TimeInterval = 5

        static func run() async -> [InstalledApp] {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    let runner = MetadataQueryRunner()
                    runner.start { apps in
                        continuation.resume(returning: apps)
                    }
                }
            }
        }

        private func start(completion: @escaping ([InstalledApp]) -> Void) {
            lock.withLock {
                self.completion = completion
                // Self-retain until finish() so callback lifetimes cannot drop us early.
                self.retainUntilFinished = self
            }

            query.predicate = NSPredicate(
                format: "kMDItemContentType == 'com.apple.application-bundle'"
            )
            query.searchScopes = [NSMetadataQueryLocalComputerScope]

            let observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [self] _ in
                self.finish(collectResults: true)
            }
            lock.withLock { self.observer = observer }

            query.start()

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeoutSeconds) { [self] in
                self.finish(collectResults: false)
            }
        }

        /// Runs on the main queue only. First caller through the locked flag wins.
        private func finish(collectResults: Bool) {
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

            var apps: [InstalledApp] = []
            if collectResults {
                let standardPrefixes = ["/Applications/", "/System/Applications/",
                                        FileManager.default.homeDirectoryForCurrentUser
                                            .appendingPathComponent("Applications").path + "/"]
                for i in 0..<query.resultCount {
                    guard let item = query.result(at: i) as? NSMetadataItem,
                          let path = item.value(forAttribute: kMDItemPath as String) as? String else {
                        continue
                    }
                    // Skip apps already covered by the standard location scan.
                    guard !standardPrefixes.contains(where: { path.hasPrefix($0) }) else { continue }
                    if let app = AppInventory.makeApp(from: URL(fileURLWithPath: path), isSystem: false) {
                        apps.append(app)
                    }
                }
            }

            let completion = lock.withLock { () -> (([InstalledApp]) -> Void)? in
                defer { self.completion = nil }
                return self.completion
            }
            completion?(apps)
            lock.withLock { retainUntilFinished = nil }
        }
    }

    static func totalAllocatedSize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.totalFileAllocatedSize else { continue }
            total += Int64(size)
        }
        return total
    }
}
