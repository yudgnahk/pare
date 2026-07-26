import AppKit
import SwiftUI

@main
struct PareApp: App {
    @NSApplicationDelegateAdaptor(PareAppDelegate.self) private var appDelegate
    @StateObject private var scanViewModel = ScanDashboardViewModel()
    @StateObject private var historyViewModel = HistoryViewModel()
    @StateObject private var textZoom = TextZoomController()

    var body: some Scene {
        WindowGroup("Pare") {
            ContentView(scanViewModel: scanViewModel, historyViewModel: historyViewModel)
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
            DiagnosticsExportCommands(scanViewModel: scanViewModel)
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
    @ObservedObject var scanViewModel: ScanDashboardViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @State private var selection: AppDestination = .smartScan

    var body: some View {
        DisplayScaleReader {
            // Environment (displayScale) is applied inside the reader.
            MainShellView(
                selection: $selection,
                scanViewModel: scanViewModel,
                historyViewModel: historyViewModel
            )
        }
    }
}

/// Shell that reads `displayScale` from the environment (inside DisplayScaleReader).
private struct MainShellView: View {
    @Binding var selection: AppDestination
    @ObservedObject var scanViewModel: ScanDashboardViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
                .frame(width: max(200, AppTheme.Spacing.sidebarWidth * scale.spacingFactor))
                .frame(maxHeight: .infinity)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            ZStack {
                AppBackgroundView()
                detailContent
                    .id(selection)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .smartScan:
            ScanDashboardView(viewModel: scanViewModel)
        case .apps:
            AppManagerView()
        case .homebrew:
            HomebrewManagerView()
        case .disk:
            DiskAnalyzerView()
        case .maintenance:
            MaintenanceView()
        case .history:
            HistoryView(viewModel: historyViewModel)
        case .settings:
            SettingsView()
        }
    }
}
