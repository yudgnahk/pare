import SwiftUI

/// Top-level destinations for the left sidebar.
enum AppDestination: String, Hashable, CaseIterable, Identifiable {
    case smartScan
    case apps
    case homebrew
    case disk
    case maintenance
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartScan: return "Smart Scan"
        case .apps: return "Apps"
        case .homebrew: return "Homebrew"
        case .disk: return "Disk Analyzer"
        case .maintenance: return "Maintenance"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .smartScan: return "sparkles"
        case .apps: return "square.grid.2x2"
        case .homebrew: return "shippingbox"
        case .disk: return "externaldrive"
        case .maintenance: return "wrench.and.screwdriver"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }

    var section: SidebarSection {
        switch self {
        case .smartScan: return .cleanup
        case .apps, .homebrew, .disk, .maintenance: return .tools
        case .history, .settings: return .library
        }
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case cleanup = "Cleanup"
    case tools = "Tools"
    case library = "Library"

    var id: String { rawValue }

    var destinations: [AppDestination] {
        AppDestination.allCases.filter { $0.section == self }
    }
}
