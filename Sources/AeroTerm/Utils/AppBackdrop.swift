import SwiftUI
import AppKit

/// 访达侧栏同款窗口后模糊：`.sidebar` 材质、更小的模糊半径、更高透明度。
public struct AppBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var emphasized: Bool

    public init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        emphasized: Bool = false
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.emphasized = emphasized
    }

    public func makeNSView(context: Context) -> AppVisualEffectView {
        let view = AppVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = emphasized
        view.wantsLayer = true
        view.autoresizingMask = [.width, .height]
        return view
    }

    public func updateNSView(_ view: AppVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = emphasized
    }
}

public final class AppVisualEffectView: NSVisualEffectView {
    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        pinToSuperview()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pinToSuperview()
    }

    public override func layout() {
        super.layout()
        pinToSuperview()
    }

    private func pinToSuperview() {
        guard let superview else { return }
        frame = superview.bounds
        autoresizingMask = [.width, .height]
    }
}

extension NSView {
    func pinFilling(_ container: NSView) {
        if superview !== container {
            removeFromSuperview()
            translatesAutoresizingMaskIntoConstraints = true
            autoresizingMask = [.width, .height]
            frame = container.bounds
            container.addSubview(self)
        } else if frame != container.bounds {
            frame = container.bounds
        }
    }
}
