import Foundation

/// Lookup structures built once from `KnownOwners` and the app catalog.
struct OwnerTable: Sendable {
    private struct Wildcard: Sendable {
        let parent: [String]
        let prefix: String
        let owner: FolderOwner
    }

    private var home: [String: FolderOwner] = [:]
    private var root: [String: FolderOwner] = [:]
    private var bundles: [String: FolderOwner] = [:]
    private var wildcards: [Wildcard] = []
    private var maxHomeDepth = 0
    private var maxRootDepth = 0

    init(known: [KnownOwner], catalog: AppCatalog) {
        for entry in known { add(entry) }
        let knownNames = Set(known.map { $0.name.lowercased() })
        for entry in catalog.entries where !knownNames.contains(entry.displayName.lowercased()) {
            add(KnownOwner(
                entry.id, entry.displayName, .app,
                home: entry.libraryPaths.map { "Library/\($0)" } + entry.homePaths,
                traits: entry.category == "ai" ? [.ai] : []
            ))
        }
    }

    static func components(of path: String) -> [String] {
        var parts = path.lowercased().split(separator: "/").map(String.init)
        if let first = parts.first, first == "var" || first == "tmp" || first == "etc" {
            parts.insert("private", at: 0)
        }
        return parts
    }

    func homeOwner(_ rel: ArraySlice<String>) -> FolderOwner? {
        // Wildcards first: they are narrower than a shared parent such as Library/Caches/Google.
        let wild = wildcards.first { wildcard in
            rel.count > wildcard.parent.count
                && rel.prefix(wildcard.parent.count).elementsEqual(wildcard.parent)
                && rel[rel.startIndex + wildcard.parent.count].hasPrefix(wildcard.prefix)
        }
        return wild?.owner ?? longest(rel, in: home, maxDepth: maxHomeDepth)
    }

    func rootOwner(_ comps: [String]) -> FolderOwner? {
        longest(comps[...], in: root, maxDepth: maxRootDepth)
    }

    /// Longest dot-boundary prefix of a lowercase bundle ID that a known owner claims.
    func bundleOwner(_ parts: [Substring]) -> FolderOwner? {
        for n in stride(from: parts.count, through: 2, by: -1) {
            if let hit = bundles[parts.prefix(n).joined(separator: ".")] { return hit }
        }
        return nil
    }

    private func longest(_ rel: ArraySlice<String>, in table: [String: FolderOwner], maxDepth: Int) -> FolderOwner? {
        for k in stride(from: min(rel.count, maxDepth), through: 1, by: -1) {
            if let hit = table[rel.prefix(k).joined(separator: "/")] { return hit }
        }
        return nil
    }

    private mutating func add(_ entry: KnownOwner) {
        let owner = entry.owner
        for prefix in entry.homePrefixes { insert(prefix, owner: owner, root: false) }
        for prefix in entry.rootPrefixes { insert(prefix, owner: owner, root: true) }
        for id in entry.bundleIDs where bundles[id.lowercased()] == nil { bundles[id.lowercased()] = owner }
    }

    private mutating func insert(_ prefix: String, owner: FolderOwner, root isRoot: Bool) {
        var parts = prefix.lowercased().split(separator: "/").map(String.init)
        guard let last = parts.last else { return }
        if last.hasSuffix("*"), !isRoot {
            parts.removeLast()
            wildcards.append(Wildcard(parent: parts, prefix: String(last.dropLast()), owner: owner))
            return
        }
        let key = parts.joined(separator: "/")
        if isRoot {
            if root[key] == nil { root[key] = owner }
            maxRootDepth = max(maxRootDepth, parts.count)
        } else {
            if home[key] == nil { home[key] = owner }
            maxHomeDepth = max(maxHomeDepth, parts.count)
        }
    }
}
