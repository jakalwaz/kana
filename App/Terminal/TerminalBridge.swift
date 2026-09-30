// The only file that talks to libghostty (through libghostty-spm's
// GhosttyTerminal wrapper, which owns the ghostty.h calls). Everything else in
// Kana goes through `TerminalSession`, so a Ghostty bump only touches here.
//
// Based on libghostty-spm's Example/GhosttyTerminalApp (surface setup) and
// Ghostty's macos/Sources/Ghostty/Ghostty.Config.swift (keybind handling).

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
    /// windows, Focus Mode). While ghostty owns them, the keys never reach
    /// Kana's menu. See `default` keybinds in Ghostty's src/config/Config.zig.
    private static let keysKanaOwns: [String] = {
        var keys = [
            "super+t", "super+n", "super+w", "super+alt+w", "super+shift+w", "super+shift+alt+w",
            "super+shift+[", "super+shift+]", "super+d", "super+shift+d", "super+[", "super+]",
            "super+shift+f", "super+alt+p", "super+alt+i", "super+ctrl+f", "super+enter",
            "super+shift+enter",
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
    var onWorkingDirectoryChange: ((String) -> Void)?
    var onClose: (() -> Void)?

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

    /// Shell environment. ZDOTDIR loads Kana's zsh layer (suggestions, prompt,
    /// welcome screen) ahead of the user's own startup files; see
    /// App/Shell/zsh/.zshenv.
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
            env["ZDOTDIR"] = zsh.path
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
}

extension TerminalSession:
    TerminalSurfaceTitleDelegate,
    TerminalSurfacePwdDelegate,
    TerminalSurfaceCloseDelegate
{
    func terminalDidChangeTitle(_ title: String) {
        onTitleChange?(title)
    }

    func terminalDidChangeWorkingDirectory(_ path: String) {
        onWorkingDirectoryChange?(path)
    }

    func terminalDidClose(processAlive _: Bool) {
        onClose?()
    }
}
