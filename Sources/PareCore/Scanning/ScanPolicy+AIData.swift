import Foundation

// MARK: - AI tool user data

extension ScanPolicy {

    /// Compiled Neural Engine models; deleting them broke Apple Intelligence until reboot, wherever the folder sits.
    static let e5BundleCacheFolderName = "com.apple.e5rt.e5bundlecache"

    /// Lowercased component runs of AI tool sessions, memories and model stores.
    static let neverCleanAIDataComponentSequences: [[String]] = [
        [".ollama", "models"],
        [".cache", "huggingface"],
        [".claude", "projects"],
        [".claude", "todos"],
        [".claude", "plans"],
        [".codex", "sessions"],
        [".codex", "archived_sessions"],
        [".continue", "sessions"],
        [".copilot", "session-state"],
        [e5BundleCacheFolderName],
    ]

    /// HuggingFace roots from `HF_HOME`, `HF_HUB_CACHE` and `XDG_CACHE_HOME`, absolute values only.
    public static func declaredAIDataRoots(environment: [String: String], home: URL) -> [URL] {
        func absolute(_ key: String, appending suffix: String? = nil) -> URL? {
            guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  value.hasPrefix("/") else { return nil }
            let url = URL(fileURLWithPath: value).standardizedFileURL
            guard url.pathComponents.count > 2, url.path != home.standardizedFileURL.path else { return nil }
            return suffix.map { url.appending(path: $0) } ?? url
        }
        return [absolute("HF_HOME"), absolute("HF_HUB_CACHE"), absolute("XDG_CACHE_HOME", appending: "huggingface")]
            .compactMap { $0 }
    }

    /// Environment-declared AI data roots, read once so per-path checks stay cheap.
    public static let processAIDataRoots: [URL] = declaredAIDataRoots(
        environment: ProcessInfo.processInfo.environment,
        home: FileManager.default.homeDirectoryForCurrentUser
    )
}
