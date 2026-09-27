import Foundation
import PareCore

/// Immutable crumb trail from a fixed root down to the current Disk Analyzer level.
struct DiskBreadcrumb: Equatable {

    struct Crumb: Equatable, Identifiable {
        let id: String
        let url: URL
        let name: String
    }

    let root: URL
    let current: URL

    /// Fails when `current` is not `root` or a descendant of it.
    init?(root: URL, current: URL) {
        let canonicalRoot = DiskBreadcrumb.canonicalize(root)
        let canonicalCurrent = DiskBreadcrumb.canonicalize(current)
        guard ScanPolicy.isEqualToOrDescendant(candidate: canonicalCurrent, root: canonicalRoot) else {
            return nil
        }
        self.root = canonicalRoot
        self.current = canonicalCurrent
    }

    /// Foundation's `resolvingSymlinksInPath()` deliberately leaves `/tmp`, `/var`, `/etc`
    /// unresolved (BSD compatibility), so a path like `/var/folders/...` never becomes
    /// `/private/var/folders/...` on its own even though the two spell the same directory —
    /// normalize that indirection by hand so root/current comparisons never split on spelling.
    private static let privateIndirectionRoots = ["/tmp", "/var", "/etc"]

    private static func canonicalize(_ url: URL) -> URL {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let path = resolved.path
        guard !path.hasPrefix("/private") else { return resolved }
        for indirection in privateIndirectionRoots where path == indirection || path.hasPrefix(indirection + "/") {
            return URL(fileURLWithPath: "/private" + path)
        }
        return resolved
    }

    /// Crumbs from root through current, inclusive of both endpoints.
    var crumbs: [Crumb] {
        let rootComponents = root.pathComponents
        let currentComponents = current.pathComponents
        guard currentComponents.count >= rootComponents.count else { return [] }

        return (rootComponents.count...currentComponents.count).map { depth in
            let components = Array(currentComponents.prefix(depth))
            let url = URL(fileURLWithPath: NSString.path(withComponents: components))
            return Crumb(id: url.path, url: url, name: url.lastPathComponent)
        }
    }

    /// One level up; `nil` when already at the root.
    func up() -> DiskBreadcrumb? {
        guard current != root else { return nil }
        return DiskBreadcrumb(root: root, current: current.deletingLastPathComponent())
    }

    /// Descends into `child`; `nil` when it is not inside the current level.
    func enter(_ child: URL) -> DiskBreadcrumb? {
        let canonicalChild = DiskBreadcrumb.canonicalize(child)
        guard ScanPolicy.isEqualToOrDescendant(candidate: canonicalChild, root: current) else {
            return nil
        }
        return DiskBreadcrumb(root: root, current: canonicalChild)
    }
}
