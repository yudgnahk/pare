import SwiftUI

/// Plain button style with a gentle press-down scale, so custom CTAs feel physical.
struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(AppTheme.Motion.quick, value: configuration.isPressed)
    }
}
