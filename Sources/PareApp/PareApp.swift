import AppKit
import SwiftUI

@main
struct PareApp: App {
    @NSApplicationDelegateAdaptor(PareAppDelegate.self) private var appDelegate
    @StateObject private var models = AppModelStore()
    @StateObject private var textZoom = TextZoomController()

    var body: some Scene {
        WindowGroup("Pare") {
            ContentView(models: models)
                .environmentObject(textZoom)
                .modifier(TextZoomKeyMonitor(zoom: textZoom))
                .frame(
                    minWidth: AppTheme.Window.minWidth,
                    maxWidth: .infinity,
                    minHeight: AppTheme.Window.minHeight,
                    maxHeight: .infinity
                )
        }
        // Full-bleed window like App B — no opaque black title bar strip.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: AppTheme.Window.defaultWidth, height: AppTheme.Window.defaultHeight)
        .commands {
            TextZoomCommands(zoom: textZoom)
            DiagnosticsExportCommands(scanViewModel: models.scan)
        }
    }
}

/// Applies the brand Dock icon once AppKit is ready (Info.plist also references AppIcon).
private final class PareAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        PareBrandLogo.applyDockIconIfAvailable()
    }
}


struct ContentView: View {
    let models: AppModelStore
    @State private var selection: AppDestination = .smartScan

    var body: some View {
        DisplayScaleReader {
            // Environment (displayScale) is applied inside the reader.
            MainShellView(selection: $selection, models: models)
        }
    }
}

/// Shell that reads `displayScale` from the environment (inside DisplayScaleReader).
private struct MainShellView: View {
    @Binding var selection: AppDestination
    let models: AppModelStore
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
                .frame(width: max(200, AppTheme.Spacing.sidebarWidth * scale.spacingFactor))
                .frame(maxHeight: .infinity)

            Rectangle()
                .fill(AppTheme.Fill.control)
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            ZStack {
                AppBackgroundView()
                // No `.id(selection)` here: stamping the pane with the selection
                // destroyed every screen's state on tab switch (the switch below
                // already gives each destination its own identity).
                detailContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // Explicitly main-actor isolated: the destination views are @MainActor, and
    // older Swift toolchains do not infer isolation for a computed property
    // outside `body` (errors under strict concurrency on the macOS 13/14 CI legs).
    @MainActor
    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .smartScan:
            ScanDashboardView(viewModel: models.scan)
        case .apps:
            AppManagerView(viewModel: models.apps)
        case .homebrew:
            HomebrewManagerView(viewModel: models.homebrew)
        case .disk:
            DiskAnalyzerView(viewModel: models.disk)
        case .maintenance:
            MaintenanceView(viewModel: models.maintenance)
        case .history:
            HistoryView(viewModel: models.history)
        case .settings:
            SettingsView()
        }
    }
}
