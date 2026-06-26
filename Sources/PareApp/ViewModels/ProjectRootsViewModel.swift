import Foundation
import AppKit
import SwiftUI
import PareCore

@MainActor
public final class ProjectRootsViewModel: ObservableObject {
    @Published private(set) var discoveredRoots: [(url: URL, confirmed: Bool)] = []
    @Published private(set) var manualAdditions: [URL] = []
    @Published private(set) var isDiscovering = false
    @Published private(set) var lastDiscoveredAt: Date?
    @Published private(set) var hasRunDiscovery = false

    private let discovery = ProjectRootDiscovery.shared

    public init() {
        Task { await reload() }
    }

    public var hasAnyRoots: Bool {
        !discoveredRoots.isEmpty || !manualAdditions.isEmpty
    }

    public func runDiscovery() {
        guard !isDiscovering else { return }
        isDiscovering = true
        Task {
            await discovery.discover()
            await reload()
            isDiscovering = false
        }
    }

    public func toggleRoot(_ url: URL, confirmed: Bool) {
        Task {
            if confirmed {
                await discovery.confirm(url)
            } else {
                await discovery.exclude(url)
            }
            await reload()
        }
    }

    public func addManualPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project root directory to scan for build artifacts"
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await discovery.addManual(url)
            await reload()
        }
    }

    public func removeManual(_ url: URL) {
        Task {
            await discovery.removeManual(url)
            await reload()
        }
    }

    // MARK: Private

    private func reload() async {
        discoveredRoots = await discovery.allDiscoveredRoots
        manualAdditions = await discovery.manualAdditions
        lastDiscoveredAt = await discovery.discoveryDate
        hasRunDiscovery = lastDiscoveredAt != nil
    }
}
