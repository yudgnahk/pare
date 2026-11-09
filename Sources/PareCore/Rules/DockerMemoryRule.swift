import Foundation

/// Docker Desktop's Linux VM holding host RAM, read from its settings. Explain-only: Pare never edits Docker files.
public struct DockerMemoryRule: ScanRule {
    public let id = "docker-vm-memory"
    public let title = "Docker VM Memory"
    public let reason = "Docker Desktop's VM can hold a large share of RAM"
    public let category: ScanCategory = .diagnostics
    public let riskLevel: RiskLevel = .advanced
    public let confidence: Double = 0.8

    /// Docker defaults the VM to half of host RAM.
    static let defaultLimitDivisor: UInt64 = 2
    /// A limit this close to the default (or above) frees nothing.
    static let usefulLimitSlackMiB = 256
    /// Case B: on hosts this small the default half is too much even with Resource Saver on.
    static let smallHostBytes: UInt64 = 16 * 1024 * 1024 * 1024
    static let settingsDirectory = "Library/Group Containers/group.com.docker"
    static let settingsFiles = ["settings-store.json", "settings.json"]
    static let appBundleName = "Docker.app"
    private static let mib: UInt64 = 1024 * 1024

    public typealias FileReader = @Sendable (URL) -> Data?
    public typealias InstallCheck = @Sendable (URL) -> Bool

    private let readFile: FileReader
    private let hostMemoryBytes: @Sendable () -> UInt64
    private let swapUsedBytes: @Sendable () async -> Int64?
    private let isDockerInstalled: InstallCheck

    public init(
        readFile: FileReader? = nil,
        hostMemoryBytes: (@Sendable () -> UInt64)? = nil,
        swapUsedBytes: (@Sendable () async -> Int64?)? = nil,
        isDockerInstalled: InstallCheck? = nil
    ) {
        self.readFile = readFile ?? { try? Data(contentsOf: $0) }
        self.isDockerInstalled = isDockerInstalled ?? { Self.appBundleExists(home: $0) }
        self.hostMemoryBytes = hostMemoryBytes ?? { ProcessInfo.processInfo.physicalMemory }
        self.swapUsedBytes = swapUsedBytes ?? { await SwapUsageRule.currentUsedBytes() }
    }

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        // Uninstalling Docker leaves its Group Container behind.
        guard let (path, settings) = loadSettings(home: home), isDockerInstalled(home) else { return [] }
        let hostBytes = hostMemoryBytes()
        let hostMiB = Int(hostBytes / Self.mib)
        let defaultMiB = hostMiB / Int(Self.defaultLimitDivisor)
        let limitMiB = settings.memoryMiB ?? defaultMiB
        let noUsefulLimit = limitMiB >= defaultMiB - Self.usefulLimitSlackMiB
        let saverOff = settings.resourceSaver == false
        let kubernetes = settings.kubernetes == true
        let unsetOnSmallHost = settings.memoryMiB == nil && hostBytes <= Self.smallHostBytes
        guard (noUsefulLimit && (saverOff || kubernetes)) || unsetOnSmallHost else { return [] }
        guard let swap = await swapUsedBytes(), swap > SwapUsageRule.minimumReportedSwapBytes else { return [] }

        let gigabytes = limitMiB / 1024
        let limit = settings.memoryMiB == nil ? "no memory limit" : "memory limit \(gigabytes) GB"
        let reason: String
        if saverOff {
            reason = "Docker can hold \(gigabytes) GB of RAM while idle — Resource Saver is off, \(limit)"
        } else if kubernetes {
            reason = "Kubernetes keeps Docker holding up to \(gigabytes) GB of RAM — \(limit)"
        } else {
            reason = "Docker can take up to \(gigabytes) GB of RAM — \(limit) set"
        }
        return [ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: reason,
            path: path,
            sizeBytes: 0,
            lastUsed: nil,
            confidence: confidence,
            annotations: [
                .explainOnly(action: Self.tip(hostMiB: hostMiB, saverOff: saverOff, kubernetes: kubernetes)),
                .noteAction(.openDockerDesktop),
            ]
        )]
    }

    /// The store wins; legacy `settings.json` is read only when the store is absent.
    private func loadSettings(home: URL) -> (String, DockerVMSettings)? {
        let directory = home.appending(path: Self.settingsDirectory)
        for name in Self.settingsFiles {
            let url = directory.appending(path: name)
            guard let data = readFile(url) else { continue }
            return DockerDesktopSettingsParser.parse(data).map { (url.path, $0) }
        }
        return nil
    }

    private static func appBundleExists(home: URL) -> Bool {
        let roots = [URL(fileURLWithPath: "/Applications"), home.appending(path: "Applications")]
        return roots.contains { FileManager.default.fileExists(atPath: $0.appending(path: appBundleName).path) }
    }

    private static func tip(hostMiB: Int, saverOff: Bool, kubernetes: Bool) -> String {
        let suggested = max(2, hostMiB / 1024 / 4)
        var text = "Docker Desktop → Settings → Resources: set Memory limit to \(suggested) GB"
        if saverOff { text += ", turn on Resource Saver" }
        if kubernetes { text += ", turn off Kubernetes if unused" }
        return text + ". Opening Docker Desktop starts its VM."
    }
}
