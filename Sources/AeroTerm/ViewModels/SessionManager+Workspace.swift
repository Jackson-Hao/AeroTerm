import Foundation
import AppKit
import SwiftUI

extension SessionManager {
    public func surface(id: UUID) -> WorkspaceSurface? {
        surfaces.first(where: { $0.id == id })
    }

    public func surface(containing sessionID: UUID) -> WorkspaceSurface? {
        surfaces.first(where: { $0.contains(sessionID: sessionID) })
    }

    public var primarySurface: WorkspaceSurface {
        surfaces.first(where: { $0.isPrimary }) ?? WorkspaceSurface.makePrimary()
    }

    public func isSessionDetached(_ sessionID: UUID) -> Bool {
        surface(containing: sessionID)?.isPrimary == false
    }

    public func hiddenSessions(excluding surfaceID: UUID? = nil) -> [SessionItem] {
        sessions.filter { session in
            guard let host = surface(containing: session.id) else { return true }
            if let surfaceID { return host.id != surfaceID }
            return false
        }
    }

    public func needsOffscreenKeepAlive(_ session: SessionItem) -> Bool {
        (session.type.usesAccountAuth || session.type == .agentCLI)
            && surface(containing: session.id) == nil
    }

    public func enqueueWindowCommand(_ command: WorkspaceWindowCommand) {
        windowCommands.append(command)
    }

    public func consumeWindowCommands() -> [WorkspaceWindowCommand] {
        let batch = windowCommands
        windowCommands = []
        return batch
    }

    public func selectSession(_ sessionID: UUID) {
        guard sessions.contains(where: { $0.id == sessionID }) else { return }
        sidebarTab = .active
        if let host = surface(containing: sessionID) {
            activeSessionID = sessionID
            focusedSurfaceID = host.id
            updateSurface(host.id) { surface in
                surface.focusedNodeID = surface.layout?.nodeID(for: sessionID) ?? surface.focusedNodeID
            }
            if !host.isPrimary {
                enqueueWindowCommand(.focus(host.id))
            } else if let main = NSApp.windows.first(where: { $0.identifier?.rawValue == "AeroTerm.Main" }) {
                main.makeKeyAndOrderFront(nil)
            }
            return
        }
        revealSession(sessionID)
    }

    public func revealSession(_ sessionID: UUID) {
        guard sessions.contains(where: { $0.id == sessionID }) else { return }
        if applyPendingDropPlacement(sessionID: sessionID) {
            return
        }
        if surface(containing: sessionID) != nil {
            selectSession(sessionID)
            return
        }

        let targetID = WorkspaceSurface.primaryID
        ensurePrimaryExists()

        updateSurface(targetID) { surface in
            if let layout = surface.layout,
               let leafID = surface.focusedNodeID ?? layout.firstLeafNodeID() {
                surface.layout = layout.replacingLeaf(nodeID: leafID, sessionID: sessionID)
                surface.focusedNodeID = leafID
            } else {
                let leaf = PaneNode.leaf(id: UUID(), sessionID: sessionID)
                surface.layout = leaf
                surface.focusedNodeID = leaf.id
            }
        }
        activeSessionID = sessionID
        focusedSurfaceID = targetID
        sidebarTab = .active
    }

    public func detachSession(_ sessionID: UUID) {
        guard sessions.contains(where: { $0.id == sessionID }) else { return }
        if let existing = surface(containing: sessionID), !existing.isPrimary, existing.sessionIDs == [sessionID] {
            enqueueWindowCommand(.focus(existing.id))
            activeSessionID = sessionID
            focusedSurfaceID = existing.id
            return
        }

        removeSessionFromLayouts(sessionID)
        let leaf = PaneNode.leaf(id: UUID(), sessionID: sessionID)
        let surface = WorkspaceSurface(
            id: UUID(),
            layout: leaf,
            isPrimary: false,
            focusedNodeID: leaf.id
        )
        surfaces.append(surface)
        activeSessionID = sessionID
        focusedSurfaceID = surface.id
        sidebarTab = .active
        enqueueWindowCommand(.open(surface.id))
        dismissEmptyDetachedWindows()
    }

    public func mergeSessionToMain(_ sessionID: UUID) {
        guard sessions.contains(where: { $0.id == sessionID }) else { return }
        removeSessionFromLayouts(sessionID)
        insertIntoPrimary(sessionID, splitIfNeeded: primarySurface.layout != nil)
        dismissEmptyDetachedWindows()
        activeSessionID = sessionID
        focusedSurfaceID = WorkspaceSurface.primaryID
        sidebarTab = .active
    }

    public func mergeSurfaceToMain(_ surfaceID: UUID) {
        guard let surface = surface(id: surfaceID), !surface.isPrimary else { return }
        let ids = surface.sessionIDs
        surfaces.removeAll { $0.id == surfaceID }
        for (index, id) in ids.enumerated() {
            insertIntoPrimary(id, splitIfNeeded: index > 0 || primarySurface.layout != nil)
        }
        enqueueWindowCommand(.close(surfaceID))
        if let first = ids.first {
            activeSessionID = first
        }
        focusedSurfaceID = WorkspaceSurface.primaryID
    }

    public func handleDetachedWindowClose(_ surfaceID: UUID) {
        guard let surface = surface(id: surfaceID), !surface.isPrimary else { return }
        let ids = surface.sessionIDs
        surfaces.removeAll { $0.id == surfaceID }
        for (index, id) in ids.enumerated() {
            insertIntoPrimary(id, splitIfNeeded: index > 0 || primarySurface.layout != nil)
        }
        if let first = ids.first {
            activeSessionID = first
        }
        focusedSurfaceID = WorkspaceSurface.primaryID
    }

    public func splitSession(_ sessionID: UUID, axis: SplitAxis) {
        guard sessions.contains(where: { $0.id == sessionID }) else { return }
        if let host = surface(containing: sessionID),
           let nodeID = host.layout?.nodeID(for: sessionID) {
            updateSurface(host.id) { surface in
                surface.layout = surface.layout?.splitting(nodeID: nodeID, axis: axis, newSessionID: nil)
                surface.focusedNodeID = nodeID
            }
            activeSessionID = sessionID
            focusedSurfaceID = host.id
            return
        }

        let targetID = surfaces.contains(where: { $0.id == focusedSurfaceID })
            ? focusedSurfaceID
            : WorkspaceSurface.primaryID
        ensurePrimaryExists()
        guard let host = surface(id: targetID), let layout = host.layout,
              let leafID = host.focusedNodeID ?? layout.firstLeafNodeID()
        else {
            revealSession(sessionID)
            return
        }

        removeSessionFromLayouts(sessionID)
        updateSurface(targetID) { surface in
            surface.layout = surface.layout?.splitting(nodeID: leafID, axis: axis, newSessionID: sessionID)
            surface.focusedNodeID = surface.layout?.nodeID(for: sessionID)
        }
        activeSessionID = sessionID
        focusedSurfaceID = targetID
    }

    public func dropSession(_ sessionID: UUID, onto nodeID: UUID, edge: DropEdge, in surfaceID: UUID) {
        guard let source = sessions.first(where: { $0.id == sessionID }) else { return }
        let alreadyInTarget = surface(id: surfaceID)?.contains(sessionID: sessionID) == true
        if alreadyInTarget {
            if edge == .center, surface(id: surfaceID)?.layout?.nodeID(for: sessionID) == nodeID {
                return
            }
            cloneSession(source, onto: nodeID, edge: edge, in: surfaceID)
            return
        }

        removeSessionFromLayouts(sessionID)
        guard surface(id: surfaceID)?.layout?.contains(nodeID: nodeID) == true else {
            revealSession(sessionID)
            return
        }

        updateSurface(surfaceID) { surface in
            surface.layout = surface.layout?.placing(sessionID: sessionID, on: nodeID, edge: edge)
            surface.focusedNodeID = surface.layout?.nodeID(for: sessionID)
        }
        dismissEmptyDetachedWindows()
        activeSessionID = sessionID
        focusedSurfaceID = surfaceID
        sidebarTab = .active
    }

    public func dropSessionOnEmptySurface(_ sessionID: UUID, surfaceID: UUID) {
        guard sessions.contains(where: { $0.id == sessionID }) else { return }
        removeSessionFromLayouts(sessionID)
        ensurePrimaryExists()
        updateSurface(surfaceID) { surface in
            let leaf = PaneNode.leaf(id: UUID(), sessionID: sessionID)
            surface.layout = leaf
            surface.focusedNodeID = leaf.id
        }
        dismissEmptyDetachedWindows()
        activeSessionID = sessionID
        focusedSurfaceID = surfaceID
        sidebarTab = .active
    }

    public func setSplitRatio(nodeID: UUID, surfaceID: UUID, ratio: Double) {
        updateSurface(surfaceID) { surface in
            surface.layout = surface.layout?.settingRatio(nodeID: nodeID, ratio: ratio)
        }
    }

    public func closePane(nodeID: UUID, surfaceID: UUID) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            updateSurface(surfaceID) { surface in
                surface.layout = surface.layout?.removing(nodeID: nodeID)
                surface.pruneFocusedNode()
            }
        }
        dismissEmptyDetachedWindows()
        if let remainingSurface = surface(id: surfaceID) {
            if let focusedID = remainingSurface.focusedNodeID,
               let focused = remainingSurface.layout?.sessionID(for: focusedID) {
                activeSessionID = focused
            } else if let remaining = remainingSurface.sessionIDs.first {
                activeSessionID = remaining
            }
        }
        DispatchQueue.main.async {
            NSApp.keyWindow?.contentView?.layoutSubtreeIfNeeded()
        }
    }

    public func focusPane(nodeID: UUID, surfaceID: UUID) {
        updateSurface(surfaceID) { surface in
            surface.focusedNodeID = nodeID
        }
        focusedSurfaceID = surfaceID
        if let sessionID = surface(id: surfaceID)?.layout?.sessionID(for: nodeID) {
            activeSessionID = sessionID
            sidebarTab = .active
        }
    }

    public func assignSessionToLeaf(_ sessionID: UUID, nodeID: UUID, surfaceID: UUID) {
        dropSession(sessionID, onto: nodeID, edge: .center, in: surfaceID)
    }

    func cancelPendingDropPlacement() {
        guard let pending = pendingDropPlacement else { return }
        pendingDropPlacement = nil
        updateSurface(pending.surfaceID) { surface in
            if surface.layout?.sessionID(for: pending.nodeID) == nil {
                surface.layout = surface.layout?.removing(nodeID: pending.nodeID)
                surface.pruneFocusedNode()
            }
        }
        dismissEmptyDetachedWindows()
    }

    private func cloneSession(_ source: SessionItem, onto nodeID: UUID, edge: DropEdge, in surfaceID: UUID) {
        guard surface(id: surfaceID)?.layout?.contains(nodeID: nodeID) == true else { return }
        let placeholderID = UUID()
        if edge == .center {
            pendingDropPlacement = PendingDropPlacement(surfaceID: surfaceID, nodeID: nodeID, edge: .center)
        } else {
            updateSurface(surfaceID) { surface in
                surface.layout = surface.layout?.inserting(
                    sessionID: nil,
                    leafID: placeholderID,
                    on: nodeID,
                    edge: edge
                )
                surface.focusedNodeID = placeholderID
            }
            pendingDropPlacement = PendingDropPlacement(surfaceID: surfaceID, nodeID: placeholderID, edge: .center)
        }
        duplicateSession(source)
    }

    @discardableResult
    private func applyPendingDropPlacement(sessionID: UUID) -> Bool {
        guard let pending = pendingDropPlacement else { return false }
        pendingDropPlacement = nil
        guard surface(id: pending.surfaceID)?.layout?.contains(nodeID: pending.nodeID) == true else {
            return false
        }
        updateSurface(pending.surfaceID) { surface in
            if pending.edge == .center {
                surface.layout = surface.layout?.replacingLeaf(nodeID: pending.nodeID, sessionID: sessionID)
                surface.focusedNodeID = pending.nodeID
            } else {
                surface.layout = surface.layout?.placing(sessionID: sessionID, on: pending.nodeID, edge: pending.edge)
                surface.focusedNodeID = surface.layout?.nodeID(for: sessionID)
            }
        }
        activeSessionID = sessionID
        focusedSurfaceID = pending.surfaceID
        sidebarTab = .active
        return true
    }

    func pruneSessionFromLayouts(_ sessionID: UUID) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            removeSessionFromLayouts(sessionID)
        }
        dismissEmptyDetachedWindows()
    }

    func resetWorkspaceLayouts() {
        let detached = surfaces.filter { !$0.isPrimary }.map(\.id)
        surfaces = [WorkspaceSurface.makePrimary()]
        focusedSurfaceID = WorkspaceSurface.primaryID
        for id in detached {
            enqueueWindowCommand(.close(id))
        }
    }

    private func insertIntoPrimary(_ sessionID: UUID, splitIfNeeded: Bool) {
        ensurePrimaryExists()
        updateSurface(WorkspaceSurface.primaryID) { surface in
            if splitIfNeeded, let layout = surface.layout,
               let leafID = surface.focusedNodeID ?? layout.firstLeafNodeID() {
                surface.layout = layout.splitting(nodeID: leafID, axis: .horizontal, newSessionID: sessionID)
            } else if surface.layout == nil {
                let leaf = PaneNode.leaf(id: UUID(), sessionID: sessionID)
                surface.layout = leaf
                surface.focusedNodeID = leaf.id
            } else if let leafID = surface.focusedNodeID ?? surface.layout?.firstLeafNodeID() {
                surface.layout = surface.layout?.replacingLeaf(nodeID: leafID, sessionID: sessionID)
            }
            surface.focusedNodeID = surface.layout?.nodeID(for: sessionID) ?? surface.focusedNodeID
        }
    }

    private func removeSessionFromLayouts(_ sessionID: UUID) {
        for surface in surfaces {
            guard surface.contains(sessionID: sessionID) else { continue }
            updateSurface(surface.id) { item in
                item.layout = item.layout?.removing(sessionID: sessionID)
                item.pruneFocusedNode()
            }
        }
    }

    private func dismissEmptyDetachedWindows() {
        let emptyIDs = surfaces.filter { !$0.isPrimary && $0.layout == nil }.map(\.id)
        guard !emptyIDs.isEmpty else { return }
        surfaces.removeAll { emptyIDs.contains($0.id) }
        for id in emptyIDs {
            enqueueWindowCommand(.close(id))
        }
        if emptyIDs.contains(focusedSurfaceID) {
            focusedSurfaceID = WorkspaceSurface.primaryID
        }
    }

    private func ensurePrimaryExists() {
        if !surfaces.contains(where: { $0.isPrimary }) {
            surfaces.insert(WorkspaceSurface.makePrimary(), at: 0)
        }
    }

    private func updateSurface(_ id: UUID, _ body: (inout WorkspaceSurface) -> Void) {
        ensurePrimaryExists()
        if let index = surfaces.firstIndex(where: { $0.id == id }) {
            var surface = surfaces[index]
            body(&surface)
            surfaces[index] = surface
            return
        }
        if id == WorkspaceSurface.primaryID {
            var surface = WorkspaceSurface.makePrimary()
            body(&surface)
            surfaces.insert(surface, at: 0)
        }
    }
}
