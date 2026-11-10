import Foundation
import PareCore

/// Settings rows for the third-party tools scans may run, and the Confirm / Forget actions.
@MainActor
final class DeveloperToolsViewModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let tool: ConfirmableTool
        let state: ToolTrustState
        var id: String { tool.rawValue }
    }

    /// Settings waits longer than a scan: the user may be answering a Keychain prompt.
    static let loadTimeoutSeconds: TimeInterval = 60

    @Published private(set) var rows: [Row] = []
    @Published private(set) var busyTool: ConfirmableTool?
    @Published var errorMessage: String?

    private let registry: ConfirmedToolRegistry
    private let environment: [String: String]

    init(
        registry: ConfirmedToolRegistry = .shared,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.registry = registry
        self.environment = environment
    }

    func refresh() async {
        var loaded: [Row] = []
        for tool in ConfirmableTool.allCases {
            let state = await registry.state(for: tool, environment: environment, timeout: Self.loadTimeoutSeconds)
            loaded.append(Row(tool: tool, state: state))
        }
        rows = loaded
    }

    func confirm(_ tool: ConfirmableTool, path: String) async {
        await perform(tool) { registry in _ = try registry.confirm(tool, path: path) }
    }

    func forget(_ tool: ConfirmableTool) async {
        await perform(tool) { registry in try registry.forget(tool) }
    }

    private func perform(_ tool: ConfirmableTool, _ change: @escaping @Sendable (ConfirmedToolRegistry) throws -> Void) async {
        busyTool = tool
        defer { busyTool = nil }
        let registry = registry
        // Keychain calls block until any prompt is answered, so keep them off the main actor.
        let result = await Task.detached { Result { try change(registry) } }.value
        switch result {
        case .success: errorMessage = nil
        case .failure(let rejection as ToolRejection): errorMessage = rejection.message
        case .failure: errorMessage = "Couldn't save to Keychain."
        }
        await refresh()
    }
}
