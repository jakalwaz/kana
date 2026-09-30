import AppKit

/// One terminal: a leaf in a tab's split tree. The welcome screen is printed
/// by the shell itself (`kana banner`), so it lives in the scrollback like
/// any output.
@MainActor
final class TerminalPane: NSView {
    let session: TerminalSession

    var title = "zsh"
    var workingDirectory: String?

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
    }
}

/// Draws but never takes clicks, so they reach the terminal underneath.
final class PassthroughView: NSView {
    override func hitTest(_: NSPoint) -> NSView? { nil }
}
