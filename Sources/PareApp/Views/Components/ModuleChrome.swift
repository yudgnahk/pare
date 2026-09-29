import SwiftUI

/// Page scaffold for secondary modules: shared `PageHeader`, then content filling the rest.
struct ModuleChrome<Actions: View, Content: View>: View {
    let destination: AppDestination
    var title: String? = nil
    var subtitle: String? = nil
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(destination: destination, title: title, subtitle: subtitle, actions: actions)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension ModuleChrome where Actions == EmptyView {
    init(
        destination: AppDestination,
        title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(destination: destination, title: title, subtitle: subtitle, actions: { EmptyView() }, content: content)
    }
}
