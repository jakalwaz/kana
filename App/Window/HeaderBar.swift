import AppKit

/// Mew-style header: sits in the (transparent) title bar next to the traffic
/// lights, with one pill per tab, a + button, and the wordmark on the right.
/// Empty space drags the window; a double-click zooms it.
@MainActor
final class HeaderBar: NSView {
    static let height: CGFloat = 38
    /// Room for the traffic lights.
    private let leadingInset: CGFloat = 82

    var titles: [String] = [] { didSet { needsDisplay = true } }
    var selectedIndex = 0 { didSet { needsDisplay = true } }
    var accent = NSColor.systemRed { didSet { needsDisplay = true } }

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNewTab: (() -> Void)?

    private var hoverIndex: Int?
    private var hoverClose = false
    private var hoverPlus = false

    private let tabHeight: CGFloat = 24
    private let maxTabWidth: CGFloat = 200
    private let minTabWidth: CGFloat = 90

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    // MARK: geometry

    private var tabWidth: CGFloat {
        let available = bounds.width - leadingInset - 60 - 40
        guard !titles.isEmpty else { return maxTabWidth }
        return max(minTabWidth, min(maxTabWidth, available / CGFloat(titles.count)))
    }

    private func tabRect(_ i: Int) -> NSRect {
        NSRect(x: leadingInset + CGFloat(i) * (tabWidth + 6), y: (bounds.height - tabHeight) / 2, width: tabWidth, height: tabHeight)
    }

    private func closeRect(_ i: Int) -> NSRect {
        let tab = tabRect(i)
        return NSRect(x: tab.maxX - 20, y: tab.midY - 7, width: 14, height: 14)
    }

    private var plusRect: NSRect {
        let x = titles.isEmpty ? leadingInset : tabRect(titles.count - 1).maxX + 6
        return NSRect(x: x, y: (bounds.height - tabHeight) / 2, width: tabHeight, height: tabHeight)
    }

    // MARK: drawing

    override func draw(_: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        NSColor(white: 1, alpha: 0.07).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

        for (i, title) in titles.enumerated() {
            drawTab(i, title: title)
        }

        let plus = plusRect
        if hoverPlus {
            NSColor(white: 1, alpha: 0.08).setFill()
            NSBezierPath(roundedRect: plus, xRadius: 6, yRadius: 6).fill()
        }
        let plusColor = NSColor(white: 1, alpha: hoverPlus ? 0.85 : 0.4)
        drawCentered("+", in: plus, font: .systemFont(ofSize: 15, weight: .light), color: plusColor)

        // wordmark
        let mark = NSAttributedString(string: "カナ", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: 0.28),
        ])
        let size = mark.size()
        let dot = NSRect(x: bounds.width - size.width - 30, y: bounds.midY - 3, width: 6, height: 6)
        accent.setFill()
        NSBezierPath(ovalIn: dot).fill()
        mark.draw(at: NSPoint(x: dot.maxX + 7, y: bounds.midY - size.height / 2))
    }

    private func drawTab(_ i: Int, title: String) {
        let rect = tabRect(i)
        let selected = i == selectedIndex
        let hovered = i == hoverIndex
        if selected || hovered {
            NSColor(white: 1, alpha: selected ? 0.09 : 0.05).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        }
        if selected {
            accent.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 10, y: rect.midY - 2.5, width: 5, height: 5)).fill()
        }

        let textRect = NSRect(x: rect.minX + 22, y: rect.minY, width: rect.width - 22 - 24, height: rect.height)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingHead
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: selected ? .medium : .regular),
            .foregroundColor: NSColor(white: 1, alpha: selected ? 0.92 : 0.45),
            .paragraphStyle: style,
        ])
        let h = text.size().height
        text.draw(with: NSRect(x: textRect.minX, y: rect.midY - h / 2, width: textRect.width, height: h), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        if hovered || (selected && titles.count > 1) {
            let close = closeRect(i)
            if hovered, hoverClose {
                NSColor(white: 1, alpha: 0.12).setFill()
                NSBezierPath(roundedRect: close, xRadius: 4, yRadius: 4).fill()
            }
            drawCentered("×", in: close, font: .systemFont(ofSize: 12, weight: .regular),
                         color: NSColor(white: 1, alpha: hovered && hoverClose ? 0.9 : 0.4))
        }
    }

    private func drawCentered(_ s: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let text = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        let size = text.size()
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    // MARK: mouse

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let index = titles.indices.first { tabRect($0).contains(p) }
        let close = index.map { closeRect($0).insetBy(dx: -3, dy: -3).contains(p) } ?? false
        let plus = plusRect.contains(p)
        if index != hoverIndex || close != hoverClose || plus != hoverPlus {
            hoverIndex = index
            hoverClose = close
            hoverPlus = plus
            needsDisplay = true
        }
    }

    override func mouseExited(with _: NSEvent) {
        hoverIndex = nil
        hoverClose = false
        hoverPlus = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = titles.indices.first(where: { tabRect($0).contains(p) }) {
            if closeRect(i).insetBy(dx: -3, dy: -3).contains(p), titles.count > 1 || i == hoverIndex {
                onClose?(i)
            } else {
                onSelect?(i)
            }
            return
        }
        if plusRect.contains(p) {
            onNewTab?()
            return
        }
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}
