import Foundation

/// The environment a confirmed tool runs with: nothing that makes it load code the confirmation did not cover.
public enum ToolSpawnEnvironment {
    static let removedKeys: Set<String> = ["NODE_OPTIONS", "NODE_PATH"]
    static let removedPrefixes = ["DYLD_"]
    /// Otherwise a `GOTOOLCHAIN` in `go env -w` or the environment makes go download and exec another toolchain.
    static let forced = ["GOTOOLCHAIN": "local"]

    public static func sanitized(_ environment: [String: String]) -> [String: String] {
        environment
            .filter { key, _ in !removedKeys.contains(key) && !removedPrefixes.contains { key.hasPrefix($0) } }
            .merging(forced) { _, forcedValue in forcedValue }
    }
}
