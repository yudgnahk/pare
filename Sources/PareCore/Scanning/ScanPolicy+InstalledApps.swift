import Foundation

extension ScanPolicy {

    private static let nonInstalledContainerExtensions: Set<String> = ["app", "framework", "bundle"]

    private static let buildOutputComponents: Set<String> = [
        ".build", "dist", "build", "deriveddata", "node_modules", "pods", "target", ".trash", ".trashes"
    ]

    /// Whether a Spotlight-found `.app` is an installed app rather than an updater copy, nested helper or build output.
    public static func isInstalledAppLocation(
        _ url: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let path = url.standardizedFileURL
        let library = home.appendingPathComponent("Library")
        if isEqualToOrDescendant(candidate: path, root: library) { return false }

        let parents = path.deletingLastPathComponent().pathComponents.map { $0.lowercased() }
        for component in parents {
            if buildOutputComponents.contains(component) { return false }
            let ext = (component as NSString).pathExtension
            if nonInstalledContainerExtensions.contains(ext) { return false }
        }
        return true
    }
}
