import Foundation

/// Where to look for developer tools. A Finder-launched app inherits only `/usr/bin:/bin:/usr/sbin:/sbin`,
/// so well-known install directories go after the inherited PATH; no shell or dotfile is ever read.
public enum ToolSearchPath {
    /// Homebrew on Apple silicon and Intel, and the official Go installer.
    static let fixedDirectories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/local/go/bin"]

    /// uv/pipx, rustup, standalone pnpm, and the Volta/mise/asdf shims a Node-based pnpm needs to find `node`.
    static let homeRelativeDirectories = [
        ".local/bin",
        ".cargo/bin",
        "Library/pnpm",
        ".local/share/pnpm",
        ".volta/bin",
        ".local/share/mise/shims",
        ".asdf/shims",
    ]

    /// Inherited PATH entries, then `PNPM_HOME`, then the well-known directories; absolute and deduplicated.
    public static func directories(environment: [String: String]) -> [String] {
        let home = environment["HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? NSHomeDirectory()
        let inherited = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let extra = [environment["PNPM_HOME"]].compactMap { $0 }
            + fixedDirectories
            + homeRelativeDirectories.map { URL(fileURLWithPath: home).appending(path: $0).path }
        var seen = Set<String>()
        return (inherited + extra).compactMap { entry in
            let directory = entry.count > 1 && entry.hasSuffix("/") ? String(entry.dropLast()) : entry
            // A relative entry would resolve against whatever the app's working directory happens to be.
            guard directory.hasPrefix("/"), seen.insert(directory).inserted else { return nil }
            return directory
        }
    }

    /// `directories(environment:)` as a PATH value, for a launched tool whose own scripts look up `node` etc.
    public static func pathValue(environment: [String: String]) -> String {
        directories(environment: environment).joined(separator: ":")
    }
}
