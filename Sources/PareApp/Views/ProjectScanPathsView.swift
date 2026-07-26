import SwiftUI
import AppKit
import PareCore

// MARK: - ProjectScanPathsView

struct ProjectScanPathsView: View {
    @StateObject private var viewModel = ProjectScanPathsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackgroundView()

            VStack(spacing: 0) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project Scan Paths")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Pare looks for local build caches (.cache, .next, dist, target, …) inside these directories. Dependency trees like node_modules and .venv are never marked reclaimable.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

                // Add button row
                HStack {
                    Button(action: viewModel.addPath) {
                        Label("Add Folder…", systemImage: "folder.badge.plus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

                Divider().opacity(0.15)

                if viewModel.paths.isEmpty {
                    EmptyStateView(
                        icon: "folder.badge.questionmark",
                        title: "No project paths yet",
                        message: "Add your ~/Projects folder to automatically\ndetect build artifacts in future scans."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.paths, id: \.self) { path in
                                pathRow(path)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .frame(width: 520, height: 420)
    }

    private func pathRow(_ path: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 18)

            Text(path)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button(role: .destructive) {
                viewModel.removePath(path)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .buttonStyle(.borderless)
            .help("Remove from scan paths")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - ProjectScanPathsViewModel

@MainActor
private final class ProjectScanPathsViewModel: ObservableObject {
    @Published private(set) var paths: [String] = []

    private let store = ProjectScanPathStore.shared

    init() {
        paths = store.paths
    }

    func addPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project root directory to scan for build artifacts"
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.add(url.path)
        paths = store.paths
    }

    func removePath(_ path: String) {
        store.remove(path)
        paths = store.paths
    }
}
