import Foundation

/// Resolves a folder path to its owner by whole path components relative to the home directory.
public struct OwnerResolver: OwnerResolving {
    /// Directories under `~/Library` whose first child is usually a bundle ID.
    private static let bundleIDParents: Set<String> = [
        "caches", "application support", "containers", "httpstorages", "webkit", "logs",
    ]

    private let homeComponents: [String]
    private let installed: InstalledAppIndex
    private let projects: ProjectIndex
    private let table: OwnerTable
    private let cache = BundleMatchCache()

    public init(
        homeDirectory: URL,
        installedApps: InstalledAppIndex,
        projects: ProjectIndex = .empty,
        catalog: AppCatalog = .shared
    ) {
        self.homeComponents = OwnerTable.components(of: homeDirectory.path)
        self.installed = installedApps
        self.projects = projects
        self.table = OwnerTable(known: KnownOwners.all, catalog: catalog)
    }

    public func owner(forFolderPath path: String) -> FolderOwner {
        if let project = projects.project(containing: path) { return .project(project) }
        let comps = OwnerTable.components(of: path)
        guard !homeComponents.isEmpty, comps.starts(with: homeComponents) else {
            return table.rootOwner(comps) ?? .other
        }
        let rel = comps.dropFirst(homeComponents.count)
        guard !rel.isEmpty else { return .other }
        return table.homeOwner(rel) ?? libraryBundleOwner(rel) ?? .other
    }

    private func libraryBundleOwner(_ rel: ArraySlice<String>) -> FolderOwner? {
        let start = rel.startIndex
        guard rel.count >= 3, rel[start] == "library", Self.bundleIDParents.contains(rel[start + 1]) else {
            return nil
        }
        let component = rel[start + 2]
        let parts = component.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, !parts.contains(where: \.isEmpty), !component.contains(" ") else { return nil }
        if let known = table.bundleOwner(parts) { return known }
        if let app = cache.match(component, in: installed) {
            return FolderOwner(kind: .app, key: "app:\(app.id)", displayName: app.name)
        }
        return parts[0] == "com" && parts[1] == "apple" ? .macOS : .other
    }
}

/// Memoises installed-app lookups, which may reach LaunchServices.
final class BundleMatchCache: @unchecked Sendable {
    private struct Entry { let app: InstalledAppMatch? }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func match(_ bundleID: String, in index: InstalledAppIndex) -> InstalledAppMatch? {
        lock.lock()
        if let hit = entries[bundleID] {
            lock.unlock()
            return hit.app
        }
        lock.unlock()
        let app = index.match(forBundleID: bundleID)
        lock.lock()
        entries[bundleID] = Entry(app: app)
        lock.unlock()
        return app
    }
}
