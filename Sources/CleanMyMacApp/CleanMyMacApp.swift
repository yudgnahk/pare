import SwiftUI

@main
struct CleanMyMacApp: App {
    @StateObject private var viewModel = ScanDashboardViewModel()

    var body: some Scene {
        WindowGroup("Clean My Mac") {
            ScanDashboardView(viewModel: viewModel)
                .frame(minWidth: 1024, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 780)
    }
}
