import Foundation

/// Locates PareCore's SPM resource bundle, returning `nil` instead of trapping.
///
/// `Bundle.module` calls `fatalError` when packaging misplaces the bundle, which
/// turns a degradable missing-resource case into a crash mid-scan.
enum ResourceBundle {
    private final class Token {}

    private static let bundleName = "Pare_PareCore"

    /// Same search order as SwiftPM's generated accessor, minus the `fatalError`.
    static nonisolated let pareCore: Bundle? = {
        var candidates: [URL?] = []

        #if DEBUG
        // `swift test` points at the built bundle through this variable.
        let env = ProcessInfo.processInfo.environment
        if let override = env["PACKAGE_RESOURCE_BUNDLE_PATH"] ?? env["PACKAGE_RESOURCE_BUNDLE_URL"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        #endif

        candidates += [
            Bundle.main.resourceURL,           // linked into an app
            Bundle(for: Token.self).resourceURL, // linked into a framework
            Bundle.main.bundleURL,             // command-line tools
        ]

        for case let base? in candidates {
            let url = base.appendingPathComponent("\(bundleName).bundle")
            if let bundle = Bundle(url: url) { return bundle }
        }
        return nil
    }()
}
