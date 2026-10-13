import XCTest
@testable import PareCore

final class PaseoAgentResolverTests: XCTestCase {

    private var agents: URL!

    override func setUpWithError() throws {
        agents = FileManager.default.temporaryDirectory
            .appendingPathComponent("pare_paseo_\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: agents.deletingLastPathComponent())
    }

    @discardableResult
    private func writeSession(_ id: UUID, slug: String = "Users-u-Projects-shop", json: String) throws -> URL {
        let folder = agents.appendingPathComponent(slug, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(id.uuidString.lowercased() + ".json")
        try Data(json.utf8).write(to: file)
        return file
    }

    private func sessionJSON(title: String = "Fix checkout", status: String = "running") -> String {
        """
        {"id":"x","title":"\(title)","cwd":"/Users/u/Projects/shop","lastStatus":"\(status)",
         "lastUserMessageAt":"2026-10-12T06:12:16.248Z","config":{"token":"never-read"}}
        """
    }

    func testResolvesSessionFields() throws {
        let id = UUID()
        try writeSession(id, json: sessionJSON())
        var resolver = PaseoAgentResolver(agentsDirectory: agents)

        let info = try XCTUnwrap(resolver.resolve(id))

        XCTAssertEqual(info.title, "Fix checkout")
        XCTAssertEqual(info.cwd, "/Users/u/Projects/shop")
        XCTAssertEqual(info.lastStatus, "running")
        XCTAssertEqual(info.lastUserMessageAt, PaseoAgentResolver.parseDate("2026-10-12T06:12:16.248Z"))
        XCTAssertNotNil(info.lastUserMessageAt)
    }

    func testMissingAgentsDirectoryIsSilent() {
        var resolver = PaseoAgentResolver(agentsDirectory: agents.appendingPathComponent("absent"))

        XCTAssertNil(resolver.resolve(UUID()))
    }

    func testMissingFileIsSilent() throws {
        try writeSession(UUID(), json: sessionJSON())
        var resolver = PaseoAgentResolver(agentsDirectory: agents)

        XCTAssertNil(resolver.resolve(UUID()))
    }

    func testMalformedJSONIsSilent() throws {
        let id = UUID()
        try writeSession(id, json: "{not json")
        var resolver = PaseoAgentResolver(agentsDirectory: agents)

        XCTAssertNil(resolver.resolve(id))
    }

    func testWrongFieldTypeIsSilent() throws {
        let id = UUID()
        try writeSession(id, json: #"{"title": 42}"#)
        var resolver = PaseoAgentResolver(agentsDirectory: agents)

        XCTAssertNil(resolver.resolve(id))
    }

    func testOversizedFileIsNotRead() throws {
        let id = UUID()
        let padding = String(repeating: " ", count: PaseoAgentResolver.maxFileBytes)
        try writeSession(id, json: sessionJSON() + padding)
        var resolver = PaseoAgentResolver(agentsDirectory: agents)

        XCTAssertNil(resolver.resolve(id))
    }

    func testSymlinkedSessionIsSkipped() throws {
        let id = UUID()
        let real = try writeSession(UUID(), slug: "elsewhere", json: sessionJSON())
        let folder = agents.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent(id.uuidString.lowercased() + ".json"),
            withDestinationURL: real
        )
        var resolver = PaseoAgentResolver(agentsDirectory: agents)

        XCTAssertNil(resolver.resolve(id))
    }

    func testRereadsWhenTheFileChanges() throws {
        let id = UUID()
        let file = try writeSession(id, json: sessionJSON(status: "running"))
        var resolver = PaseoAgentResolver(agentsDirectory: agents)
        XCTAssertEqual(resolver.resolve(id)?.lastStatus, "running")

        try Data(sessionJSON(status: "idle").utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: file.path)

        XCTAssertEqual(resolver.resolve(id)?.lastStatus, "idle")
    }

    func testMissIsRetriedOnlyAfterTheBackoff() throws {
        let id = UUID()
        let clock = PaseoTestClock()
        var resolver = PaseoAgentResolver(agentsDirectory: agents, now: { clock.now })
        XCTAssertNil(resolver.resolve(id))

        try writeSession(id, json: sessionJSON())
        XCTAssertNil(resolver.resolve(id), "a miss is remembered for a while")

        clock.now = clock.now.addingTimeInterval(PaseoAgentResolver.missRetrySeconds + 1)
        XCTAssertNotNil(resolver.resolve(id))
    }

    func testAbbreviatedCwd() {
        let info = { (cwd: String?) in PaseoAgentInfo(title: nil, cwd: cwd, lastStatus: nil, lastUserMessageAt: nil) }

        XCTAssertEqual(info("/Users/u/Projects/acme/shop").abbreviatedCwd(homeDirectory: "/Users/u"), "~/…/acme/shop")
        XCTAssertEqual(info("/Users/u/Projects").abbreviatedCwd(homeDirectory: "/Users/u"), "~/Projects")
        XCTAssertEqual(info("/Users/u").abbreviatedCwd(homeDirectory: "/Users/u"), "~")
        XCTAssertEqual(info("/Users/uv/x/y/z").abbreviatedCwd(homeDirectory: "/Users/u"), "/…/y/z")
        XCTAssertEqual(info("/tmp/x").abbreviatedCwd(homeDirectory: "/Users/u"), "/tmp/x")
        XCTAssertNil(info(nil).abbreviatedCwd(homeDirectory: "/Users/u"))
    }
}

/// Test clock the resolver reads through a `@Sendable` closure.
private final class PaseoTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}
