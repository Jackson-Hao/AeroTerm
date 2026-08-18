import SwiftUI
import AppKit

/// Hosts a pane inside the tiling view without inheriting the window titlebar
/// safe area (that inset is what produced the gray mask and shifted UI).
final class FillHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureForTiling()
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    override var preservesContentDuringLiveResize: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureForTiling()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureForTiling()
    }

    func configureForTiling() {
        sizingOptions = []
        safeAreaRegions = []
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = []
        clipsToBounds = true
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.masksToBounds = true
        layer?.backgroundColor = TerminalAppearance.backgroundColor.cgColor
        layer?.actions = [
            "bounds": NSNull(),
            "frame": NSNull(),
            "position": NSNull(),
            "contents": NSNull()
        ]
        setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        setContentHuggingPriority(.fittingSizeCompression, for: .vertical)
        setContentCompressionResistancePriority(.fittingSizeCompression, for: .horizontal)
        setContentCompressionResistancePriority(.fittingSizeCompression, for: .vertical)
    }

    func install(_ rootView: Content) {
        self.rootView = rootView
        configureForTiling()
    }

    override func setFrameSize(_ newSize: NSSize) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.setFrameSize(newSize)
        CATransaction.commit()
    }
}

/// One leaf: AppKit-owned header strip + separate content host.
/// Terminals live only in the body, so they cannot cover or compress the close button.
@MainActor
final class PaneSlotView: NSView {
    let nodeID: UUID
    private let headerHost: FillHostingView<SessionPaneHeaderView>
    private let bodyHost: FillHostingView<SessionPaneBodyView>

    private(set) var surfaceID: UUID
    private(set) var sessionID: UUID?
    private(set) var showsHeader: Bool

    init(nodeID: UUID, surfaceID: UUID, sessionID: UUID?, showsHeader: Bool) {
        self.nodeID = nodeID
        self.surfaceID = surfaceID
        self.sessionID = sessionID
        self.showsHeader = showsHeader
        headerHost = FillHostingView(rootView: SessionPaneHeaderView(
            nodeID: nodeID,
            surfaceID: surfaceID,
            sessionID: sessionID
        ))
        bodyHost = FillHostingView(rootView: SessionPaneBodyView(
            nodeID: nodeID,
            surfaceID: surfaceID,
            sessionID: sessionID
        ))
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.actions = [
            "bounds": NSNull(),
            "frame": NSNull(),
            "position": NSNull(),
            "contents": NSNull()
        ]
        clipsToBounds = true
        headerHost.autoresizingMask = [.width]
        bodyHost.autoresizingMask = [.width, .height]
        addSubview(bodyHost)
        addSubview(headerHost)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }
    override var preservesContentDuringLiveResize: Bool { true }

    func apply(surfaceID: UUID, sessionID: UUID?, showsHeader: Bool) {
        let headerChanged = self.surfaceID != surfaceID || self.sessionID != sessionID
        let bodyChanged = headerChanged
        self.surfaceID = surfaceID
        self.sessionID = sessionID
        self.showsHeader = showsHeader
        if headerChanged {
            headerHost.install(SessionPaneHeaderView(
                nodeID: nodeID,
                surfaceID: surfaceID,
                sessionID: sessionID
            ))
        }
        if bodyChanged {
            bodyHost.install(SessionPaneBodyView(
                nodeID: nodeID,
                surfaceID: surfaceID,
                sessionID: sessionID
            ))
        }
        applyChromeFrames()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        if oldSize == .zero || headerHost.isHidden == showsHeader {
            applyChromeFrames()
        } else {
            super.resizeSubviews(withOldSize: oldSize)
        }
    }

    override func layout() {
        super.layout()
        if headerHost.isHidden == showsHeader || headerHost.frame.width != bounds.width {
            applyChromeFrames()
        }
    }

    private func applyChromeFrames() {
        let headerHeight = showsHeader ? WorkspaceSplitMetrics.headerHeight : 0
        headerHost.isHidden = !showsHeader
        headerHost.autoresizingMask = [.width]
        bodyHost.autoresizingMask = [.width, .height]
        let nextHeader = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        let nextBody = CGRect(
            x: 0,
            y: headerHeight,
            width: bounds.width,
            height: max(0, bounds.height - headerHeight)
        )
        if headerHost.frame != nextHeader {
            headerHost.frame = nextHeader
        }
        if bodyHost.frame != nextBody {
            bodyHost.frame = nextBody
        }
    }
}

struct WorkspaceTilingView: NSViewRepresentable {
    var layout: PaneNode
    var surfaceID: UUID
    var showsHeaderWhenSingle: Bool

    func makeNSView(context: Context) -> WorkspaceTilingNSView {
        let view = WorkspaceTilingNSView(frame: .zero)
        view.surfaceID = surfaceID
        view.showsHeaderWhenSingle = showsHeaderWhenSingle
        view.apply(layout: layout)
        return view
    }

    func updateNSView(_ view: WorkspaceTilingNSView, context: Context) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            view.surfaceID = surfaceID
            view.showsHeaderWhenSingle = showsHeaderWhenSingle
            view.apply(layout: layout)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WorkspaceTilingNSView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite, width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }
}

@MainActor
final class WorkspaceTilingNSView: NSView {
    var surfaceID: UUID = WorkspaceSurface.primaryID
    var showsHeaderWhenSingle = true

    private var layoutTree: PaneNode?
    private var hosts: [UUID: PaneSlotView] = [:]
    private var sashes: [UUID: SplitSashView] = [:]
    private let catcher = WorkspaceDropCatcherView(frame: .zero)

    private var liveRatios: [UUID: Double] = [:]
    private var applyingFrames = false

    private var dragSplitID: UUID?
    private var dragAxis: SplitAxis?
    private var dragStartPoint: CGPoint = .zero
    private var dragStartRatio: Double = 0.5
    private var dragSpan: CGFloat = 1

    var isDraggingSash: Bool { dragSplitID != nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.masksToBounds = true
        layer?.actions = [
            "bounds": NSNull(),
            "frame": NSNull(),
            "position": NSNull(),
            "contents": NSNull()
        ]
        clipsToBounds = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.width, .height]
        catcher.locksFrameToSuperview = false
        catcher.autoresizingMask = []
        addSubview(catcher)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var preservesContentDuringLiveResize: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyFrames()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        applyFrames()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let sizeChanged = newSize != bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.setFrameSize(newSize)
        if sizeChanged {
            applyFrames()
        }
        CATransaction.commit()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        // Child frames are assigned in applyFrames(), not by autoresizing.
    }

    func relayoutNow() {
        applyFrames()
    }

    static func relayoutAll(in window: NSWindow) {
        func walk(_ view: NSView) {
            if let tiling = view as? WorkspaceTilingNSView {
                tiling.relayoutNow()
            }
            view.subviews.forEach(walk)
        }
        if let root = window.contentView {
            walk(root)
        }
    }

    func apply(layout: PaneNode) {
        let previous = layoutTree
        layoutTree = layout
        catcher.surfaceID = surfaceID
        if previous == nil || needsChildSync(from: previous!, to: layout) {
            syncChildren()
            applyFrames()
            return
        }
        if previous != layout {
            applyFrames()
        }
    }

    private func needsChildSync(from old: PaneNode, to new: PaneNode) -> Bool {
        let oldLeaves = old.leaves
        let newLeaves = new.leaves
        if oldLeaves.map(\.id) != newLeaves.map(\.id) { return true }
        if oldLeaves.map(\.sessionID) != newLeaves.map(\.sessionID) { return true }
        let oldHeader = showsHeaderWhenSingle || oldLeaves.count > 1
        let newHeader = showsHeaderWhenSingle || newLeaves.count > 1
        return oldHeader != newHeader
    }

    func beginSashDrag(splitID: UUID, axis: SplitAxis, event: NSEvent) {
        guard let sash = layoutTree?.splitSashes(in: bounds, ratioOverrides: liveRatios)
            .first(where: { $0.id == splitID })
        else { return }
        dragSplitID = splitID
        dragAxis = axis
        dragStartPoint = convert(event.locationInWindow, from: nil)
        dragStartRatio = liveRatios[splitID] ?? currentRatio(for: splitID) ?? 0.5
        dragSpan = sash.span
        window?.disableCursorRects()
        (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
    }

    func continueSashDrag(event: NSEvent) {
        guard let splitID = dragSplitID, let axis = dragAxis else { return }
        let point = convert(event.locationInWindow, from: nil)
        let delta = axis == .horizontal ? point.x - dragStartPoint.x : point.y - dragStartPoint.y
        let usable = max(dragSpan - WorkspaceSplitMetrics.handle, 1)
        let next = PaneNode.clampRatio(dragStartRatio + Double(delta / usable))
        liveRatios[splitID] = next
        applyFrames()
        (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
    }

    func endSashDrag() {
        if let splitID = dragSplitID, let ratio = liveRatios[splitID] {
            layoutTree = layoutTree?.settingRatio(nodeID: splitID, ratio: ratio)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                SessionManager.shared.setSplitRatio(nodeID: splitID, surfaceID: surfaceID, ratio: ratio)
            }
        }
        dragSplitID = nil
        dragAxis = nil
        liveRatios.removeAll()
        window?.enableCursorRects()
        window?.invalidateCursorRects(for: self)
        applyFrames()
    }

    private func syncChildren() {
        guard let layoutTree else { return }
        let leaves = layoutTree.leaves
        let leafIDs = Set(leaves.map(\.id))
        let showHeader = showsHeaderWhenSingle || leaves.count > 1

        for (id, host) in hosts where !leafIDs.contains(id) {
            host.removeFromSuperview()
            hosts[id] = nil
        }

        for leaf in leaves {
            if let slot = hosts[leaf.id] {
                slot.apply(surfaceID: surfaceID, sessionID: leaf.sessionID, showsHeader: showHeader)
            } else {
                let slot = PaneSlotView(
                    nodeID: leaf.id,
                    surfaceID: surfaceID,
                    sessionID: leaf.sessionID,
                    showsHeader: showHeader
                )
                hosts[leaf.id] = slot
                addSubview(slot, positioned: .below, relativeTo: catcher)
            }
        }

        let sashInfos = layoutTree.splitSashes(in: bounds.isEmpty ? CGRect(x: 0, y: 0, width: 1, height: 1) : bounds)
        let sashIDs = Set(sashInfos.map(\.id))
        for (id, sash) in sashes where !sashIDs.contains(id) {
            sash.removeFromSuperview()
            sashes[id] = nil
        }
        for info in sashInfos {
            if let sash = sashes[info.id] {
                sash.axis = info.axis
            } else {
                let sash = SplitSashView(axis: info.axis, splitID: info.id, owner: self)
                sashes[info.id] = sash
                addSubview(sash, positioned: .below, relativeTo: catcher)
            }
        }

        if subviews.last !== catcher {
            addSubview(catcher, positioned: .above, relativeTo: nil)
        }
    }

    private func applyFrames() {
        guard !applyingFrames, bounds.width > 1, bounds.height > 1, let layoutTree else { return }
        applyingFrames = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            CATransaction.commit()
            applyingFrames = false
        }

        if catcher.frame != bounds {
            catcher.frame = bounds
        }

        let leaves = layoutTree.leafFrames(in: bounds, ratioOverrides: liveRatios)
        for leaf in leaves {
            guard let slot = hosts[leaf.id] else { continue }
            if slot.frame != leaf.frame {
                slot.frame = leaf.frame
            }
        }

        let sashInfos = layoutTree.splitSashes(in: bounds, ratioOverrides: liveRatios)
        for info in sashInfos {
            guard let sash = sashes[info.id] else { continue }
            sash.axis = info.axis
            if sash.frame != info.frame {
                sash.frame = info.frame
            }
            sash.resetCursorRects()
        }
    }

    private func currentRatio(for splitID: UUID) -> Double? {
        func search(_ node: PaneNode) -> Double? {
            switch node {
            case .leaf:
                return nil
            case .split(let id, _, let first, let second, let ratio):
                if id == splitID { return ratio }
                return search(first) ?? search(second)
            }
        }
        return layoutTree.flatMap(search)
    }
}

@MainActor
final class SplitSashView: NSView {
    var axis: SplitAxis {
        didSet {
            if oldValue != axis {
                window?.invalidateCursorRects(for: self)
            }
        }
    }

    let splitID: UUID
    weak var owner: WorkspaceTilingNSView?

    init(axis: SplitAxis, splitID: UUID, owner: WorkspaceTilingNSView) {
        self.axis = axis
        self.splitID = splitID
        self.owner = owner
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: resizeCursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        resizeCursor.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        let line: NSRect
        if axis == .horizontal {
            line = NSRect(x: floor(bounds.midX), y: bounds.minY, width: 1, height: bounds.height)
        } else {
            line = NSRect(x: bounds.minX, y: floor(bounds.midY), width: bounds.width, height: 1)
        }
        NSColor.separatorColor.withAlphaComponent(0.55).setFill()
        line.fill()
    }

    override func mouseDown(with event: NSEvent) {
        owner?.beginSashDrag(splitID: splitID, axis: axis, event: event)
        resizeCursor.set()
    }

    override func mouseDragged(with event: NSEvent) {
        owner?.continueSashDrag(event: event)
    }

    override func mouseUp(with event: NSEvent) {
        owner?.endSashDrag()
    }

    private var resizeCursor: NSCursor {
        axis == .horizontal ? .resizeLeftRight : .resizeUpDown
    }
}
