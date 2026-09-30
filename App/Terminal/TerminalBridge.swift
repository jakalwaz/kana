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

/// Kana's terminal look: pure black, one accent colour.
enum KanaTheme {
    static let background = "000000"
    static let foreground = "E6E6E6"

    static func configuration(accentHex: String) -> TerminalConfiguration {
        let accent = accentHex.replacingOccurrences(of: "#", with: "")
        return TerminalConfiguration { b in
            b.withBackground(background)
            b.withForeground(foreground)
            b.withCursorColor(accent)
            b.withCursorText(background)
            b.withSelectionBackground("2B2B2B")
            b.withSelectionForeground("FFFFFF")
            // Normal 0-7
            b.withPalette(0, color: "#1A1A1A")
            b.withPalette(1, color: "#\(accent)")
            b.withPalette(2, color: "#5FD38D")
            b.withPalette(3, color: "#F2C063")
            b.withPalette(4, color: "#5FA8FF")
            b.withPalette(5, color: "#C78CFF")
            b.withPalette(6, color: "#4FD6D6")
            b.withPalette(7, color: "#D0D0D0")
            // Bright 8-15. 8 is the grey of inline suggestions: readable, but quiet.
            b.withPalette(8, color: "#666666")
            b.withPalette(9, color: "#FF4B55")
            b.withPalette(10, color: "#7EF0A8")
            b.withPalette(11, color: "#FFD580")
            b.withPalette(12, color: "#8CC4FF")
            b.withPalette(13, color: "#DDB0FF")
            b.withPalette(14, color: "#7EF0F0")
            b.withPalette(15, color: "#FFFFFF")
        }
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
            "super+q", "super+,",
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

    static func controller(settings: KanaSettings) -> TerminalController {
        if let controller { return controller }
        let dark = KanaTheme.configuration(accentHex: settings.accentHex)
        let made = TerminalController(theme: TerminalTheme(light: dark, dark: dark)) { b in
            b.withFontSize(Float(settings.fontSize))
            if let family = settings.fontFamily { b.withFontFamily(family) }
            b.withFontThicken(false)
            b.withCursorStyle(.bar)
            b.withCursorStyleBlink(true)
            b.withBackgroundOpacity(1)
            b.withWindowPaddingX(14)
            b.withWindowPaddingY(8)
            b.withCustom("window-padding-balance", "true")
            b.withCustom("mouse-hide-while-typing", "true")
            b.withCustom("shell-integration-features", "cursor,title")
            for key in keysKanaOwns {
                b.withCustom("keybind", "\(key)=unbind")
            }
        }
        if let issue = made.lastConfigurationIssue {
            NSLog("Kana: ghostty config issue: %@", issue)
        }
        controller = made
        return made
    }
}

/// One shell in one libghostty surface.
@MainActor
final class TerminalSession: NSObject {
    let view: NSView
    let paneID = UUID().uuidString

    var onTitleChange: ((String) -> Void)?
    var onFocusChange: ((Bool) -> Void)?
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
