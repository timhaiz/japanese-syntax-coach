import SwiftUI

struct WordTokenFlowLayout: Layout {
    private let spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width ?? 0)
        let layout = positions(subviews: subviews, width: width)
        return CGSize(width: width, height: layout.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = positions(subviews: subviews, width: bounds.width)
        for (index, point) in layout.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), anchor: .topLeading,
                                  proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }

    private func positions(subviews: Subviews, width: CGFloat) -> (points: [CGPoint], height: CGFloat) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (points, y + rowHeight)
    }
}
