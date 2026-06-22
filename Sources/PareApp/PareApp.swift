import SwiftUI

@main
struct PareApp: App {
    @StateObject private var scanViewModel = ScanDashboardViewModel()
    @StateObject private var historyViewModel = HistoryViewModel()

    var body: some Scene {
        WindowGroup("Pare") {
            ContentView(scanViewModel: scanViewModel, historyViewModel: historyViewModel)
                .frame(minWidth: 1024, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 780)
    }
}

struct ContentView: View {
    @ObservedObject var scanViewModel: ScanDashboardViewModel
    @ObservedObject var historyViewModel: HistoryViewModel

    var body: some View {
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

            HistoryView(viewModel: historyViewModel)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
    }
}
