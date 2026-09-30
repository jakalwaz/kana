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
    /// Per tab: something there wants you (an accent dot, like the selected
    /// tab's), and OSC 9;4 progress (a thin bar along the bottom).
    var attention: [Bool] = [] { didSet { needsDisplay = true } }
    var progress: [TerminalSession.Progress?] = [] { didSet { needsDisplay = true } }
    var accent = NSColor.systemRed { didSet { needsDisplay = true } }
    /// The terminal's background; text and pills flip dark on light themes.
    var background = NSColor.black { didSet { needsDisplay = true } }

    private func ink(_ alpha: CGFloat) -> NSColor {
        (background.isLight ? NSColor.black : NSColor.white).withAlphaComponent(alpha)
    }

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNewTab: (() -> Void)?

    private var hoverIndex: Int?
    private var hoverClose = false
    private var hoverPlus = false

    private let tabHeight: CGFloat = 24
    private let maxTabWidth: CGFloat = 200
    /// With the wordmark hidden, eight tabs this wide fit the smallest window
    /// (480 pt). Past that they run off the edge; ⌘1-9 and ⌘⇧[ ] still reach them.
    private let minTabWidth: CGFloat = 36
    private let tabGap: CGFloat = 6
    private let plusReserve: CGFloat = 30
    private let wordmarkReserve: CGFloat = 80

    /// The wordmark gives way when the tabs need its room.
    private var showsWordmark: Bool {
        let n = CGFloat(titles.count)
        let needed = leadingInset + n * minTabWidth + max(0, n - 1) * tabGap + plusReserve + wordmarkReserve
        return needed <= bounds.width
    }

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
        guard !titles.isEmpty else { return maxTabWidth }
        let n = CGFloat(titles.count)
        let trailing = plusReserve + (showsWordmark ? wordmarkReserve : 10)
        let available = bounds.width - leadingInset - trailing - tabGap * (n - 1)
        return max(minTabWidth, min(maxTabWidth, available / n))
    }

    private func tabRect(_ i: Int) -> NSRect {
        NSRect(x: leadingInset + CGFloat(i) * (tabWidth + tabGap), y: (bounds.height - tabHeight) / 2, width: tabWidth, height: tabHeight)
    }

    private func closeRect(_ i: Int) -> NSRect {
        let tab = tabRect(i)
        return NSRect(x: tab.maxX - 20, y: tab.midY - 7, width: 14, height: 14)
    }

    private var plusRect: NSRect {
        let x = titles.isEmpty ? leadingInset : tabRect(titles.count - 1).maxX + tabGap
        return NSRect(x: x, y: (bounds.height - tabHeight) / 2, width: tabHeight, height: tabHeight)
    }

    // MARK: drawing

    override func draw(_: NSRect) {
        background.setFill()
        bounds.fill()
        ink(0.07).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

        for (i, title) in titles.enumerated() {
            drawTab(i, title: title)
        }

        let plus = plusRect
        if hoverPlus {
            ink(0.08).setFill()
            NSBezierPath(roundedRect: plus, xRadius: 6, yRadius: 6).fill()
        }
        let plusColor = ink(hoverPlus ? 0.85 : 0.4)
        drawCentered("+", in: plus, font: .systemFont(ofSize: 15, weight: .light), color: plusColor)

        guard showsWordmark else { return }
        let mark = NSAttributedString(string: "カナ", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: ink(0.28),
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
            ink(selected ? 0.09 : 0.05).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        }
        let wantsYou = attention.indices.contains(i) && attention[i]
        if selected || wantsYou {
            accent.setFill()
            // a bigger dot when it's calling you from another tab
            let r: CGFloat = wantsYou && !selected ? 3.5 : 2.5
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 12.5 - r, y: rect.midY - r, width: 2 * r, height: 2 * r)).fill()
        }
        if progress.indices.contains(i), let p = progress[i] {
            drawProgress(p, in: rect)
        }

        let textRect = NSRect(x: rect.minX + 22, y: rect.minY, width: rect.width - 22 - 24, height: rect.height)
        // narrow tabs show just a dot (grey unless selected) and the ×
        guard textRect.width >= 16 else {
            if !selected, !wantsYou {
                ink(0.3).setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.minX + 10, y: rect.midY - 2.5, width: 5, height: 5)).fill()
            }
            return drawClose(i, rect: rect, selected: selected, hovered: hovered)
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingHead
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: selected ? .medium : .regular),
            .foregroundColor: ink(selected ? 0.92 : 0.45),
            .paragraphStyle: style,
        ])
        let h = text.size().height
        text.draw(with: NSRect(x: textRect.minX, y: rect.midY - h / 2, width: textRect.width, height: h), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        drawClose(i, rect: rect, selected: selected, hovered: hovered)
    }

    /// Busy with no percentage: a faint full bar. Red when it failed,
    /// amber when paused.
    private func drawProgress(_ p: TerminalSession.Progress, in rect: NSRect) {
        let track = NSRect(x: rect.minX + 8, y: rect.maxY - 3, width: rect.width - 16, height: 2)
        let color = p.failed ? NSColor.systemRed : p.paused ? NSColor.systemOrange : accent
        guard let percent = p.percent else {
            color.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: track, xRadius: 1, yRadius: 1).fill()
            return
        }
        ink(0.08).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1, yRadius: 1).fill()
        var done = track
        done.size.width = track.width * CGFloat(min(100, max(0, percent))) / 100
        color.setFill()
        NSBezierPath(roundedRect: done, xRadius: 1, yRadius: 1).fill()
    }

    private func drawClose(_ i: Int, rect _: NSRect, selected: Bool, hovered: Bool) {
        guard hovered || (selected && titles.count > 1) else { return }
        let close = closeRect(i)
        if hovered, hoverClose {
            ink(0.12).setFill()
            NSBezierPath(roundedRect: close, xRadius: 4, yRadius: 4).fill()
        }
        drawCentered("×", in: close, font: .systemFont(ofSize: 12, weight: .regular),
                     color: ink(hovered && hoverClose ? 0.9 : 0.4))
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
