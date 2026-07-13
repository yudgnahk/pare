import Foundation
import AppKit

/// Scans for per-app leftover files and moves the app + leftovers to Trash.
/// Never uses FileManager.removeItem — always NSWorkspace.recycle.
public struct AppUninstaller: Sendable {

    public init() {}

    /// Returns all leftover paths for the given app, grouped by category.
    /// Group containers are included but flagged — never auto-selected.
    public func findLeftovers(for app: InstalledApp) -> [AppLeftover] {
        guard let bundleID = app.bundleID else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        var leftovers: [AppLeftover] = []

        let patterns: [(base: String, suffix: String?, category: AppLeftoverCategory, isGroup: Bool)] = [
            ("\(home)/Library/Application Support", bundleID,        .support,           false),
            ("\(home)/Library/Caches",              bundleID,        .caches,            false),
            ("\(home)/Library/Containers",          bundleID,        .containers,        false),
            ("\(home)/Library/WebKit",              bundleID,        .webkit,            false),
            ("\(home)/Library/HTTPStorages",        bundleID,        .httpStorage,       false),
            ("\(home)/Library/Saved Application State", "\(bundleID).savedState", .savedState, false),
            ("\(home)/Library/Application Scripts", bundleID,        .applicationScripts,false),
        ]

        for (base, suffix, category, _) in patterns {
            let url = suffix != nil
                ? URL(fileURLWithPath: base).appendingPathComponent(suffix!)
                : URL(fileURLWithPath: base)
            if FileManager.default.fileExists(atPath: url.path) {
                let size = AppInventory.totalAllocatedSize(at: url)
                leftovers.append(AppLeftover(path: url.path, sizeBytes: size, category: category))
            }
        }

        // Preferences: plist files matching bundleID prefix
        let prefsDir = "\(home)/Library/Preferences"
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: prefsDir) {
            for file in contents where file.hasPrefix(bundleID) {
                let fullPath = "\(prefsDir)/\(file)"
                let size = (try? FileManager.default.attributesOfItem(atPath: fullPath)[.size] as? Int64) ?? 0
                leftovers.append(AppLeftover(path: fullPath, sizeBytes: size, category: .preferences))
            }
        }

        // Logs: directory or files matching bundleID
        let logsDir = "\(home)/Library/Logs"
        let logURL = URL(fileURLWithPath: logsDir).appendingPathComponent(bundleID)
        if FileManager.default.fileExists(atPath: logURL.path) {
            let size = AppInventory.totalAllocatedSize(at: logURL)
            leftovers.append(AppLeftover(path: logURL.path, sizeBytes: size, category: .logs))
        }

        // Cookies
        let cookiePath = "\(home)/Library/Cookies/\(bundleID).binarycookies"
        if FileManager.default.fileExists(atPath: cookiePath) {
            let size = (try? FileManager.default.attributesOfItem(atPath: cookiePath)[.size] as? Int64) ?? 0
            leftovers.append(AppLeftover(path: cookiePath, sizeBytes: size, category: .cookies))
        }

        // LaunchAgents (user)
        leftovers.append(contentsOf: findLaunchItems(
            in: "\(home)/Library/LaunchAgents", bundleID: bundleID, category: .launchAgents
        ))
        // LaunchAgents (system) and LaunchDaemons
        leftovers.append(contentsOf: findLaunchItems(
            in: "/Library/LaunchAgents", bundleID: bundleID, category: .launchAgents
        ))
        leftovers.append(contentsOf: findLaunchItems(
            in: "/Library/LaunchDaemons", bundleID: bundleID, category: .launchDaemons
        ))

        // Group Containers — listed separately, never auto-selected
        let groupContainerDir = "\(home)/Library/Group Containers"
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: groupContainerDir) {
            for item in contents where item.hasSuffix(".\(bundleID)") || item.contains(bundleID) {
                let fullPath = "\(groupContainerDir)/\(item)"
                let size = AppInventory.totalAllocatedSize(at: URL(fileURLWithPath: fullPath))
                leftovers.append(AppLeftover(
                    path: fullPath,
                    sizeBytes: size,
                    category: .groupContainers,
                    isGroupContainer: true
                ))
            }
        }

        return leftovers.sorted { $0.category.rawValue < $1.category.rawValue }
    }

    private func findLaunchItems(in dir: String, bundleID: String, category: AppLeftoverCategory) -> [AppLeftover] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return contents.compactMap { file -> AppLeftover? in
            guard file.contains(bundleID) else { return nil }
            let path = "\(dir)/\(file)"
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
            return AppLeftover(path: path, sizeBytes: size, category: category)
        }
    }

    /// Checks if the app is managed by Homebrew by inspecting the caskroom receipt.
    public func homebrewCaskToken(for app: InstalledApp) -> String? {
        HomebrewCaskroom.token(forAppName: app.name, path: app.path)
    }

    /// Moves the app bundle and the given leftovers to Trash.
    /// Group containers in the `leftovers` array are skipped unless explicitly included.
    /// Returns the paths that were successfully trashed, and those that failed.
    @MainActor
    public func uninstall(
        app: InstalledApp,
        leftovers: [AppLeftover],
        includeGroupContainers: Bool = false
    ) async -> (trashed: [String], failed: [(String, Error)]) {
        var toTrash: [String] = [app.path]
        for leftover in leftovers where !leftover.isGroupContainer || includeGroupContainers {
            toTrash.append(leftover.path)
        }

        var trashed: [String] = []
        var failed: [(String, Error)] = []

        for path in toTrash {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            do {
                var resultURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resultURL)
                trashed.append(path)
            } catch {
                failed.append((path, error))
            }
        }

        return (trashed, failed)
    }
}
