import SwiftUI

/// Three-phase scan stepper rendered as pills: done, active, pending.
struct ScanStepChips: View {
    let activeStep: Int

    @Environment(\.pareDisplayScale) private var scale

    private static let steps: [(icon: String, label: String)] = [
        ("internaldrive.fill", "System"),
        ("globe", "Apps & browsers"),
        ("chevron.left.forwardslash.chevron.right", "Developer")
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                chip(number: index + 1, icon: step.icon, label: step.label)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(activeStep) of \(Self.steps.count)")
    }

    private func chip(number: Int, icon: String, label: String) -> some View {
        let done = activeStep > number
        let active = activeStep == number
        return HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : icon)
                .font(scale.font(12, weight: .semibold))
            Text(label)
                .font(scale.font(12, weight: active ? .semibold : .medium))
                .lineLimit(1)
        }
        .foregroundStyle(done || active ? AppTheme.accentText : AppTheme.textTertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(active ? AppTheme.accent.opacity(0.16) : AppTheme.Fill.subtle)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(active ? AppTheme.accent.opacity(0.35) : AppTheme.Hairline.standard, lineWidth: 1)
        )
        .motionAwareAnimation(AppTheme.Motion.standard, value: activeStep)
    }
}

/// Quiet reassurance pill ("Trash first, never erased").
struct TrustChip: View {
    let icon: String
    let text: String

    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(scale.font(11, weight: .semibold))
                .foregroundStyle(AppTheme.accentText)
            Text(text)
                .font(scale.font(12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(AppTheme.cardFill, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(AppTheme.Hairline.standard, lineWidth: 1))
    }
}

/// Legend swatch + label + value, used under disk rings.
struct LegendDot: View {
    let color: Color
    let label: String
    let value: String

    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(value)
                .font(scale.font(12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
            Text(label)
                .font(scale.font(12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
