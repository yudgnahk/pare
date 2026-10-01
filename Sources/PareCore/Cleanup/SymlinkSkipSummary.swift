import Foundation

/// Collapses N symlink-blocked skip rows into one line when a single symlinked ancestor (e.g. home) caused them all.
public enum SymlinkSkipSummary {

    /// One explanatory line, or nil unless every skip is `.symbolicLinkBlocked` under one shared symlinked ancestor.
    public static func message(
        for skipped: [CleanupSkippedItem],
        hasSymbolicLinkComponent: (String) -> Bool = ScanPolicy.hasSymbolicLinkComponent(atPath:)
    ) -> String? {
        guard skipped.allSatisfy(isSymlinkBlocked),
              let ancestor = sharedSymlinkedAncestor(
                of: skipped.map(\.path),
                hasSymbolicLinkComponent: hasSymbolicLinkComponent
              )
        else { return nil }
        return "All \(skipped.count) items were skipped because \(ancestor) is a symbolic link. "
            + "Pare never moves items through a symbolic link to the Trash."
    }

    /// Shallowest prefix shared by all `paths` that contains a symbolic link; needs at least two paths.
    static func sharedSymlinkedAncestor(
        of paths: [String],
        hasSymbolicLinkComponent: (String) -> Bool
    ) -> String? {
        guard paths.count >= 2 else { return nil }
        let componentLists = paths.map { URL(fileURLWithPath: $0).standardizedFileURL.pathComponents }
        guard let first = componentLists.first else { return nil }
        var prefix = URL(fileURLWithPath: "/")
        for (index, component) in first.enumerated() where index > 0 {
            guard componentLists.allSatisfy({ $0.count > index && $0[index] == component }) else { return nil }
            prefix = prefix.appendingPathComponent(component)
            if hasSymbolicLinkComponent(prefix.path) { return prefix.path }
        }
        return nil
    }

    private static func isSymlinkBlocked(_ item: CleanupSkippedItem) -> Bool {
        if case .symbolicLinkBlocked = item.error { return true }
        return false
    }
}
