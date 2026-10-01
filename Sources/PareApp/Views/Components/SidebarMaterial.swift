import SwiftUI
import AppKit

/// Native sidebar vibrancy; falls back to opaque automatically when Reduce Transparency is on.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

#if DEBUG
struct SidebarMaterial_Previews: PreviewProvider {
    static var previews: some View {
        SidebarMaterial()
            .frame(width: 220, height: 400)
    }
}
#endif
