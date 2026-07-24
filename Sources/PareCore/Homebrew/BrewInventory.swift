import Foundation

/// Fetches all installed Homebrew formulae and casks via `brew info --json=v2 --installed`.
public actor BrewInventory {

    public init() {}

    /// Returns (formulae, casks). Throws if Homebrew is not installed.
    public func scan(showAll: Bool = false) async throws -> (formulae: [BrewFormula], casks: [BrewCask]) {
        let output = try await BrewRunner.shared.run(["info", "--json=v2", "--installed"])
        guard let data = output.data(using: .utf8) else {
            return ([], [])
        }
        return try parse(data: data, showAll: showAll)
    }

    // MARK: - Private

    private func parse(data: Data, showAll: Bool) throws -> (formulae: [BrewFormula], casks: [BrewCask]) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], [])
        }

        let formulae = parseFormulae(root["formulae"] as? [[String: Any]] ?? [], showAll: showAll)
        let casks = parseCasks(root["casks"] as? [[String: Any]] ?? [])
        return (formulae, casks)
    }

    private func parseFormulae(_ items: [[String: Any]], showAll: Bool) -> [BrewFormula] {
        let cellarRoots = Self.cellarRoots()

        return items.compactMap { item -> BrewFormula? in
            guard let name = item["name"] as? String,
                  let installedList = item["installed"] as? [[String: Any]],
                  let first = installedList.first,
                  let version = first["version"] as? String else { return nil }

            let installedOnRequest = first["installed_on_request"] as? Bool ?? true
            guard showAll || installedOnRequest else { return nil }

            let pinned = item["pinned"] as? Bool ?? false
            let deps = item["dependencies"] as? [String] ?? []
            let desc = item["desc"] as? String ?? ""

            var installDate: Date?
            if let timestamp = first["time"] as? TimeInterval {
                installDate = Date(timeIntervalSince1970: timestamp)
            }

            let sizeBytes = Self.kegSizeBytes(name: name, version: version, cellarRoots: cellarRoots)

            return BrewFormula(
                name: name,
                desc: desc,
                version: version,
                installedOnRequest: installedOnRequest,
                pinned: pinned,
                installDate: installDate,
                dependencies: deps,
                sizeBytes: sizeBytes
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Homebrew Cellar roots for Apple Silicon and Intel prefixes.
    private static func cellarRoots() -> [String] {
        ["/opt/homebrew/Cellar", "/usr/local/Cellar"]
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Measures the installed keg directory size (versioned path preferred).
    private static func kegSizeBytes(name: String, version: String, cellarRoots: [String]) -> Int64 {
        for root in cellarRoots {
            let versioned = "\(root)/\(name)/\(version)"
            if FileManager.default.fileExists(atPath: versioned) {
                return FileSystemUtils.directorySize(url: URL(fileURLWithPath: versioned))
            }
            let unversioned = "\(root)/\(name)"
            if FileManager.default.fileExists(atPath: unversioned) {
                return FileSystemUtils.directorySize(url: URL(fileURLWithPath: unversioned))
            }
        }
        return 0
    }

    private func parseCasks(_ items: [[String: Any]]) -> [BrewCask] {
        let appSearchDirs = Self.appSearchDirectories()

        return items.compactMap { item -> BrewCask? in
            guard let token = item["token"] as? String,
                  let version = item["version"] as? String else { return nil }

            let autoUpdates = item["auto_updates"] as? Bool ?? false

            var appNames: [String] = []
            if let artifacts = item["artifacts"] as? [[String: Any]] {
                for artifact in artifacts {
                    if let apps = artifact["app"] as? [String] {
                        appNames.append(contentsOf: apps)
                    }
                }
            }

            var installDate: Date?
            if let timestamp = item["installed_time"] as? TimeInterval {
                installDate = Date(timeIntervalSince1970: timestamp)
            }

            let matchedAppURLs = Self.matchingAppURLs(appNames: appNames, searchDirs: appSearchDirs)
            let orphaned = !appNames.isEmpty && matchedAppURLs.isEmpty

            return BrewCask(
                token: token,
                version: version,
                autoUpdates: autoUpdates,
                installedAppNames: appNames,
                installDate: installDate,
                lastUsed: Self.mostRecentLastUsedDate(among: matchedAppURLs),
                isOrphaned: orphaned
            )
        }
        .sorted { $0.token.localizedCaseInsensitiveCompare($1.token) == .orderedAscending }
    }

    private static func appSearchDirectories() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/Applications", "\(home)/Applications", "/System/Applications"]
    }

    /// A cask is orphaned when it has at least one .app artifact listed but
    /// none of those apps can be found in any standard application directory.
    /// Casks with no .app artifacts (CLI tools, fonts, etc.) are not flagged.
    ///
    /// Multi-app casks return every existing bundle (order follows Homebrew
    /// artifact order, then search-dir order) so last-used can take the max.
    static func matchingAppURLs(appNames: [String], searchDirs: [String]) -> [URL] {
        var urls: [URL] = []
        for appName in appNames {
            for directory in searchDirs {
                let url = URL(fileURLWithPath: directory).appendingPathComponent(appName)
                if FileManager.default.fileExists(atPath: url.path) {
                    urls.append(url)
                    break // first matching search dir for this artifact
                }
            }
        }
        return urls
    }

    /// Most recent Spotlight last-used date among app bundles.
    static func mostRecentLastUsedDate(among urls: [URL]) -> Date? {
        urls.compactMap(lastUsedDate(for:)).max()
    }

    private static func lastUsedDate(for url: URL) -> Date? {
        let item = NSMetadataItem(url: url)
        return item?.value(forAttribute: kMDItemLastUsedDate as String) as? Date
    }
}
