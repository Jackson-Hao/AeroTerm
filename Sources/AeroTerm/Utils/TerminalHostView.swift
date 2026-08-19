import AppKit
import SwiftTerm

/// Hosts a reused `TerminalView` without ever shrinking it to an empty or 1×1 frame.
/// SwiftTerm rebuilds its grid on `setFrameSize`; a 0×0 attach (SwiftUI makeNSView)
/// or the old offscreen keep-alive view wiped the buffer on every session switch.
final class TerminalHostView: NSView {
    static let minSize = CGSize(width: 80, height: 40)

    private(set) weak var terminal: TerminalView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        focusRingType = .none
        autoresizingMask = [.width, .height]
        TerminalAppearance.paintContainer(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }
    override var preservesContentDuringLiveResize: Bool { true }

    func install(_ terminal: TerminalView) {
        TerminalAppearance.paintContainer(self)
        if terminal.superview !== self {
            terminal.removeFromSuperview()
            terminal.translatesAutoresizingMaskIntoConstraints = true
            terminal.autoresizingMask = []
            addSubview(terminal)
        }
        self.terminal = terminal
        layoutTerminal()
    }

    func uninstall(_ terminal: TerminalView) {
        guard terminal.superview === self else { return }
        terminal.removeFromSuperview()
        if self.terminal === terminal {
            self.terminal = nil
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutTerminal()
    }

    override func layout() {
        super.layout()
        layoutTerminal()
    }

    private func layoutTerminal() {
        guard let terminal else { return }
        guard bounds.width >= Self.minSize.width, bounds.height >= Self.minSize.height else { return }
        if terminal.frame != bounds {
            terminal.frame = bounds
        }
    }
}
