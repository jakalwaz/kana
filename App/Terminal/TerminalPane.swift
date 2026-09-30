import AppKit

/// One tab's content: a terminal. The welcome screen is printed by the shell
/// itself (`kana banner`), so it lives in the scrollback like any output.
@MainActor
final class TerminalPane: NSView {
    let session: TerminalSession

    var title = "zsh"
    var workingDirectory: String?

    init(settings: KanaSettings, skin: SkinInfo?, banner: TerminalSession.Banner, workingDirectory: String?) {
        session = TerminalSession(settings: settings, skin: skin, banner: banner, workingDirectory: workingDirectory)
        self.workingDirectory = workingDirectory
        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        addSubview(session.view)
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
    }
}
