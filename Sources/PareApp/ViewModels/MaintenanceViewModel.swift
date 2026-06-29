import Foundation
import PareCore

@MainActor
final class MaintenanceViewModel: ObservableObject {

    enum ActionState: Equatable {
        case idle
        case running
        case success
        case failed(String)

        var isRunning: Bool { self == .running }
        var isIdle: Bool { self == .idle }
    }

    @Published private(set) var states: [String: ActionState] = [:]
    @Published private(set) var logs: [String: [String]] = [:]
    @Published private(set) var showDockerAction = false

    private let runner = MaintenanceRunner.shared
    private var runningTasks: [String: Task<Void, Never>] = [:]

    var visibleActions: [MaintenanceAction] {
        MaintenanceCatalog.all.filter { action in
            action.id == MaintenanceCatalog.dockerPrune.id ? showDockerAction : true
        }
    }

    func state(for action: MaintenanceAction) -> ActionState {
        states[action.id] ?? .idle
    }

    func log(for action: MaintenanceAction) -> [String] {
        logs[action.id] ?? []
    }

    // MARK: - Lifecycle

    func onAppear() {
        Task { showDockerAction = await runner.isDockerRunning() }
    }

    // MARK: - Run

    func runAction(_ action: MaintenanceAction) {
        guard state(for: action) != .running else { return }
        states[action.id] = .running
        logs[action.id] = []

        runningTasks[action.id] = Task {
            do {
                for try await line in runner.run(action: action) {
                    logs[action.id, default: []].append(line)
                }
                states[action.id] = .success
            } catch {
                logs[action.id, default: []].append("✗ \(error.localizedDescription)")
                states[action.id] = .failed(error.localizedDescription)
            }
            runningTasks.removeValue(forKey: action.id)
        }
    }
}
