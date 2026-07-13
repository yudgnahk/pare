import SwiftUI

@main
struct PareApp: App {
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
        }
    }
}

struct ContentView: View {
    @ObservedObject var scanViewModel: ScanDashboardViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @State private var selection: AppDestination = .smartScan

    var body: some View {
        DisplayScaleReader {
            // Fixed sidebar (not NavigationSplitView) so the left menu is always
            // visible — SplitView collapses/hides the sidebar too easily on macOS.
            HStack(spacing: 0) {
                SidebarView(selection: $selection)
                    .frame(width: AppTheme.Spacing.sidebarWidth)
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
            // Content paints under traffic lights (hidden title bar).
            .ignoresSafeArea()
        }
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
