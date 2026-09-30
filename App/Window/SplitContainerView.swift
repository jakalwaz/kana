import AppKit
import KanaCore

/// One tab's content: its panes laid out from the tab's SplitTree, with a
/// thin divider between each split that drags to resize and double-clicks to
/// even everything out. Based on Ghostty's macos/Sources/Features/Splits/
/// SplitView.swift (divider hit area wider than the line, resize cursor).
@MainActor
final class SplitContainerView: NSView {
    static let dividerThickness: CGFloat = 1
    /// How far past the line a divider still grabs the mouse, each side.
    private static let grabSlop: CGFloat = 3

    var onResize: ((SplitPath, Double) -> Void)?
    var onEqualize: (() -> Void)?

    private var tree: SplitTree<TerminalPane>?
    private weak var focused: TerminalPane?
    private var dividerViews: [DividerView] = []

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    /// Shows this tree: adds new panes, drops removed ones, lays it all out.
    func show(_ tree: SplitTree<TerminalPane>, focused: TerminalPane) {
        self.tree = tree
        self.focused = focused
        let leaves = tree.leaves
        for case let pane as TerminalPane in subviews where !leaves.contains(where: { $0 === pane }) {
            pane.removeFromSuperview()
        }
        for pane in leaves where pane.superview !== self {
            addSubview(pane, positioned: .below, relativeTo: dividerViews.first)
        }
        layoutPanes()
    }

    override func layout() {
        super.layout()
        layoutPanes()
    }

    private func layoutPanes() {
        guard let tree else { return }
        let layout = tree.layout(in: bounds, divider: Self.dividerThickness)
        let split = layout.frames.count > 1
        let shown = Set(layout.frames.map { ObjectIdentifier($0.leaf) })
        for pane in tree.leaves where !shown.contains(ObjectIdentifier(pane)) {
            pane.isHidden = true
        }
        for (pane, frame) in layout.frames {
            pane.isHidden = false
            pane.frame = frame
            pane.isDimmed = split && pane !== focused
        }

        while dividerViews.count < layout.dividers.count {
            let view = DividerView()
            view.onDrag = { [weak self] path, ratio in self?.onResize?(path, ratio) }
            view.onDoubleClick = { [weak self] in self?.onEqualize?() }
            addSubview(view, positioned: .above, relativeTo: nil)
            dividerViews.append(view)
        }
        while dividerViews.count > layout.dividers.count {
            dividerViews.removeLast().removeFromSuperview()
        }
        for (view, divider) in zip(dividerViews, layout.dividers) {
            let slop = Self.grabSlop
            view.frame = divider.axis == .horizontal
                ? divider.rect.insetBy(dx: -slop, dy: 0)
                : divider.rect.insetBy(dx: 0, dy: -slop)
            view.divider = divider
        }
    }
}

/// The grab area around one divider line.
@MainActor
private final class DividerView: NSView {
    var divider: SplitDivider? {
        didSet {
            guard divider != oldValue else { return }
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    var onDrag: ((SplitPath, Double) -> Void)?
    var onDoubleClick: (() -> Void)?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_: NSRect) {
        guard let divider else { return }
        NSColor(white: 1, alpha: 0.12).setFill()
        convert(divider.rect, from: superview).fill()
    }

    override func resetCursorRects() {
        guard let divider else { return }
        addCursorRect(bounds, cursor: divider.axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let divider, let container = superview else { return }
        let point = container.convert(event.locationInWindow, from: nil)
        let span = divider.span
        let thickness = SplitContainerView.dividerThickness
        let ratio = divider.axis == .horizontal
            ? (point.x - span.minX - thickness / 2) / max(1, span.width - thickness)
            : (point.y - span.minY - thickness / 2) / max(1, span.height - thickness)
        onDrag?(divider.path, Double(ratio))
    }
}
