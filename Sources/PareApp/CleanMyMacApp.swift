import SwiftUI

@main
struct PareApp: App {
    @StateObject private var scanViewModel = ScanDashboardViewModel()
    @StateObject private var historyViewModel = HistoryViewModel()

    var body: some Scene {
        WindowGroup("Pare") {
            ContentView(scanViewModel: scanViewModel, historyViewModel: historyViewModel)
                // Declare a floor that fits 13" MacBooks; content expands to full screen.
                .frame(
                    minWidth: AppTheme.Window.minWidth,
                    maxWidth: .infinity,
                    minHeight: AppTheme.Window.minHeight,
                    maxHeight: .infinity
                )
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: AppTheme.Window.defaultWidth, height: AppTheme.Window.defaultHeight)
    }
}

struct ContentView: View {
    @ObservedObject var scanViewModel: ScanDashboardViewModel
    @ObservedObject var historyViewModel: HistoryViewModel

    var body: some View {
        DisplayScaleReader {
            TabView {
                ScanDashboardView(viewModel: scanViewModel)
                    .tabItem {
                        Label("Scan", systemImage: "magnifyingglass")
                    }

                AppManagerView()
                    .tabItem {
                        Label("Apps", systemImage: "apps.iphone")
                    }

                HomebrewManagerView()
                    .tabItem {
                        Label("Homebrew", systemImage: "shippingbox")
                    }

                DiskAnalyzerView()
                    .tabItem {
                        Label("Disk", systemImage: "externaldrive.badge.magnifyingglass")
                    }

                MaintenanceView()
                    .tabItem {
                        Label("Maintenance", systemImage: "wrench.and.screwdriver")
                    }

                HistoryView(viewModel: historyViewModel)
                    .tabItem {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
