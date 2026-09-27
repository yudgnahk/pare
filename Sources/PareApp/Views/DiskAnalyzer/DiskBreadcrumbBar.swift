import SwiftUI
import PareCore

/// Clickable crumb trail for the current Disk Analyzer level, with a back
/// chevron and the level's total size on the trailing edge.
struct DiskBreadcrumbBar: View {
    let crumbs: [DiskBreadcrumb.Crumb]
    let canGoUp: Bool
    let totalLabel: String
    let onSelect: (DiskBreadcrumb.Crumb) -> Void
    let onGoUp: () -> Void
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        HStack(spacing: 8) {
            IconActionButton(systemImage: "chevron.up", help: "Up one level", isEnabled: canGoUp, action: onGoUp)

            IconTile(symbol: "folder.fill", swatch: AppTheme.Swatch.accent, size: 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, crumb in
                        crumbButton(crumb, isLast: index == crumbs.count - 1, isFirst: index == 0)
                    }
                }
            }

            Spacer(minLength: 8)

            Text(totalLabel)
                .font(scale.font(13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }

    @ViewBuilder
    private func crumbButton(_ crumb: DiskBreadcrumb.Crumb, isLast: Bool, isFirst: Bool) -> some View {
        if !isFirst {
            Image(systemName: "chevron.right")
                .font(scale.font(10, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
        }
        Button { onSelect(crumb) } label: {
            Text(crumb.name)
                .font(scale.caption)
                .foregroundStyle(isLast ? AppTheme.textPrimary : AppTheme.textSecondary)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .disabled(isLast)
    }
}

#if DEBUG
private enum DiskBreadcrumbBarPreviewData {
    static var crumbs: [DiskBreadcrumb.Crumb] {
        let root = URL(fileURLWithPath: "/Users/k")
        let library = root.appendingPathComponent("Library")
        let caches = library.appendingPathComponent("Caches")
        return [
            .init(id: root.path, url: root, name: root.lastPathComponent),
            .init(id: library.path, url: library, name: library.lastPathComponent),
            .init(id: caches.path, url: caches, name: caches.lastPathComponent)
        ]
    }
}

struct DiskBreadcrumbBar_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            bar.environment(\.colorScheme, .light).background(AppTheme.base).previewDisplayName("Light")
            bar.environment(\.colorScheme, .dark).background(AppTheme.base).previewDisplayName("Dark")
        }
    }

    static var bar: some View {
        DiskBreadcrumbBar(
            crumbs: DiskBreadcrumbBarPreviewData.crumbs,
            canGoUp: true,
            totalLabel: "14.9 GB",
            onSelect: { _ in },
            onGoUp: {}
        )
        .padding(24)
    }
}
#endif
