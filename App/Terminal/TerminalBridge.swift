// The only file that talks to libghostty (through libghostty-spm's
// GhosttyTerminal wrapper, which owns the ghostty.h calls). Everything else in
// Kana goes through `TerminalSession`, so a Ghostty bump only touches here.
//
// Based on libghostty-spm's Example/GhosttyTerminalApp (surface setup),
// Ghostty's macos/Sources/Ghostty/Ghostty.Config.swift (keybind handling),
// Features/Terminal/BaseTerminalController.swift (close confirmation) and
// Features/ClipboardConfirmation/ (unsafe paste).

import AppKit
import GhosttyTerminal
import KanaCore

/// Kana's terminal look: pure black, one accent colour. Ghostty config
/// lines, used unless the config picks a `theme`.
enum KanaTheme {
    static func lines(accentHex: String) -> [KanaConfig.GhosttyLine] {
        let accent = accentHex.replacingOccurrences(of: "#", with: "")
        let palette = [
            // Normal 0-7
            "1A1A1A", accent, "5FD38D", "F2C063", "5FA8FF", "C78CFF", "4FD6D6", "D0D0D0",
            // Bright 8-15. 8 is the grey of inline suggestions: readable, but quiet.
            "666666", "FF4B55", "7EF0A8", "FFD580", "8CC4FF", "DDB0FF", "7EF0F0", "FFFFFF",
        ]
        return [
            .init("background", "000000"),
            .init("foreground", "E6E6E6"),
            .init("cursor-color", accent),
            .init("cursor-text", "000000"),
            .init("selection-background", "2B2B2B"),
            .init("selection-foreground", "FFFFFF"),
        ] + palette.enumerated().map { .init("palette", "\($0.offset)=#\($0.element)") }
    }
}

@MainActor
enum TerminalBridge {
    /// One controller (one ghostty app) shared by every pane.
    private static var controller: TerminalController?

    /// Ghostty's default macOS keybinds that Kana handles itself (tabs,
    /// windows, Focus Mode, quit, config). While ghostty owns them, the view
    /// swallows the keys and they never reach Kana's menu. See `default`
    /// keybinds in Ghostty's src/config/Config.zig.
    private static let keysKanaOwns: [String] = {
        var keys = [
            "super+q", "super+,", "super+shift+,", "super+shift+k", "super+shift+p", "super+shift+t", "super+shift+o",
            "super+t", "super+n", "super+w", "super+alt+w", "super+shift+w", "super+shift+alt+w",
            "super+shift+[", "super+shift+]", "super+d", "super+shift+d", "super+[", "super+]",
            "super+shift+f", "super+alt+p", "super+alt+i", "super+ctrl+f", "super+enter",
            // splits: zoom, equalize, move between them
            "super+shift+enter", "super+ctrl+=",
            "super+alt+arrow_up", "super+alt+arrow_down", "super+alt+arrow_left", "super+alt+arrow_right",
        ]
        for i in 1 ... 9 { keys += ["super+\(i)", "super+digit_\(i)"] }
        return keys
    }()

    /// Kana's defaults, under anything in the user's config.
    private static let baseLines: [KanaConfig.GhosttyLine] = [
        .init("font-size", "13"),
        .init("font-thicken", "false"),
        .init("cursor-style", "bar"),
        .init("cursor-style-blink", "true"),
        .init("background-opacity", "1"),
        .init("window-padding-x", "14"),
        .init("window-padding-y", "8"),
        .init("window-padding-balance", "true"),
        .init("mouse-hide-while-typing", "true"),
        .init("shell-integration-features", "cursor,title"),
    ]

    /// Where the rendered Ghostty config lives. Kept (not in tmp) so it's
    /// easy to look at when a setting doesn't do what you expect.
    static var ghosttyConfigFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kana/ghostty.conf")
    }

    static func controller(settings: KanaSettings) -> TerminalController {
        if let controller { return controller }
        writeGhosttyConfig(settings)
        // An empty theme: the wrapper's default (Afterglow) would otherwise
        // be applied over the file and win over the user's theme.
        let made = TerminalController(configSource: .file(ghosttyConfigFile.path), theme: TerminalTheme())
        controller = made
        return made
    }

    /// ⌘⇧,: the config file again, into every running terminal. Kana's own
    /// keys (skin, banner...) apply to new tabs.
    static func reload(settings: KanaSettings) {
        // a stale file would reload silently, so a failed write stops here
        guard writeGhosttyConfig(settings) else { return }
        controller?.updateConfigSource(.file(ghosttyConfigFile.path))
    }

    /// The terminal background, for the window chrome. Ghostty's resolved
    /// colour, except with a `light:X,dark:Y` theme, where it's read from the
    /// side that matches the system appearance (the resolved one goes stale
    /// when the appearance changes).
    static func backgroundColor(settings: KanaSettings, dark: Bool) -> NSColor {
        // an explicit `background` in the config beats any theme, in Ghostty too
        let explicit = settings.config.ghostty.last { $0.key == "background" }?.value
        if let theme = settings.config.theme, ThemeLibrary.pair(theme) != nil, let explicit,
           let color = NSColor(hex: explicit.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        {
            return color
        }
        if let theme = settings.config.theme, let pair = ThemeLibrary.pair(theme),
           let hex = ThemeLibrary.background(ofTheme: dark ? pair.dark : pair.light),
           let color = NSColor(hex: hex)
        {
            return color
        }
        guard let color = controller?.backgroundColor else { return .black }
        return NSColor(srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255,
                       blue: CGFloat(color.blue) / 255, alpha: 1)
    }

    /// Problems with the user's config: Kana's parser, then writing the
    /// file, then Ghostty's (unknown keys, bad values).
    static func configurationIssues(settings: KanaSettings) -> [String] {
        settings.config.issues + [writeIssue, controller?.lastConfigurationIssue].compactMap { $0 }
    }

    private static var writeIssue: String?

    @discardableResult
    private static func writeGhosttyConfig(_ settings: KanaSettings) -> Bool {
        let colors = settings.config.theme == nil ? KanaTheme.lines(accentHex: settings.accentHex) : []
        let text = settings.config.renderGhostty(
            defaults: baseLines + colors,
            enforced: keysKanaOwns.map { .init("keybind", "\($0)=unbind") },
            resolveTheme: ThemeLibrary.path(for:)
        )
        let file = ghosttyConfigFile
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(("# Written by Kana from ~/.config/kana/config. Edit that file, not this one.\n" + text).utf8)
                .write(to: file, options: .atomic)
            writeIssue = nil
            return true
        } catch {
            writeIssue = "couldn't write \(file.path): \(error.localizedDescription)"
            return false
        }
    }
}

/// One shell in one libghostty surface.
@MainActor
final class TerminalSession: NSObject {
    let view: NSView
    let paneID = UUID().uuidString

    var onTitleChange: ((String) -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    /// A command ended (shell integration's prompt marks). Exit code nil
    /// when the shell didn't say.
    var onCommandFinished: ((_ exitCode: Int?, _ duration: TimeInterval) -> Void)?
    /// OSC 9 / OSC 777 from a program (Claude Code uses these), or the bell.
    var onNotification: ((_ title: String, _ body: String) -> Void)?
    var onBell: (() -> Void)?
    /// OSC 9;4: nil when the program cleared it; percent nil when it only
    /// says it's busy.
    var onProgress: ((Progress?) -> Void)?
    /// ⌘ over a link: the URL, or nil when the pointer left it.
    var onHoverLink: ((String?) -> Void)?

    struct Progress: Equatable {
        var percent: Int?
        var failed = false
        var paused = false
    }
    var onWorkingDirectoryChange: ((String) -> Void)?
    /// The surface is closing. `processAlive` means something other than an
    /// idle shell is still running, so the host should confirm first.
    var onClose: ((_ processAlive: Bool) -> Void)?

    private let surfaceView: AppTerminalView

    /// What the welcome screen does in this shell.
    enum Banner: String { case animate, still, off }

    init(settings: KanaSettings, skin: SkinInfo?, banner: Banner, workingDirectory: String?) {
        surfaceView = AppTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view = surfaceView
        super.init()

        surfaceView.delegate = self
        surfaceView.setAccessibilityLabel("Terminal")
        surfaceView.controller = TerminalBridge.controller(settings: settings)
        surfaceView.configuration = TerminalSurfaceOptions(
            backend: .exec,
            workingDirectory: workingDirectory ?? NSHomeDirectory(),
            envVars: Self.environment(settings: settings, skin: skin, banner: banner, paneID: paneID)
        )
    }

    /// Shell environment. Kana's zsh layer (suggestions, welcome screen) loads
    /// through Ghostty's zsh integration: surface env vars are applied after
    /// the integration sets ZDOTDIR (Ghostty's src/termio/Exec.zig), so
    /// overriding ZDOTDIR would skip it. Instead GHOSTTY_ZSH_ZDOTDIR, where
    /// Ghostty's .zshenv hands over next, points at Kana's folder. See
    /// App/Shell/zsh/.zshenv for the whole chain.
    private static func environment(settings: KanaSettings, skin: SkinInfo?, banner: Banner, paneID: String) -> [String: String] {
        var env: [String: String] = [
            "KANA": "1",
            "KANA_PANE_ID": paneID,
            "KANA_ACCENT": skin?.accentHex ?? settings.accentHex,
            "KANA_SUGGEST": settings.suggestions ? "1" : "0",
            "KANA_BANNER": banner.rawValue,
        ]
        if let skin { env["KANA_SKIN_DIR"] = skin.directory.path }
        if let bin = KanaResources.binDirectory { env["KANA_BIN_DIR"] = bin.path }
        if let zsh = KanaResources.zshDirectory {
            if let userZDOTDIR = ProcessInfo.processInfo.environment["ZDOTDIR"] {
                env["KANA_ZSH_ZDOTDIR"] = userZDOTDIR
            }
            env["GHOSTTY_ZSH_ZDOTDIR"] = zsh.path
        }
        return env
    }

    func focus() {
        surfaceView.window?.makeFirstResponder(surfaceView)
    }

    var isFocused: Bool {
        surfaceView.window?.firstResponder === surfaceView
    }

    func setVisible(_ visible: Bool) {
        surfaceView.setSurfaceVisible(visible)
    }

    /// Asks Ghostty to close the surface. It answers through `onClose`, with
    /// `processAlive` set when something is still running (Ghostty's
    /// `needsConfirmQuit`), like Ghostty's own ⌘W.
    func requestClose() {
        if !surfaceView.performBindingAction("close_surface") {
            onClose?(false)
        }
    }
}

extension TerminalSession:
    TerminalSurfaceTitleDelegate,
    TerminalSurfacePwdDelegate,
    TerminalSurfaceCloseDelegate,
    TerminalSurfaceFocusDelegate,
    TerminalSurfaceCommandFinishedDelegate,
    TerminalSurfaceDesktopNotificationDelegate,
    TerminalSurfaceBellDelegate,
    TerminalSurfaceProgressReportDelegate,
    TerminalSurfaceOpenURLDelegate,
    TerminalSurfaceHoverLinkDelegate,
    TerminalSurfaceClipboardConfirmationDelegate
{
    func terminalDidChangeTitle(_ title: String) {
        onTitleChange?(title)
    }

    func terminalDidChangeWorkingDirectory(_ path: String) {
        onWorkingDirectoryChange?(path)
    }

    func terminalDidChangeFocus(_ focused: Bool) {
        onFocusChange?(focused)
    }

    func terminalDidFinishCommand(exitCode: Int?, durationNanos: UInt64) {
        onCommandFinished?(exitCode, TimeInterval(durationNanos) / 1_000_000_000)
    }

    func terminalDidRequestDesktopNotification(title: String, body: String) {
        onNotification?(title, body)
    }

    func terminalDidRingBell() {
        onBell?()
    }

    func terminalDidReportProgress(state: TerminalProgressState, percent: Int?) {
        switch state {
        case .remove: onProgress?(nil)
        case .set: onProgress?(Progress(percent: percent))
        case .indeterminate: onProgress?(Progress(percent: nil))
        case .error: onProgress?(Progress(percent: percent, failed: true))
        case .pause: onProgress?(Progress(percent: percent, paused: true))
        }
    }

    /// ⌘-click on a URL or an OSC 8 hyperlink. Terminal output chose the
    /// target, so it goes through UntrustedURL first (like Ghostty's OSC 8
    /// handling in Ghostty.App.swift).
    func terminalDidRequestOpenURL(_ string: String, kind _: TerminalOpenURLKind) {
        switch UntrustedURL(string: string).decision {
        case let .allow(url):
            NSWorkspace.shared.open(url)
        case let .confirm(url):
            let handler = NSWorkspace.shared.urlForApplication(toOpen: url)?
                .deletingPathExtension().lastPathComponent ?? "another app"
            linkAlert("Open this link in \(handler)?", url.absoluteString, button: "Open") {
                NSWorkspace.shared.open(url)
            }
        case let .deny(reason):
            linkAlert("Kana didn't open this link", "\(string)\n\n\(reason)", button: nil, then: nil)
        }
    }

    /// Cancel comes first, so Return doesn't open an untrusted link (as in
    /// Ghostty). Shown on the next turn: this runs inside Ghostty's URL
    /// callback with the renderer locked, and the sheet's focus change would
    /// wait on that lock (Ghostty's UntrustedURLAlert defers the same way).
    private func linkAlert(_ title: String, _ detail: String, button: String?, then action: (() -> Void)?) {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.surfaceView.window, window.isVisible, window.attachedSheet == nil else { return }
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = detail
            alert.alertStyle = action == nil ? .warning : .informational
            alert.addButton(withTitle: button == nil ? "OK" : "Cancel")
            if let button { alert.addButton(withTitle: button) }
            alert.beginSheetModal(for: window) { response in
                if response == .alertSecondButtonReturn { action?() }
            }
        }
    }

    func terminalDidUpdateHoverLink(_ url: String?) {
        onHoverLink?(url)
    }

    func terminalDidClose(processAlive: Bool) {
        onClose?(processAlive)
    }

    /// Multi-line pastes into a program without bracketed paste, and OSC 52
    /// clipboard access. Without this delegate the wrapper denies them all.
    func terminalDidRequestClipboardConfirmation(_ request: TerminalClipboardConfirmationRequest) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch request.kind {
        case .paste:
            alert.messageText = "Paste this text?"
            alert.informativeText = "It may run commands as soon as it's pasted."
            alert.addButton(withTitle: "Paste")
        case .osc52Read:
            alert.messageText = "Let this program read your clipboard?"
            alert.informativeText = "A program in this terminal asked for what's on your clipboard."
            alert.addButton(withTitle: "Allow")
        case .osc52Write:
            alert.messageText = "Let this program set your clipboard?"
            alert.informativeText = "A program in this terminal wants to copy this to your clipboard."
            alert.addButton(withTitle: "Allow")
        }
        alert.addButton(withTitle: "Cancel")
        if request.kind != .osc52Read {
            alert.accessoryView = Self.preview(request.contents)
        }
        guard let window = surfaceView.window else {
            request.respond(allow: false)
            return
        }
        alert.beginSheetModal(for: window) { response in
            request.respond(allow: response == .alertFirstButtonReturn)
        }
    }

    /// A read-only box showing what would be pasted.
    private static func preview(_ text: String) -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 140))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = text.count > 4000 ? String(text.prefix(4000)) + "\n…" : text
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        return scroll
    }
}
