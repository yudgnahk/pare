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
        items.compactMap { item -> BrewFormula? in
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

            return BrewFormula(
                name: name,
                desc: desc,
                version: version,
                installedOnRequest: installedOnRequest,
                pinned: pinned,
                installDate: installDate,
                dependencies: deps
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func parseCasks(_ items: [[String: Any]]) -> [BrewCask] {
        let appSearchDirs = Self.appSearchDirectories()

        return items.compactMap { item -> BrewCask? in
            guard let token = item["token"] as? String,
                  let version = item["version"] as? String else { return nil }

            let autoUpdates = item["auto_updates"] as? Bool ?? false

            var appNames: [String] = []       // from "app" artifacts — name only, checked in search dirs
            var directAppPaths: [String] = [] // from "uninstall.delete" — full paths, checked directly
            var requiresSudo = false

            if let artifacts = item["artifacts"] as? [[String: Any]] {
                for artifact in artifacts {
                    if let apps = artifact["app"] as? [String] {
                        appNames.append(contentsOf: apps)
                    }
                    // pkg-based casks (e.g. Microsoft Teams) have no "app" artifact; instead
                    // the installed .app path appears in uninstall[].delete[].
                    if let uninstalls = artifact["uninstall"] as? [[String: Any]] {
                        for u in uninstalls {
                            if let deletes = u["delete"] as? [String] {
                                directAppPaths.append(contentsOf: deletes.filter { $0.hasSuffix(".app") })
                                // System-level deletes (not ~/Library) require sudo.
                                if deletes.contains(where: { $0.hasPrefix("/Library/") }) {
                                    requiresSudo = true
                                }
                            }
                            // pkgutil --forget requires sudo to modify the package receipt DB.
                            if u["pkgutil"] != nil { requiresSudo = true }
                        }
                    }
                }
            }

            // For display: if there are no "app" artifacts, derive names from pkg delete paths.
            let displayNames: [String] = appNames.isEmpty
                ? directAppPaths.map { URL(fileURLWithPath: $0).lastPathComponent }
                : appNames

            var installDate: Date?
            if let timestamp = item["installed_time"] as? TimeInterval {
                installDate = Date(timeIntervalSince1970: timestamp)
            }

            let orphaned = Self.isOrphaned(appNames: appNames, directPaths: directAppPaths, searchDirs: appSearchDirs)

            return BrewCask(
                token: token,
                version: version,
                autoUpdates: autoUpdates,
                installedAppNames: displayNames,
                installDate: installDate,
                isOrphaned: orphaned,
                requiresSudo: requiresSudo
            )
        }
        .sorted { $0.token.localizedCaseInsensitiveCompare($1.token) == .orderedAscending }
    }

    private static func appSearchDirectories() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/Applications", "\(home)/Applications", "/System/Applications"]
    }

    /// A cask is orphaned when its installed app bundle(s) can no longer be found on disk.
    ///
    /// - `appNames`: basenames from "app" artifacts — checked inside each search directory.
    /// - `directPaths`: full paths from pkg "uninstall.delete" entries — checked as-is.
    /// - Casks with neither (pure CLI tools, fonts, drivers) are never flagged.
    private static func isOrphaned(appNames: [String], directPaths: [String], searchDirs: [String]) -> Bool {
        // pkg-based casks: check the full install paths recorded in uninstall.delete
        if !directPaths.isEmpty {
            return !directPaths.contains { FileManager.default.fileExists(atPath: $0) }
        }
        // app-based casks: check name presence in standard application directories
        guard !appNames.isEmpty else { return false }
        return !appNames.contains { appName in
            searchDirs.contains { dir in
                FileManager.default.fileExists(atPath: "\(dir)/\(appName)")
            }
        }
    }
}
