import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
enum PaneDragSession {
    static var activeSessionID: UUID?
}

@MainActor
enum SessionDragPayload {
    static let typeIdentifier = "app.aeroterm.session"
    static let pasteboardType = NSPasteboard.PasteboardType(typeIdentifier)

    static func provider(for sessionID: UUID) -> NSItemProvider {
        PaneDragSession.activeSessionID = sessionID
        let text = sessionID.uuidString
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .ownProcess) { completion in
            completion(text.data(using: .utf8), nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .ownProcess) { completion in
            completion(text.data(using: .utf8), nil)
            return nil
        }
        return provider
    }

    static func sessionID(from pasteboard: NSPasteboard) -> UUID? {
        if let data = pasteboard.data(forType: pasteboardType),
           let text = String(data: data, encoding: .utf8),
           let id = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return id
        }
        if let text = pasteboard.string(forType: pasteboardType)
            ?? pasteboard.string(forType: .string),
           let id = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return id
        }
        return nil
    }
}

struct SessionDragSource: ViewModifier {
    let sessionID: UUID?

    func body(content: Content) -> some View {
        if let sessionID {
            content.onDrag {
                SessionDragPayload.provider(for: sessionID)
            }
        } else {
            content
        }
    }
}

struct WorkspaceDropCatcher: NSViewRepresentable {
    let surfaceID: UUID

    func makeNSView(context: Context) -> WorkspaceDropCatcherView {
        let view = WorkspaceDropCatcherView(frame: .zero)
        view.surfaceID = surfaceID
        return view
    }

    func updateNSView(_ view: WorkspaceDropCatcherView, context: Context) {
        view.surfaceID = surfaceID
    }
}

@MainActor
final class WorkspaceDropCatcherView: NSView {
    var surfaceID: UUID = WorkspaceSurface.primaryID
    /// When embedded in `WorkspaceTilingNSView`, frames are assigned by the owner.
    var locksFrameToSuperview = true

    private let highlightLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            SessionDragPayload.pasteboardType,
            .string,
            NSPasteboard.PasteboardType(UTType.utf8PlainText.identifier),
            NSPasteboard.PasteboardType(UTType.plainText.identifier)
        ])
        wantsLayer = true
        focusRingType = .none
        layer?.backgroundColor = NSColor.clear.cgColor
        highlightLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
        highlightLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.75).cgColor
        highlightLayer.lineWidth = 2
        highlightLayer.isHidden = true
        layer?.addSublayer(highlightLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        pinToSuperview()
    }

    override func layout() {
        super.layout()
        pinToSuperview()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard PaneDragSession.activeSessionID != nil, bounds.contains(point) else {
            return nil
        }
        return self
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender) else { return [] }
        updateHighlight(with: sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender) else {
            clearHighlight()
            return []
        }
        updateHighlight(with: sender)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        clearHighlight()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        clearHighlight()
        PaneDragSession.activeSessionID = nil
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            clearHighlight()
        }
        guard let sessionID = resolvedSessionID(from: sender) else {
            PaneDragSession.activeSessionID = nil
            return false
        }
        let point = convert(sender.draggingLocation, from: nil)
        let manager = SessionManager.shared
        guard let surface = manager.surface(id: surfaceID) else {
            PaneDragSession.activeSessionID = nil
            return false
        }

        if let layout = surface.layout {
            guard let target = resolve(at: point, layout: layout) else {
                PaneDragSession.activeSessionID = nil
                return false
            }
            manager.dropSession(sessionID, onto: target.nodeID, edge: target.edge, in: surfaceID)
        } else {
            manager.dropSessionOnEmptySurface(sessionID, surfaceID: surfaceID)
        }
        PaneDragSession.activeSessionID = nil
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        clearHighlight()
    }

    private func canAccept(_ sender: NSDraggingInfo) -> Bool {
        resolvedSessionID(from: sender) != nil
    }

    private func resolvedSessionID(from sender: NSDraggingInfo) -> UUID? {
        SessionDragPayload.sessionID(from: sender.draggingPasteboard)
            ?? PaneDragSession.activeSessionID
    }

    private func pinToSuperview() {
        guard locksFrameToSuperview, let superview else { return }
        if frame != superview.bounds {
            frame = superview.bounds
        }
        autoresizingMask = [.width, .height]
    }

    private func updateHighlight(with sender: NSDraggingInfo) {
        let point = convert(sender.draggingLocation, from: nil)
        let manager = SessionManager.shared
        guard let surface = manager.surface(id: surfaceID) else {
            clearHighlight()
            return
        }
        if let layout = surface.layout, let target = resolve(at: point, layout: layout) {
            showHighlight(PaneNode.highlightRect(for: target.edge, in: target.frame))
        } else if surface.layout == nil {
            showHighlight(bounds)
        } else {
            clearHighlight()
        }
    }

    private func showHighlight(_ rect: CGRect) {
        let inset = rect.insetBy(dx: 3, dy: 3)
        highlightLayer.path = CGPath(roundedRect: inset, cornerWidth: 6, cornerHeight: 6, transform: nil)
        highlightLayer.isHidden = false
    }

    private func clearHighlight() {
        highlightLayer.isHidden = true
        highlightLayer.path = nil
    }

    private func resolve(at point: CGPoint, layout: PaneNode) -> (nodeID: UUID, edge: DropEdge, frame: CGRect)? {
        let leaves = layout.leafFrames(in: bounds)
        guard let leaf = leaves.first(where: { $0.frame.contains(point) }) ?? leaves.min(by: {
            hypot($0.frame.midX - point.x, $0.frame.midY - point.y)
                < hypot($1.frame.midX - point.x, $1.frame.midY - point.y)
        }) else {
            return nil
        }
        return (leaf.id, PaneNode.dropEdge(at: point, in: leaf.frame), leaf.frame)
    }
}
