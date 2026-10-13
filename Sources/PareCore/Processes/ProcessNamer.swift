import Foundation

/// Turns an executable and its arguments into a readable name; returns no argument text verbatim except allow-listed words.
public enum ProcessNamer {
    static let maxNameLength = 60

    /// Tools whose own binary or package name reads badly.
    static let knownNames: [String: String] = [
        "claude": "Claude Code",
        "claude-code": "Claude Code",
        "@anthropic-ai/claude-code": "Claude Code",
        "codex": "Codex",
        "@openai/codex": "Codex"
    ]

    /// Subcommands worth showing after a script name; anything else could be user data.
    static let subcommands: Set<String> = [
        "serve", "server", "mcp", "start", "run", "dev", "watch", "daemon",
        "worker", "agent", "lsp", "proxy", "build", "test", "preview"
    ]

    /// Script names that say nothing on their own, so the package folder names the process.
    static let genericScriptNames: Set<String> = [
        "index", "main", "cli", "server", "app", "run", "start", "__main__", "entry", "bin"
    ]

    static let packageNoiseFolders: Set<String> = ["dist", "build", "lib", "bin", "src", "out", "esm", "cjs"]
    static let scriptExtensions: Set<String> = ["js", "mjs", "cjs", "ts", "mts", "py", "rb", "pl", "php"]
    static let simpleInterpreters: Set<String> = ["node", "nodejs", "bun", "deno", "ruby", "perl", "php"]
    /// Interpreter flags whose next argument is a value, not the script.
    static let flagsWithValue: Set<String> = ["-r", "--require", "--import", "--loader", "--experimental-loader", "-W", "-X"]

    public static func identify(executablePath: String?, kernelName: String, arguments: [String]?) -> ProcessIdentity {
        let executableName = executablePath.map { ($0 as NSString).lastPathComponent }.flatMap(nonEmpty) ?? kernelName
        let arguments = arguments ?? []
        let name = resolvedName(executablePath: executablePath, executableName: executableName, kernelName: kernelName, arguments: arguments)
        return ProcessIdentity(
            displayName: clean(name) ?? clean(kernelName) ?? "pid",
            executableName: clean(executableName) ?? "",
            paseoAgentID: paseoAgentID(in: arguments)
        )
    }

    private static func resolvedName(executablePath: String?, executableName: String, kernelName: String, arguments: [String]) -> String {
        if let known = knownNames[executableName] { return known }
        if isInterpreter(executableName), let script = scriptName(arguments: arguments) {
            return knownNames[script] ?? script
        }
        if let title = processTitle(argv0: arguments.first, executableName: executableName) { return title }
        if let path = executablePath, let app = innermostAppName(path) { return app }
        return executableName
    }

    static func isInterpreter(_ name: String) -> Bool {
        simpleInterpreters.contains(name) || name.range(of: #"^[Pp]ython(\d+(\.\d+)?)?$"#, options: .regularExpression) != nil
    }

    /// `node /x/bin/gitnexus mcp` → `gitnexus mcp`; `python -m http.server` → `http.server`.
    static func scriptName(arguments: [String]) -> String? {
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "-m", index + 1 < arguments.count {
                let module = arguments[index + 1]
                guard module.range(of: #"^[A-Za-z_][A-Za-z0-9_.]{0,59}$"#, options: .regularExpression) != nil else { return nil }
                return withSubcommand(module, arguments: arguments, after: index + 1)
            }
            if argument == "-c" || argument == "-e" || argument == "--eval" || argument == "-p" { return nil }
            if argument.hasPrefix("-") {
                index += flagsWithValue.contains(argument) ? 2 : 1
                continue
            }
            guard let base = scriptBaseName(argument) else { return nil }
            return withSubcommand(base, arguments: arguments, after: index)
        }
        return nil
    }

    private static func withSubcommand(_ base: String, arguments: [String], after index: Int) -> String {
        guard index + 1 < arguments.count, subcommands.contains(arguments[index + 1]) else { return base }
        return base + " " + arguments[index + 1]
    }

    /// Script file name without extension; a generic name defers to its package folder.
    static func scriptBaseName(_ path: String) -> String? {
        // URLs, `key=value` pairs and query strings can carry secrets; only plain paths name a script.
        guard path.range(of: #"^[A-Za-z0-9._@+~/ -]{1,1024}$"#, options: .regularExpression) != nil else { return nil }
        let components = path.split(separator: "/").map(String.init)
        guard let file = components.last else { return nil }
        let ext = (file as NSString).pathExtension.lowercased()
        let stem = scriptExtensions.contains(ext) ? (file as NSString).deletingPathExtension : file
        guard genericScriptNames.contains(stem.lowercased()) else { return stem }
        if let package = nodePackageName(components) { return package }
        let folders = components.dropLast().reversed().filter { !packageNoiseFolders.contains($0.lowercased()) }
        return folders.first ?? stem
    }

    /// `…/node_modules/@scope/pkg/dist/cli.js` → `@scope/pkg`.
    private static func nodePackageName(_ components: [String]) -> String? {
        guard let marker = components.lastIndex(of: "node_modules"), marker + 1 < components.count - 1 else { return nil }
        let first = components[marker + 1]
        if first.hasPrefix("@"), marker + 2 < components.count - 1 {
            return first + "/" + components[marker + 2]
        }
        return first
    }

    /// A rewritten argv[0] such as Electron's "Paseo Daemon"; rejects anything that could hold data.
    static func processTitle(argv0: String?, executableName: String) -> String? {
        guard let argv0, argv0 != executableName,
              argv0.range(of: #"^[A-Za-z][A-Za-z0-9 _()-]{0,39}$"#, options: .regularExpression) != nil
        else { return nil }
        return argv0
    }

    /// `/Applications/Foo.app/Contents/Frameworks/Foo Helper.app/Contents/MacOS/Foo Helper` → `Foo Helper`.
    static func innermostAppName(_ path: String) -> String? {
        path.split(separator: "/").last { $0.hasSuffix(".app") }.map { String($0.dropLast(4)) }
    }

    /// Paseo passes `callerAgentId=<uuid>` inside the agent's MCP config.
    static func paseoAgentID(in arguments: [String]) -> UUID? {
        let marker = "callerAgentId="
        for argument in arguments {
            guard let range = argument.range(of: marker) else { continue }
            let candidate = argument[range.upperBound...].prefix(36)
            if let id = UUID(uuidString: String(candidate)) { return id }
        }
        return nil
    }

    private static func clean(_ name: String) -> String? {
        let printable = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        let trimmed = printable.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > maxNameLength ? String(trimmed.prefix(maxNameLength - 1)) + "…" : trimmed
    }

    private static func nonEmpty(_ string: String) -> String? {
        string.isEmpty ? nil : string
    }
}
