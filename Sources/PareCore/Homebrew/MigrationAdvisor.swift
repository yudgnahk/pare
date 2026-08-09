import Foundation

/// Identifies non-Homebrew apps that have a matching cask and can be adopted
/// via `brew install --cask --adopt <token>`.
///
/// Fetches the full cask catalog from formulae.brew.sh with a 24-hour on-disk cache.
public actor MigrationAdvisor {

    private static let catalogURL = URL(string: "https://formulae.brew.sh/api/cask.json")!
    private static let cacheFilename = "brew_cask_catalog.json"
    private static let cacheTTL: TimeInterval = 86_400  // 24 hours

    /// Injected session — tests pass a `URLSession` whose configuration registers
    /// a stub `URLProtocol` so catalog fetches run without network access.
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Returns apps that can be migrated to Homebrew Cask management.
    /// - Parameter installedApps: All installed apps (from AppInventory).
    public func candidates(for installedApps: [InstalledApp]) async -> [MigrationCandidate] {
        guard BrewRunner.shared.isInstalled else { return [] }

        guard let catalog = await fetchCatalog() else { return [] }

        // Already-adopted / installed casks must never reappear in the migrate list.
        // (AppInventory may also set isHomebrewManaged; this is the definitive gate.)
        let installedCaskTokens = HomebrewCaskroom.installedTokens()

        // Build lookup sets from cask catalog
        var appNameToCask: [String: String] = [:]   // lowercase app name → cask token
        var bundleIDToCask: [String: String] = [:]  // bundle ID → cask token

        for cask in catalog {
            guard let token = cask["token"] as? String else { continue }
            if let artifacts = cask["artifacts"] as? [[String: Any]] {
                for artifact in artifacts {
                    if let apps = artifact["app"] as? [String] {
                        for app in apps {
                            let key = app.lowercased().replacingOccurrences(of: ".app", with: "")
                            appNameToCask[key] = token
                        }
                    }
                    if let uninstalls = artifact["uninstall"] as? [[String: Any]] {
                        for uninstall in uninstalls {
                            if let quit = uninstall["quit"] as? String {
                                bundleIDToCask[quit] = token
                            }
                            if let quits = uninstall["quit"] as? [String] {
                                for q in quits { bundleIDToCask[q] = token }
                            }
                        }
                    }
                }
            }
        }

        var seen = Set<String>()  // deduplicate by cask token
        var results: [MigrationCandidate] = []

        for app in installedApps {
            guard !app.isHomebrewManaged, !app.isSystemApp else { continue }

            // Path already under Caskroom → managed even if flag is stale.
            if HomebrewCaskroom.manages(
                appName: app.name,
                path: app.path,
                installedTokens: installedCaskTokens
            ) {
                continue
            }

            var matchedToken: String?

            // Match by bundle ID first (most precise)
            if let bid = app.bundleID, let token = bundleIDToCask[bid] {
                matchedToken = token
            }

            // Fallback: match by app name
            if matchedToken == nil {
                let nameKey = app.name.lowercased()
                if let token = appNameToCask[nameKey] {
                    matchedToken = token
                }
            }

            // Also try normalized path basename (e.g. "Antigravity.app")
            if matchedToken == nil {
                let base = URL(fileURLWithPath: app.path)
                    .deletingPathExtension()
                    .lastPathComponent
                    .lowercased()
                if let token = appNameToCask[base] {
                    matchedToken = token
                }
            }

            guard let token = matchedToken,
                  !seen.contains(token),
                  !installedCaskTokens.contains(token) else { continue }
            seen.insert(token)

            results.append(MigrationCandidate(
                caskToken: token,
                appName: app.name,
                bundleID: app.bundleID,
                currentPath: app.path
            ))
        }

        return results.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    // MARK: - Catalog fetch + cache

    private func fetchCatalog() async -> [[String: Any]]? {
        if let cached = loadCachedCatalog() { return cached }

        guard let (data, _) = try? await session.data(from: Self.catalogURL),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        saveCatalog(data)
        return parsed
    }

    private func cacheFileURL() -> URL {
        let support = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent(Self.cacheFilename)
    }

    private func loadCachedCatalog() -> [[String: Any]]? {
        let url = cacheFileURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < Self.cacheTTL,
              let data = try? Data(contentsOf: url),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return parsed
    }

    private func saveCatalog(_ data: Data) {
        try? data.write(to: cacheFileURL(), options: .atomic)
    }
}
