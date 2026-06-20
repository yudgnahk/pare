import Foundation

/// Identifies non-Homebrew apps that have a matching cask and can be adopted
/// via `brew install --cask --adopt <token>`.
///
/// Fetches the full cask catalog from formulae.brew.sh with a 24-hour on-disk cache.
public actor MigrationAdvisor {

    private static let catalogURL = URL(string: "https://formulae.brew.sh/api/cask.json")!
    private static let cacheFilename = "brew_cask_catalog.json"
    private static let cacheTTL: TimeInterval = 86_400  // 24 hours

    public init() {}

    /// Returns apps that can be migrated to Homebrew Cask management.
    /// - Parameter installedApps: All installed apps (from AppInventory).
    public func candidates(for installedApps: [InstalledApp]) async -> [MigrationCandidate] {
        guard BrewRunner.shared.isInstalled else { return [] }

        guard let catalog = await fetchCatalog() else { return [] }

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

        // Ground-truth set of tokens already in the Caskroom — AppInventory does not
        // reliably set isHomebrewManaged, so we check the filesystem directly.
        let managedTokens = Self.installedCaskTokens()

        var seen = Set<String>()  // deduplicate by cask token
        var results: [MigrationCandidate] = []

        for app in installedApps {
            guard !app.isSystemApp else { continue }

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

            // Skip tokens already adopted into Homebrew or already listed.
            guard let token = matchedToken,
                  !seen.contains(token),
                  !managedTokens.contains(token) else { continue }
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

        guard let (data, _) = try? await URLSession.shared.data(from: Self.catalogURL),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        saveCatalog(data)
        return parsed
    }

    private func cacheFileURL() -> URL {
        let support = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
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

    /// Returns the set of cask tokens that are currently in the Caskroom on disk.
    /// A token directory with at least one version subdirectory means Homebrew
    /// manages that cask — including apps adopted via `brew install --cask --adopt`.
    private static func installedCaskTokens() -> Set<String> {
        let caskrooms = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]
        var tokens = Set<String>()
        for caskroom in caskrooms {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: caskroom) else { continue }
            for token in entries {
                let versionDir = "\(caskroom)/\(token)"
                if let versions = try? FileManager.default.contentsOfDirectory(atPath: versionDir),
                   !versions.isEmpty {
                    tokens.insert(token)
                }
            }
        }
        return tokens
    }
}
