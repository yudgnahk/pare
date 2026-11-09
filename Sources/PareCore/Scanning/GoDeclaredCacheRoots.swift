import Foundation

/// Go cache roots the user declared in the environment or Go's own env file, read without launching go.
enum GoDeclaredCacheRoots {
    /// `os.UserConfigDir()/go/env` on macOS, unless `GOENV` names another file.
    static func envFile(environment: [String: String], home: URL) -> URL? {
        if let override = environment["GOENV"] {
            return override.hasPrefix("/") ? URL(fileURLWithPath: override) : nil
        }
        return home.appending(path: "Library/Application Support/go/env")
    }

    /// Environment wins over the env file, as in go. A module cache without `GOMODCACHE` lives under each `GOPATH` entry.
    static func roots(environment: [String: String], home: URL) -> [URL] {
        let file = envFile(environment: environment, home: home).map(parseEnvFile) ?? [:]
        func value(_ key: String) -> String? {
            [environment[key], file[key]].compactMap { $0 }.first { !$0.isEmpty }
        }
        let goPath = (value("GOPATH") ?? "").split(separator: ":").map { String($0) + "/pkg/mod" }
        let direct = [value("GOCACHE"), value("GOMODCACHE")].compactMap { $0 }
        // Relative values (`off`) are no location, and `URL(fileURLWithPath:)` would anchor them at the working directory.
        return (direct + goPath)
            .filter { $0.hasPrefix("/") && $0 != "/" }
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    private static func parseEnvFile(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            values[String(line[..<equals])] = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        }
        return values
    }
}
