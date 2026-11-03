import XCTest
@testable import PareCore

final class ProcessNamerTests: XCTestCase {

    private func name(_ path: String?, kernel: String = "x", _ arguments: [String]?) -> String {
        ProcessNamer.identify(executablePath: path, kernelName: kernel, arguments: arguments).displayName
    }

    func testNamingTable() {
        let cases: [(label: String, path: String?, kernel: String, args: [String]?, expected: String)] = [
            ("claude binary", "/opt/homebrew/bin/claude", "claude", ["/opt/homebrew/bin/claude", "--verbose"], "Claude Code"),
            ("codex binary", "/opt/homebrew/bin/codex", "codex", ["codex", "app-server"], "Codex"),
            ("python script with subcommand", "/Users/u/.local/share/uv/tools/code-review-graph/bin/python", "python3.11",
             ["/Users/u/.local/share/uv/tools/code-review-graph/bin/python", "/Users/u/.local/bin/code-review-graph", "serve"],
             "code-review-graph serve"),
            ("node script with subcommand", "/Users/u/.nvm/versions/node/v22/bin/node", "node",
             ["node", "/Users/u/.nvm/versions/node/v22/bin/gitnexus", "mcp"], "gitnexus mcp"),
            ("subcommand outside the allow-list is dropped", "/usr/bin/node", "node",
             ["node", "/x/tool.js", "deploy-prod"], "tool"),
            ("python -m module", "/usr/bin/python3", "python3", ["python3", "-m", "http.server", "8000"], "http.server"),
            ("interpreter flags are skipped", "/usr/bin/node", "node",
             ["node", "--max-old-space-size=4096", "-r", "ts-node/register", "/srv/app/worker.ts"], "worker"),
            ("generic script names its package", "/usr/bin/node", "node",
             ["node", "/u/lib/node_modules/typescript/lib/index.js"], "typescript"),
            ("scoped package resolves to a known name", "/usr/bin/node", "node",
             ["node", "/u/lib/node_modules/@anthropic-ai/claude-code/cli.js"], "Claude Code"),
            ("generic script outside node_modules names its folder", "/usr/bin/python3", "python3",
             ["python3", "/Users/u/Projects/billing/src/main.py"], "billing"),
            ("inline code is not a script", "/usr/bin/python3", "python3", ["python3", "-c", "print(1)"], "python3"),
            ("app helper", "/Applications/Foo.app/Contents/Frameworks/Foo Helper.app/Contents/MacOS/Foo Helper", "Foo Helper",
             ["/Applications/Foo.app/Contents/Frameworks/Foo Helper.app/Contents/MacOS/Foo Helper", "--type=gpu"], "Foo Helper"),
            ("rewritten process title", "/Applications/Paseo.app/Contents/Frameworks/Paseo Helper.app/Contents/MacOS/Paseo Helper",
             "Paseo Helper", ["Paseo Daemon"], "Paseo Daemon"),
            ("title with data falls back to the executable", "/usr/local/bin/postgres", "postgres",
             ["postgres: kelvin app 127.0.0.1(5432) idle"], "postgres"),
            ("bundle-id title falls back to the app", "/Applications/Bar.app/Contents/MacOS/Bar", "Bar",
             ["com.example.bar.agent"], "Bar"),
            ("plain executable", "/usr/sbin/cfprefsd", "cfprefsd", ["/usr/sbin/cfprefsd", "agent"], "cfprefsd"),
            ("no path or arguments uses the kernel name", nil, "kernel-thing", nil, "kernel-thing")
        ]
        for testCase in cases {
            XCTAssertEqual(name(testCase.path, kernel: testCase.kernel, testCase.args), testCase.expected, testCase.label)
        }
    }

    func testExecutableNameIsThePathBasename() {
        let identity = ProcessNamer.identify(executablePath: "/usr/bin/node", kernelName: "node", arguments: ["node", "/x/gitnexus", "mcp"])

        XCTAssertEqual(identity.executableName, "node")
    }

    func testURLOrKeyValueArgumentNeverBecomesTheName() {
        let secret = "sk-live-0123456789abcdef"
        let urlArgs = ["deno", "https://example.com/run.ts?token=\(secret)"]
        let pairArgs = ["node", "TOKEN=\(secret)"]

        XCTAssertFalse(name("/usr/local/bin/deno", kernel: "deno", urlArgs).contains(secret))
        XCTAssertFalse(name("/usr/bin/node", kernel: "node", pairArgs).contains(secret))
    }

    func testLongNamesAreTruncated() {
        let long = String(repeating: "a", count: 200)
        let result = name("/usr/bin/" + long, kernel: "k", nil)

        XCTAssertEqual(result.count, ProcessNamer.maxNameLength)
        XCTAssertTrue(result.hasSuffix("…"))
    }

    func testExtractsPaseoAgentIDFromMCPConfig() {
        let id = UUID()
        let config = #"{"mcpServers":{"paseo":{"type":"http","url":"http://127.0.0.1:6767/mcp/agents?callerAgentId="# + id.uuidString.lowercased() + #""}}}"#
        let identity = ProcessNamer.identify(
            executablePath: "/opt/homebrew/bin/claude",
            kernelName: "claude",
            arguments: ["claude", "--mcp-config", config]
        )

        XCTAssertEqual(identity.paseoAgentID, id)
    }

    func testMalformedAgentIDIsIgnored() {
        let identity = ProcessNamer.identify(
            executablePath: "/opt/homebrew/bin/claude",
            kernelName: "claude",
            arguments: ["claude", "--mcp-config", "callerAgentId=../../etc/passwd"]
        )

        XCTAssertNil(identity.paseoAgentID)
    }
}
