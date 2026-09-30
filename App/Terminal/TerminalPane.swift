import AppKit

/// One terminal: a leaf in a tab's split tree. The welcome screen is printed
/// by the shell itself (`kana banner`), so it lives in the scrollback like
/// any output.
@MainActor
final class TerminalPane: NSView {
    let session: TerminalSession

    var title = "zsh"
    var workingDirectory: String?

    /// Something happened here you haven't seen: a command finished, a
    /// program asked for you, the bell. Cleared when the pane gets focus.
    var needsAttention = false
    /// OSC 9;4 progress, drawn under the tab.
    var progress: TerminalSession.Progress?

    /// ⌘ over a link: shown bottom-left, like Ghostty's URL preview.
    var hoverLink: String? {
        didSet {
            linkLabel.stringValue = hoverLink ?? ""
            linkLabel.isHidden = hoverLink == nil
            needsLayout = true
        }
    }

    private let linkLabel = PassthroughLabel(labelWithString: "")

    /// Unfocused splits sit behind a dark veil, like Ghostty's
    /// `unfocused-split-opacity` (0.7).
    var isDimmed = false { didSet { veil.isHidden = !isDimmed } }
    private let veil = PassthroughView()

    init(settings: KanaSettings, skin: SkinInfo?, banner: TerminalSession.Banner, workingDirectory: String?) {
        session = TerminalSession(settings: settings, skin: skin, banner: banner, workingDirectory: workingDirectory)
        self.workingDirectory = workingDirectory
        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        wantsLayer = true
        // transparent: the tab's themed container shows through while it resizes
        addSubview(session.view)
        veil.wantsLayer = true
        veil.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        veil.isHidden = true
        addSubview(veil)
        linkLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        linkLabel.textColor = .white
        linkLabel.lineBreakMode = .byTruncatingMiddle
        linkLabel.wantsLayer = true
        linkLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        linkLabel.layer?.cornerRadius = 4
        linkLabel.isHidden = true
        addSubview(linkLabel)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { session.focus() }
    }

    override func layout() {
        super.layout()
        session.view.frame = bounds
        veil.frame = bounds
        let size = linkLabel.fittingSize
        linkLabel.frame = NSRect(x: 8, y: 6, width: min(size.width + 12, bounds.width * 0.8), height: size.height + 4)
    }
}

/// A label that lets clicks through to the terminal under it.
final class PassthroughLabel: NSTextField {
    override func hitTest(_: NSPoint) -> NSView? { nil }
}

/// Draws but never takes clicks, so they reach the terminal underneath.
final class PassthroughView: NSView {
    override func hitTest(_: NSPoint) -> NSView? { nil }
}
