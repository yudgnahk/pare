import Foundation

/// The environment a confirmed tool runs with: nothing that makes it load code the confirmation did not cover.
public enum ToolSpawnEnvironment {
    static let removedKeys: Set<String> = ["NODE_OPTIONS", "NODE_PATH"]
    /// `GIT_*` would steer any git a tool shells out to (`GIT_CONFIG_*`, `GIT_EXEC_PATH`, `GIT_DIR`).
    static let removedPrefixes = ["DYLD_", "GIT_"]
    /// A `GOTOOLCHAIN` in `go env -w` or the environment makes go download and exec another toolchain;
    /// git config files (`~/.gitconfig` aliases) are how a git behind the tool would run code.
    static let forced = ["GOTOOLCHAIN": "local", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]

    public static func sanitized(_ environment: [String: String]) -> [String: String] {
        environment
            .filter { key, _ in !removedKeys.contains(key) && !removedPrefixes.contains { key.hasPrefix($0) } }
            .merging(forced) { _, forcedValue in forcedValue }
    }
}
