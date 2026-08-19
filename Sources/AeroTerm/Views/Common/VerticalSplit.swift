import SwiftUI

struct VerticalSplit<Top: View, Bottom: View>: View {
    @Binding var ratio: Double
    @State private var dragOrigin: Double?
    let top: Top
    let bottom: Bottom

    init(ratio: Binding<Double>, @ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        _ratio = ratio
        self.top = top()
        self.bottom = bottom()
    }

    var body: some View {
        GeometryReader { geo in
            let handle = WorkspaceSplitMetrics.handle
            let usable = max(geo.size.height - handle, 1)
            let clamped = PaneNode.clampRatio(ratio)
            let topHeight = usable * clamped
            VStack(spacing: 0) {
                top
                    .frame(width: geo.size.width, height: topHeight)
                    .clipped()
                sash
                    .frame(width: geo.size.width, height: handle)
                    .gesture(drag(in: usable))
                bottom
                    .frame(width: geo.size.width, height: max(usable - topHeight, 0))
                    .clipped()
            }
        }
    }

    private var sash: some View {
        ZStack {
            Color(NSColor.separatorColor).opacity(0.35)
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func drag(in usable: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = ratio
                }
                let next = (usable * (dragOrigin ?? ratio) + value.translation.height) / max(usable, 1)
                ratio = PaneNode.clampRatio(next)
            }
            .onEnded { _ in
                dragOrigin = nil
            }
    }
}
