import SwiftUI

/// Pinned chrome + vertical-only list scroll.
///
/// Dual-axis `ScrollView([.vertical, .horizontal])` is unstable on macOS:
/// content origin jumps when the data set changes (filters) or when the
/// parent chrome reflows. This container keeps the column header fixed and
/// resets vertical offset when `resetToken` changes.
struct StableListContainer<Header: View, Content: View>: View {
    /// Change this when filters / sort / tab selection change so the list
    /// jumps back to a predictable top position instead of mid-list.
    let resetToken: AnyHashable
    var horizontalPadding: CGFloat = AppTheme.Spacing.pageHorizontal
    var bottomPadding: CGFloat = AppTheme.Spacing.pageVertical

    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header()
                .padding(.horizontal, horizontalPadding)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 2, pinnedViews: []) {
                        // Anchor for filter-driven scroll resets.
                        Color.clear
                            .frame(height: 0)
                            .id(listTopID)

                        content()
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, bottomPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: resetToken) { _ in
                    // No animation — avoids bounce when filters toggle.
                    proxy.scrollTo(listTopID, anchor: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var listTopID: String { "stable-list-top" }
}
