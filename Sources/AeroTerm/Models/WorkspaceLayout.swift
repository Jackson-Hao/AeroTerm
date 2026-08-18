import Foundation
import CoreGraphics

public enum WorkspaceSplitMetrics {
    public static let handle: CGFloat = 5
    public static let headerHeight: CGFloat = 32
}

public enum SplitAxis: String, Equatable, Sendable {
    case horizontal
    case vertical
}

public enum DropEdge: String, Equatable, Sendable {
    case leading
    case trailing
    case top
    case bottom
    case center
}

public struct PendingDropPlacement: Equatable, Sendable {
    public var surfaceID: UUID
    public var nodeID: UUID
    public var edge: DropEdge
}

public enum WorkspaceWindowCommand: Equatable, Sendable {
    case open(UUID)
    case close(UUID)
    case focus(UUID)
}

public struct WorkspaceSurface: Identifiable, Equatable, Sendable {
    public static let primaryID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    public let id: UUID
    public var layout: PaneNode?
    public var isPrimary: Bool
    public var focusedNodeID: UUID?

    public init(
        id: UUID = UUID(),
        layout: PaneNode? = nil,
        isPrimary: Bool = false,
        focusedNodeID: UUID? = nil
    ) {
        self.id = id
        self.layout = layout
        self.isPrimary = isPrimary
        self.focusedNodeID = focusedNodeID
    }

    public static func makePrimary() -> WorkspaceSurface {
        WorkspaceSurface(id: primaryID, layout: nil, isPrimary: true, focusedNodeID: nil)
    }

    public var sessionIDs: [UUID] {
        layout?.sessionIDs ?? []
    }

    public func contains(sessionID: UUID) -> Bool {
        layout?.contains(sessionID: sessionID) == true
    }

    public mutating func pruneFocusedNode() {
        guard let focusedNodeID else { return }
        if layout?.contains(nodeID: focusedNodeID) != true {
            self.focusedNodeID = layout?.firstLeafNodeID()
        }
    }
}

public indirect enum PaneNode: Identifiable, Equatable, Sendable {
    case leaf(id: UUID, sessionID: UUID?)
    case split(id: UUID, axis: SplitAxis, first: PaneNode, second: PaneNode, ratio: Double)

    public var id: UUID {
        switch self {
        case .leaf(let id, _):
            return id
        case .split(let id, _, _, _, _):
            return id
        }
    }

    public var sessionIDs: [UUID] {
        switch self {
        case .leaf(_, let sessionID):
            return sessionID.map { [$0] } ?? []
        case .split(_, _, let first, let second, _):
            return first.sessionIDs + second.sessionIDs
        }
    }

    public func contains(sessionID: UUID) -> Bool {
        sessionIDs.contains(sessionID)
    }

    public func contains(nodeID: UUID) -> Bool {
        if id == nodeID { return true }
        switch self {
        case .leaf:
            return false
        case .split(_, _, let first, let second, _):
            return first.contains(nodeID: nodeID) || second.contains(nodeID: nodeID)
        }
    }

    public func nodeID(for sessionID: UUID) -> UUID? {
        switch self {
        case .leaf(let id, let sid):
            return sid == sessionID ? id : nil
        case .split(_, _, let first, let second, _):
            return first.nodeID(for: sessionID) ?? second.nodeID(for: sessionID)
        }
    }

    public func sessionID(for nodeID: UUID) -> UUID? {
        switch self {
        case .leaf(let id, let sid):
            return id == nodeID ? sid : nil
        case .split(_, _, let first, let second, _):
            return first.sessionID(for: nodeID) ?? second.sessionID(for: nodeID)
        }
    }

    public func firstLeafNodeID() -> UUID? {
        switch self {
        case .leaf(let id, _):
            return id
        case .split(_, _, let first, _, _):
            return first.firstLeafNodeID()
        }
    }

    public var leaves: [(id: UUID, sessionID: UUID?)] {
        switch self {
        case .leaf(let id, let sessionID):
            return [(id, sessionID)]
        case .split(_, _, let first, let second, _):
            return first.leaves + second.leaves
        }
    }

    /// Frames are in a top-left origin space (flipped), matching SwiftUI / a flipped NSView.
    public func leafFrames(
        in bounds: CGRect,
        handle: CGFloat = WorkspaceSplitMetrics.handle,
        ratioOverrides: [UUID: Double] = [:]
    ) -> [(id: UUID, sessionID: UUID?, frame: CGRect)] {
        switch self {
        case .leaf(let id, let sessionID):
            return [(id, sessionID, bounds)]
        case .split(let id, let axis, let first, let second, let ratio):
            let regions = splitRegions(
                in: bounds,
                axis: axis,
                ratio: ratioOverrides[id] ?? ratio,
                handle: handle
            )
            return first.leafFrames(in: regions.first, handle: handle, ratioOverrides: ratioOverrides)
                + second.leafFrames(in: regions.second, handle: handle, ratioOverrides: ratioOverrides)
        }
    }

    public func splitSashes(
        in bounds: CGRect,
        handle: CGFloat = WorkspaceSplitMetrics.handle,
        ratioOverrides: [UUID: Double] = [:]
    ) -> [(id: UUID, axis: SplitAxis, frame: CGRect, span: CGFloat)] {
        switch self {
        case .leaf:
            return []
        case .split(let id, let axis, let first, let second, let ratio):
            let regions = splitRegions(
                in: bounds,
                axis: axis,
                ratio: ratioOverrides[id] ?? ratio,
                handle: handle
            )
            return [(id, axis, regions.sash, regions.span)]
                + first.splitSashes(in: regions.first, handle: handle, ratioOverrides: ratioOverrides)
                + second.splitSashes(in: regions.second, handle: handle, ratioOverrides: ratioOverrides)
        }
    }

    private func splitRegions(
        in bounds: CGRect,
        axis: SplitAxis,
        ratio: Double,
        handle: CGFloat
    ) -> (first: CGRect, second: CGRect, sash: CGRect, span: CGFloat) {
        let clamped = CGFloat(Self.clampRatio(ratio))
        if axis == .horizontal {
            let span = bounds.width
            let usable = max(span - handle, 1)
            let firstWidth = usable * clamped
            let first = CGRect(x: bounds.minX, y: bounds.minY, width: firstWidth, height: bounds.height)
            let sash = CGRect(x: bounds.minX + firstWidth, y: bounds.minY, width: handle, height: bounds.height)
            let second = CGRect(
                x: sash.maxX,
                y: bounds.minY,
                width: max(usable - firstWidth, 0),
                height: bounds.height
            )
            return (first, second, sash, span)
        }
        let span = bounds.height
        let usable = max(span - handle, 1)
        let firstHeight = usable * clamped
        let first = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: firstHeight)
        let sash = CGRect(x: bounds.minX, y: bounds.minY + firstHeight, width: bounds.width, height: handle)
        let second = CGRect(
            x: bounds.minX,
            y: sash.maxY,
            width: bounds.width,
            height: max(usable - firstHeight, 0)
        )
        return (first, second, sash, span)
    }

    public static func dropEdge(at point: CGPoint, in frame: CGRect) -> DropEdge {
        let width = max(frame.width, 1)
        let height = max(frame.height, 1)
        let x = (point.x - frame.minX) / width
        let y = (point.y - frame.minY) / height
        let left = x
        let right = 1 - x
        let top = y
        let bottom = 1 - y
        let band: CGFloat = 0.32
        let nearestHorizontal = min(left, right)
        let nearestVertical = min(top, bottom)
        if nearestHorizontal > band && nearestVertical > band {
            return .center
        }
        if nearestHorizontal <= nearestVertical {
            return left < right ? .leading : .trailing
        }
        return top < bottom ? .top : .bottom
    }

    public static func highlightRect(for edge: DropEdge, in frame: CGRect) -> CGRect {
        switch edge {
        case .center:
            return frame
        case .leading:
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width * 0.5, height: frame.height)
        case .trailing:
            return CGRect(x: frame.midX, y: frame.minY, width: frame.width * 0.5, height: frame.height)
        case .top:
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height * 0.5)
        case .bottom:
            return CGRect(x: frame.minX, y: frame.midY, width: frame.width, height: frame.height * 0.5)
        }
    }

    public func removing(sessionID: UUID) -> PaneNode? {
        switch self {
        case .leaf(_, let sid):
            return sid == sessionID ? nil : self
        case .split(let id, let axis, let first, let second, let ratio):
            return collapsed(
                id: id,
                axis: axis,
                first: first.removing(sessionID: sessionID),
                second: second.removing(sessionID: sessionID),
                ratio: ratio
            )
        }
    }

    public func removing(nodeID: UUID) -> PaneNode? {
        if id == nodeID { return nil }
        switch self {
        case .leaf:
            return self
        case .split(let id, let axis, let first, let second, let ratio):
            return collapsed(
                id: id,
                axis: axis,
                first: first.removing(nodeID: nodeID),
                second: second.removing(nodeID: nodeID),
                ratio: ratio
            )
        }
    }

    public func settingRatio(nodeID: UUID, ratio: Double) -> PaneNode {
        let clamped = Self.clampRatio(ratio)
        switch self {
        case .leaf:
            return self
        case .split(let id, let axis, let first, let second, let current):
            if id == nodeID {
                return .split(id: id, axis: axis, first: first, second: second, ratio: clamped)
            }
            return .split(
                id: id,
                axis: axis,
                first: first.settingRatio(nodeID: nodeID, ratio: clamped),
                second: second.settingRatio(nodeID: nodeID, ratio: clamped),
                ratio: current
            )
        }
    }

    public func replacingLeaf(nodeID: UUID, sessionID: UUID?) -> PaneNode {
        switch self {
        case .leaf(let id, _):
            return id == nodeID ? .leaf(id: id, sessionID: sessionID) : self
        case .split(let id, let axis, let first, let second, let ratio):
            return .split(
                id: id,
                axis: axis,
                first: first.replacingLeaf(nodeID: nodeID, sessionID: sessionID),
                second: second.replacingLeaf(nodeID: nodeID, sessionID: sessionID),
                ratio: ratio
            )
        }
    }

    public func splitting(nodeID: UUID, axis: SplitAxis, newSessionID: UUID?) -> PaneNode {
        if id == nodeID {
            let extra = PaneNode.leaf(id: UUID(), sessionID: newSessionID)
            return .split(id: UUID(), axis: axis, first: self, second: extra, ratio: 0.5)
        }
        switch self {
        case .leaf:
            return self
        case .split(let id, let currentAxis, let first, let second, let ratio):
            return .split(
                id: id,
                axis: currentAxis,
                first: first.splitting(nodeID: nodeID, axis: axis, newSessionID: newSessionID),
                second: second.splitting(nodeID: nodeID, axis: axis, newSessionID: newSessionID),
                ratio: ratio
            )
        }
    }

    public func placing(sessionID: UUID, on targetNodeID: UUID, edge: DropEdge) -> PaneNode {
        inserting(sessionID: sessionID, leafID: UUID(), on: targetNodeID, edge: edge)
    }

    public func inserting(sessionID: UUID?, leafID: UUID, on targetNodeID: UUID, edge: DropEdge) -> PaneNode {
        if id == targetNodeID {
            return placingOnSelf(sessionID: sessionID, leafID: leafID, edge: edge)
        }
        switch self {
        case .leaf:
            return self
        case .split(let id, let axis, let first, let second, let ratio):
            return .split(
                id: id,
                axis: axis,
                first: first.inserting(sessionID: sessionID, leafID: leafID, on: targetNodeID, edge: edge),
                second: second.inserting(sessionID: sessionID, leafID: leafID, on: targetNodeID, edge: edge),
                ratio: ratio
            )
        }
    }

    public static func clampRatio(_ ratio: Double) -> Double {
        min(0.82, max(0.18, ratio))
    }

    private func placingOnSelf(sessionID: UUID?, leafID: UUID, edge: DropEdge) -> PaneNode {
        switch edge {
        case .center:
            switch self {
            case .leaf(let id, _):
                return .leaf(id: id, sessionID: sessionID)
            case .split:
                return self
            }
        case .leading, .trailing, .top, .bottom:
            let axis: SplitAxis = (edge == .leading || edge == .trailing) ? .horizontal : .vertical
            let incoming = PaneNode.leaf(id: leafID, sessionID: sessionID)
            let incomingFirst = (edge == .leading || edge == .top)
            return .split(
                id: UUID(),
                axis: axis,
                first: incomingFirst ? incoming : self,
                second: incomingFirst ? self : incoming,
                ratio: 0.5
            )
        }
    }

    private func collapsed(
        id: UUID,
        axis: SplitAxis,
        first: PaneNode?,
        second: PaneNode?,
        ratio: Double
    ) -> PaneNode? {
        switch (first, second) {
        case (nil, nil):
            return nil
        case (let only?, nil):
            return only
        case (nil, let only?):
            return only
        case (let first?, let second?):
            return .split(id: id, axis: axis, first: first, second: second, ratio: ratio)
        }
    }
}
