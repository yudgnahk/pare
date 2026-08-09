import XCTest
@testable import PareCore

final class ProcessTerminationRaceTests: XCTestCase {

    func testSystemProcessRunnerCompletesForRepeatedImmediateExit() async throws {
        let runner = SystemProcessRunner()

        for _ in 0..<100 {
            let result = try await runner.run(
                executablePath: "/usr/bin/true",
                arguments: [],
                environment: nil
            )

            XCTAssertEqual(result.exitCode, 0)
            XCTAssertEqual(result.standardOutput, "")
            XCTAssertEqual(result.standardError, "")
        }
    }

    func testToolCommandRunnerCompletesForRepeatedImmediateExit() async {
        let runner = ToolCommandRunner()

        for _ in 0..<100 {
            let output = await runner.capture(
                executable: URL(fileURLWithPath: "/usr/bin/true"),
                arguments: []
            )

            XCTAssertEqual(output, "")
        }
    }

    func testSystemProcessRunnerBalancesSetupWhenLaunchFails() async {
        let missingExecutable = "/definitely/not/a/real/tool/\(UUID().uuidString)"

        do {
            _ = try await SystemProcessRunner().run(
                executablePath: missingExecutable,
                arguments: [],
                environment: nil
            )
            XCTFail("Expected an invalid executable path to throw")
        } catch {
            // A prompt error proves launch failure did not strand the setup gate.
        }
    }

    func testToolCommandRunnerBalancesSetupWhenLaunchFails() async {
        let missingExecutable = URL(
            fileURLWithPath: "/definitely/not/a/real/tool/\(UUID().uuidString)"
        )

        let output = await ToolCommandRunner().capture(
            executable: missingExecutable,
            arguments: []
        )

        XCTAssertNil(output)
    }
}
