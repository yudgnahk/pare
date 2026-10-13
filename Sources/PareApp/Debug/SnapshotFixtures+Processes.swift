#if DEBUG
import Foundation
import PareCore

/// Fake process tree for the Processes snapshot: a Paseo daemon running Claude Code agents, plus a browser.
extension SnapshotFixtures {
    private struct FakeProcess {
        let pid: Int32
        let ppid: Int32
        let name: String
        let executable: String
        let megabytes: UInt64
        let cpu: Double
        var agent: PaseoAgentInfo? = nil
    }

    static var processTree: ProcessTree {
        ProcessTreeBuilder.build(fakeProcesses.map { process in
            ProcessTreeBuilder.Input(
                record: ProcessRecord(
                    id: ProcessID(pid: process.pid, startMicros: 1),
                    parentPID: process.ppid,
                    kernelName: process.executable,
                    executablePath: nil,
                    footprintBytes: process.megabytes << 20,
                    cpuTimeNanos: 0
                ),
                identity: ProcessIdentity(displayName: process.name, executableName: process.executable),
                cpuPercent: process.cpu,
                paseoAgent: process.agent
            )
        })
    }

    /// Paseo daemon and its first agent open, the way a user drills into the heaviest branch.
    static var processSnapshotExpanded: Set<ProcessID> {
        [ProcessID(pid: 900, startMicros: 1), ProcessID(pid: 1001, startMicros: 1)]
    }

    private static func agent(_ title: String, _ project: String, _ status: String, minutesAgo: Double) -> PaseoAgentInfo {
        PaseoAgentInfo(
            title: title,
            cwd: root + "/home/Projects/acme/" + project,
            lastStatus: status,
            lastUserMessageAt: Date().addingTimeInterval(-minutesAgo * 60)
        )
    }

    private static var fakeProcesses: [FakeProcess] {
        var processes = [
            FakeProcess(pid: 900, ppid: 1, name: "Paseo Daemon", executable: "Paseo Helper", megabytes: 182, cpu: 2.1),
            FakeProcess(pid: 1001, ppid: 900, name: "Claude Code", executable: "claude", megabytes: 290, cpu: 18.4,
                        agent: agent("Add the Processes tab to the app", "storefront", "running", minutesAgo: 2)),
            FakeProcess(pid: 1002, ppid: 900, name: "Claude Code", executable: "claude", megabytes: 236, cpu: 0.3,
                        agent: agent("Review the checkout refactor", "checkout-api", "idle", minutesAgo: 41)),
            FakeProcess(pid: 1003, ppid: 900, name: "Claude Code", executable: "claude", megabytes: 147, cpu: 0,
                        agent: agent("Why is the nightly build slow?", "build-tools", "idle", minutesAgo: 180)),
            FakeProcess(pid: 1101, ppid: 1001, name: "zsh", executable: "zsh", megabytes: 412, cpu: 61.0),
            FakeProcess(pid: 1102, ppid: 1101, name: "swift-frontend", executable: "swift-frontend", megabytes: 1_240, cpu: 96.5),
            FakeProcess(pid: 2000, ppid: 1, name: "Google Chrome", executable: "Google Chrome", megabytes: 420, cpu: 1.2),
            FakeProcess(pid: 2001, ppid: 2000, name: "Google Chrome Helper (Renderer)", executable: "Google Chrome Helper (Renderer)", megabytes: 615, cpu: 3.4),
            FakeProcess(pid: 2002, ppid: 2000, name: "Google Chrome Helper (GPU)", executable: "Google Chrome Helper (GPU)", megabytes: 233, cpu: 2.0),
            FakeProcess(pid: 3000, ppid: 1, name: "Xcode", executable: "Xcode", megabytes: 1_310, cpu: 0.8),
            FakeProcess(pid: 3100, ppid: 1, name: "Slack", executable: "Slack", megabytes: 380, cpu: 0.4),
            FakeProcess(pid: 3200, ppid: 1, name: "vite dev", executable: "node", megabytes: 210, cpu: 0.6),
            FakeProcess(pid: 3300, ppid: 1, name: "Finder", executable: "Finder", megabytes: 96, cpu: 0)
        ]
        for (offset, parent) in [1001, 1002, 1003].enumerated() {
            let base = Int32(1200 + offset * 10)
            processes.append(FakeProcess(pid: base, ppid: Int32(parent), name: "code-review-graph serve", executable: "python3.11", megabytes: 79, cpu: 0.1))
            processes.append(FakeProcess(pid: base + 1, ppid: Int32(parent), name: "gitnexus mcp", executable: "node", megabytes: 157 - UInt64(offset) * 40, cpu: 0))
        }
        return processes
    }
}
#endif
