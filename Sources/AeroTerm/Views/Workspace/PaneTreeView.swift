import SwiftUI

public struct PaneTreeView: View {
    let node: PaneNode
    let surfaceID: UUID
    var showsHeaderWhenSingle: Bool = true

    public var body: some View {
        WorkspaceTilingView(
            layout: node,
            surfaceID: surfaceID,
            showsHeaderWhenSingle: showsHeaderWhenSingle
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { $0.animation = nil }
    }
}
