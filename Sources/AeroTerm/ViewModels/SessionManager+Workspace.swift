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
        if surface(containing: sessionID) != nil {
            selectSession(sessionID)
            return
        }

        let targetID = WorkspaceSurface.primaryID
        ensurePrimaryExists()

        updateSurface(targetID) { surface in
            if let layout = surface.layout {
                if let empty = layout.leaves.first(where: { $0.sessionID == nil }) {
                    surface.layout = layout.replacingLeaf(nodeID: empty.id, sessionID: sessionID)
                    surface.focusedNodeID = empty.id
                } else if let leafID = surface.focusedNodeID ?? layout.firstLeafNodeID() {
                    surface.layout = layout.replacingLeaf(nodeID: leafID, sessionID: sessionID)
                    surface.focusedNodeID = leafID
                }
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
        guard sessions.contains(where: { $0.id == sessionID }) else { return }
        if surface(id: surfaceID)?.layout?.nodeID(for: sessionID) == nodeID {
            return
        }

        let alreadyInTarget = surface(id: surfaceID)?.contains(sessionID: sessionID) == true
        if alreadyInTarget, edge == .center {
            swapSessionsInSurface(sessionID, withNode: nodeID, surfaceID: surfaceID)
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
        guard let host = surface(id: surfaceID), let layout = host.layout else { return }
        let closingSessionID = layout.sessionID(for: nodeID)
        let isLastLeaf = layout.leaves.count == 1

        if isLastLeaf, !host.isPrimary {
            handleDetachedWindowClose(surfaceID)
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            updateSurface(surfaceID) { surface in
                surface.layout = surface.layout?.removing(nodeID: nodeID)
                surface.pruneFocusedNode()
            }
        }
        dismissEmptyDetachedWindows()
        if let remainingSurface = surface(id: surfaceID), remainingSurface.layout != nil {
            if let focusedID = remainingSurface.focusedNodeID,
               let focused = remainingSurface.layout?.sessionID(for: focusedID) {
                activeSessionID = focused
            } else if let remaining = remainingSurface.sessionIDs.first {
                activeSessionID = remaining
            }
        } else if activeSessionID == closingSessionID {
            activeSessionID = sessions.first(where: { surface(containing: $0.id) != nil })?.id
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

    private func swapSessionsInSurface(_ sessionID: UUID, withNode nodeID: UUID, surfaceID: UUID) {
        guard let layout = surface(id: surfaceID)?.layout,
              let sourceNodeID = layout.nodeID(for: sessionID)
        else { return }
        let targetSessionID = layout.sessionID(for: nodeID)
        updateSurface(surfaceID) { surface in
            var next = surface.layout?.replacingLeaf(nodeID: nodeID, sessionID: sessionID)
            next = next?.replacingLeaf(nodeID: sourceNodeID, sessionID: targetSessionID)
            surface.layout = next
            surface.focusedNodeID = nodeID
        }
        activeSessionID = sessionID
        focusedSurfaceID = surfaceID
        sidebarTab = .active
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
