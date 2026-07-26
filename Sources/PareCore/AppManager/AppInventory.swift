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
                    await Self.discoverApps(in: dir)
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
                        mutable.sizeBytes = FileSystemUtils.directorySize(url: URL(fileURLWithPath: app.path))
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

    private static func discoverApps(in directory: URL) async -> [InstalledApp] {
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
        return await withCheckedContinuation { continuation in
            let query = NSMetadataQuery()
            query.predicate = NSPredicate(
                format: "kMDItemContentType == 'com.apple.application-bundle'"
            )
            query.searchScopes = [NSMetadataQueryLocalComputerScope]

            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(
                forName: NSNotification.Name.NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { _ in
                query.stop()
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                    observer = nil
                }

                var apps: [InstalledApp] = []
                let standardPrefixes = ["/Applications/", "/System/Applications/",
                                        FileManager.default.homeDirectoryForCurrentUser
                                            .appendingPathComponent("Applications").path + "/"]

                for i in 0..<query.resultCount {
                    guard let item = query.result(at: i) as? NSMetadataItem,
                          let path = item.value(forAttribute: kMDItemPath as String) as? String else {
                        continue
                    }
                    // Skip apps already covered by standard location scan
                    guard !standardPrefixes.contains(where: { path.hasPrefix($0) }) else { continue }
                    let url = URL(fileURLWithPath: path)
                    if let app = makeApp(from: url, isSystem: false) {
                        apps.append(app)
                    }
                }
                continuation.resume(returning: apps)
            }

            DispatchQueue.main.async { query.start() }

            // Timeout after 5 seconds to avoid hanging
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if query.isStarted && !query.isStopped {
                    query.stop()
                    if let obs = observer {
                        NotificationCenter.default.removeObserver(obs)
                        observer = nil
                    }
                    continuation.resume(returning: [])
                }
            }
        }
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
}
