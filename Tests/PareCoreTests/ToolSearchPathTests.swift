import XCTest
@testable import PareCore

final class ToolSearchPathTests: XCTestCase {
    /// What a Finder-launched app inherits.
    private let finderPath = "/usr/bin:/bin:/usr/sbin:/sbin"
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "pare-toolpath-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    @discardableResult
    private func makeTool(_ relativePath: String, script: String = "#!/bin/sh\necho ok\n") throws -> URL {
        let url = home.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testInheritedPathComesFirstThenWellKnownDirectories() {
        let directories = ToolSearchPath.directories(environment: [
            "PATH": "/custom/bin/:relative/bin::/usr/bin:/custom/bin",
            "HOME": home.path,
            "PNPM_HOME": "/pnpm/home",
        ])

        XCTAssertEqual(Array(directories.prefix(3)), ["/custom/bin", "/usr/bin", "/pnpm/home"])
        XCTAssertFalse(directories.contains("relative/bin"), "relative entries depend on the working directory")
        XCTAssertEqual(directories.count, Set(directories).count)
        for expected in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/local/go/bin",
                         home.appending(path: ".local/bin").path, home.appending(path: ".cargo/bin").path] {
            XCTAssertTrue(directories.contains(expected), expected)
        }
    }

    func testFinderPathStillFindsToolInWellKnownHomeDirectory() throws {
        let tool = try makeTool(".local/bin/pare-fake-uv")
        let cargoTool = try makeTool(".cargo/bin/pare-fake-cargo-tool")
        let environment = ["PATH": finderPath, "HOME": home.path]

        XCTAssertEqual(ToolSearchPath.firstExecutable(named: "pare-fake-uv", environment: environment)?.path, tool.path)
        XCTAssertEqual(ToolSearchPath.firstExecutable(named: "pare-fake-cargo-tool", environment: environment)?.path,
                       cargoTool.path)
    }

    func testNameWithSlashIsNeverResolved() {
        XCTAssertNil(ToolSearchPath.firstExecutable(named: "bin/ls", environment: ["PATH": "/"]))
    }
}
