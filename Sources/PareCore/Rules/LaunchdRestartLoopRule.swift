import Foundation

/// User launch agents that launchd keeps relaunching after they fail. Read-only: one
/// `launchctl print gui/<uid>` to find services whose last status is non-zero, then one
/// `launchctl print gui/<uid>/<label>` per candidate, capped. Explain-only; nothing is ever touched.
public struct LaunchdRestartLoopRule: ScanRule {
    public let id = "launchd-restart-loops"
    public let title = "Launch Agents in a Restart Loop"
    public let reason = "Launch agent that keeps failing and being restarted"
    public let category: ScanCategory = .diagnostics
    public let riskLevel: RiskLevel = .advanced
    public let confidence: Double = 0.9

    /// More launches than this with a failing last exit is a loop, not normal on-demand use.
    public static let minimumRestartCount = 1000
    /// Bounds the per-label `launchctl print` calls in one scan.
    public static let maxServicesInspected = 20
    /// Upper bound on the whole detector's time spent in launchctl.
    static let overallBudgetSeconds: TimeInterval = 15
    static let launchctlPath = "/bin/launchctl"

    /// Returns `launchctl print <target>` output, or nil when it failed or timed out.
    public typealias Print = @Sendable (String) async -> String?

    public struct Service: Sendable, Equatable {
        public let label: String
        public let runs: Int?
        public let lastExitCode: Int?
        public let lastSignal: String?
        public let plistPath: String?
        public let program: String?

        public var isRestartLoop: Bool {
            guard let runs, runs > LaunchdRestartLoopRule.minimumRestartCount else { return false }
            return (lastExitCode.map { $0 != 0 } ?? false) || lastSignal != nil
        }
    }

    private let uid: uid_t
    private let print: Print
    private let now: @Sendable () -> Date

    public init(uid: uid_t = getuid(), print: Print? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.uid = uid
        self.print = print ?? { target in
            await ToolCommandRunner().capture(executable: URL(fileURLWithPath: Self.launchctlPath), arguments: ["print", target])
        }
        self.now = now
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let domain = "gui/\(uid)"
        guard let listing = await print(domain) else { return [] }
        let deadline = now().addingTimeInterval(Self.overallBudgetSeconds)
        var findings: [ScanFinding] = []
        for label in Self.loopCandidates(fromDomainPrint: listing).prefix(Self.maxServicesInspected) {
            guard now() < deadline, !Task.isCancelled else { break }
            guard let output = await print("\(domain)/\(label)"),
                  let service = Self.service(label: label, fromPrint: output),
                  service.isRestartLoop else { continue }
            findings.append(finding(for: service))
        }
        return findings
    }

    // MARK: - Parsing

    /// Labels in the domain's `services` block whose last status (exit code, or negative signal) is non-zero.
    static func loopCandidates(fromDomainPrint output: String) -> [String] {
        var labels: [String] = []
        var inServices = false
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if !inServices {
                inServices = line == "\tservices = {"
                continue
            }
            if line.hasPrefix("\t}") { break }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 3, Int(fields[0]) != nil,
                  let status = Int(fields[1]), status != 0 else { continue }
            labels.append(String(fields[2]))
        }
        return labels
    }

    /// The service's own top-level fields (one tab deep); nested blocks are ignored. Nil when there are none.
    static func service(label: String, fromPrint output: String) -> Service? {
        var fields: [String: String] = [:]
        for line in output.split(separator: "\n") where line.hasPrefix("\t") && !line.hasPrefix("\t\t") {
            guard let separator = line.range(of: " = ") else { continue }
            let key = line[line.index(after: line.startIndex)..<separator.lowerBound]
            let value = line[separator.upperBound...]
            guard !value.hasSuffix("{"), fields[String(key)] == nil else { continue }
            fields[String(key)] = String(value)
        }
        guard !fields.isEmpty else { return nil }
        let path = fields["path"].flatMap { $0.hasPrefix("/") ? $0 : nil }
        return Service(
            label: label,
            runs: fields["runs"].flatMap { Int($0) },
            lastExitCode: fields["last exit code"].flatMap { Int($0) },
            lastSignal: fields["last terminating signal"],
            plistPath: path,
            program: fields["program"].flatMap { $0.hasPrefix("/") ? $0 : nil }
        )
    }

    // MARK: - Finding

    private func finding(for service: Service) -> ScanFinding {
        let runs = Self.grouped(service.runs ?? 0)
        let exit = service.lastSignal.map { "last terminated by signal \($0)" }
            ?? "last exit code \(service.lastExitCode ?? 0)"
        let action = service.plistPath.map { "Check or remove the agent in \($0)" }
            ?? "Check the app that registered it, or remove it from Login Items"
        let advice = service.plistPath.map { "check or remove the agent in \($0)" }
            ?? "check the app that registered it, or remove it from Login Items"
        return ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: "\(service.label) restarted \(runs) times; \(exit) — \(advice)",
            path: service.plistPath ?? service.program ?? "launchd:gui/\(uid)/\(service.label)",
            sizeBytes: 0,
            lastUsed: nil,
            confidence: confidence,
            annotations: [.explainOnly(action: action)]
        )
    }

    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
