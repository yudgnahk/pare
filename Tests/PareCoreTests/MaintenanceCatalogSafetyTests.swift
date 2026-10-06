import XCTest
@testable import PareCore

/// Rebuilding the Launch Services database drops VPN tunnels and forces a reindex, so Pare never offers it.
final class MaintenanceCatalogSafetyTests: XCTestCase {

    func testCatalogExcludesLaunchServicesRebuild() {
        for action in MaintenanceCatalog.all {
            XCTAssertNotEqual(action.id, "rebuild-launch-services")
            XCTAssertFalse(action.title.localizedCaseInsensitiveContains("launch services"), action.title)
            XCTAssertFalse(action.description.localizedCaseInsensitiveContains("launch services"), action.id)
        }
    }

    /// Every catalog action runs through a stub, so nothing real executes; none may reach `lsregister`.
    func testNoCatalogActionInvokesLsregister() async {
        let stub = StubProcessRunner(lines: [.stdout("ok")])
        let runner = MaintenanceRunner(processRunner: stub)

        for action in MaintenanceCatalog.all {
            do {
                for try await _ in runner.run(action: action) {}
            } catch {
                // Missing tools (e.g. docker) are fine; only the invoked executables matter.
            }
        }

        XCTAssertFalse(stub.invocations.isEmpty, "precondition: actions reached the stub")
        for invocation in stub.invocations {
            XCTAssertFalse(invocation.executablePath.hasSuffix("/lsregister"), invocation.executablePath)
        }
    }

    func testRemovedActionIdIsRejected() async {
        let removed = MaintenanceAction(
            id: "rebuild-launch-services",
            title: "Rebuild Launch Services",
            description: "",
            systemImage: "arrow.clockwise.circle",
            estimatedSeconds: 15
        )
        let stub = StubProcessRunner()

        do {
            for try await _ in MaintenanceRunner(processRunner: stub).run(action: removed) {}
            XCTFail("a removed action must not run")
        } catch {
            guard case MaintenanceError.unknownAction = error else {
                return XCTFail("expected unknownAction, got \(error)")
            }
        }
        XCTAssertTrue(stub.invocations.isEmpty)
    }
}
