import SwiftUI

/// Simple left-to-right wrapping layout for action toolbars.
/// Prefer this over a fixed `HStack` when button counts change at runtime
/// (e.g. Scan / Quick Clean / Deep Clean appearing after a successful scan).
struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 10
    var alignment: HorizontalAlignment = .trailing

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            let origin = CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY)
            subviews[index].place(at: origin, proposal: ProposedViewSize(frame.size))
        }
    }

    private struct Arrangement {
        var size: CGSize
        var frames: [CGRect]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> Arrangement {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var lineStart = 0
        var totalWidth: CGFloat = 0

        func flushLine(endIndex: Int, lineWidth: CGFloat) {
            guard lineStart < endIndex else { return }
            let extra: CGFloat
            if maxWidth.isFinite, maxWidth < .greatestFiniteMagnitude {
                if alignment == .trailing {
                    extra = max(0, maxWidth - lineWidth)
                } else if alignment == .center {
                    extra = max(0, (maxWidth - lineWidth) / 2)
                } else {
                    extra = 0
                }
            } else {
                extra = 0
            }
            if extra > 0 {
                for i in lineStart..<endIndex {
                    frames[i].origin.x += extra
                }
            }
        }

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > maxWidth {
                flushLine(endIndex: index, lineWidth: currentX - spacing)
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
                lineStart = index
            }

            frames.append(CGRect(origin: CGPoint(x: currentX, y: currentY), size: size))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX - spacing)
        }

        flushLine(endIndex: subviews.count, lineWidth: max(0, currentX - spacing))

        let height = currentY + lineHeight
        let width = maxWidth.isFinite ? min(maxWidth, max(totalWidth, 0)) : totalWidth
        return Arrangement(size: CGSize(width: width, height: height), frames: frames)
    }
}
