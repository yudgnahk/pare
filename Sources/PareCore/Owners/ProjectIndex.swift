import Foundation

/// Reports which project markers a directory holds, from one listing.
public protocol ProjectMarkerProbing: Sendable {
    func probe(directory: String) -> (hasGit: Bool, hasMarker: Bool)
}

/// Lists the directory once; `.git` may be a folder or a worktree/submodule file.
public struct FileSystemMarkerProbe: ProjectMarkerProbing {
    public init() {}

    public func probe(directory: String) -> (hasGit: Bool, hasMarker: Bool) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return (false, false)
        }
        let present = Set(names)
        let marked = ScanPolicy.projectRootMarkerFileNames.contains { $0 != ".git" && present.contains($0) }
        return (present.contains(".git"), marked)
    }
}

/// Maps scan folders to the project that owns them, decided once per scan from registered roots.
public struct ProjectIndex: Sendable {
    public static let empty = ProjectIndex(projects: [:])

    private let projects: [String: ProjectRef]

    private init(projects: [String: ProjectRef]) { self.projects = projects }

    /// Only paths passed to `build` are known; anything else is not a project.
    public func project(containing folderPath: String) -> ProjectRef? { projects[folderPath] }

    public static func build(
        folderPaths: [String],
        registeredRoots: [URL],
        homeDirectory: URL,
        probe: any ProjectMarkerProbing = FileSystemMarkerProbe()
    ) -> ProjectIndex {
        var builder = Builder(roots: registeredRoots, home: homeDirectory, probe: probe)
        var found: [String: ProjectRef] = [:]
        for path in folderPaths where found[path] == nil {
            if let ref = builder.project(for: path) { found[path] = ref }
        }
        return ProjectIndex(projects: found)
    }
}

private struct Builder {
    private struct Root { let url: URL; let depth: Int }

    private let roots: [Root]
    private let homeLower: String
    private let probe: any ProjectMarkerProbing
    private var memo: [String: (hasGit: Bool, hasMarker: Bool)] = [:]

    init(roots: [URL], home: URL, probe: any ProjectMarkerProbing) {
        var seen = Set<String>()
        self.roots = roots.compactMap { url in
            let canonical = ScanPolicy.canonicalPathURL(url)
            guard seen.insert(canonical.path.lowercased()).inserted else { return nil }
            return Root(url: canonical, depth: canonical.pathComponents.count - 1)
        }
        self.homeLower = ScanPolicy.canonicalPathURL(home).path.lowercased()
        self.probe = probe
    }

    mutating func project(for folderPath: String) -> ProjectRef? {
        let folder = ScanPolicy.canonicalPathURL(URL(fileURLWithPath: folderPath))
        let containing = roots.filter {
            ScanPolicy.isCanonicallyEqualToOrDescendant(candidate: folder, root: $0.url)
        }
        guard let root = containing.max(by: { $0.depth < $1.depth }) else { return nil }
        let comps = Array(folder.pathComponents.dropFirst())
        // The artifact's parent; the root itself when the folder is the root.
        let start = max(comps.count - 1, root.depth)
        var nearestMarker: String?
        var steps = 0
        var depth = start
        while depth >= root.depth, depth > 0, steps < ScanPolicy.projectRootEvidenceMaxAncestors {
            steps += 1
            defer { depth -= 1 }
            let path = "/" + comps.prefix(depth).joined(separator: "/")
            if reachesHome(path) { break }
            if comps[root.depth..<depth].contains("node_modules") { continue }
            let result = cachedProbe(path)
            if result.hasGit { return ref(path) }
            if result.hasMarker, nearestMarker == nil { nearestMarker = path }
        }
        return nearestMarker.map(ref)
    }

    private func ref(_ path: String) -> ProjectRef {
        ProjectRef(root: path, name: (path as NSString).lastPathComponent)
    }

    private func reachesHome(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower == homeLower || homeLower.hasPrefix(lower + "/")
    }

    private mutating func cachedProbe(_ path: String) -> (hasGit: Bool, hasMarker: Bool) {
        let key = path.lowercased()
        if let hit = memo[key] { return hit }
        let result = probe.probe(directory: path)
        memo[key] = result
        return result
    }
}
