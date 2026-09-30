// Contract C3 (TASKS.md): Kana's config file, `~/.config/kana/config`.
//
// It's Ghostty's config format (docs/KANA.md section 11): `key = value`
// lines, `#` comments, repeatable keys. A few keys are Kana's own; every
// other line is Ghostty's, passed through untouched and in order, so any
// Ghostty option (fonts, keybinds, palette, scrollback...) just works.
//
// Pure Foundation: parsed here, rendered into the Ghostty config file the app
// hands to libghostty.

import Foundation

public struct KanaConfig: Sendable, Equatable {
    public enum IntroMode: String, Sendable, Equatable {
        case on, off
        case firstWindow = "first-window"
    }

    public enum NotifyMode: String, Sendable, Equatable {
        case never, unfocused, always
    }

    /// One `key = value` line for Ghostty, value unquoted as Ghostty would
    /// read it. An empty value is kept: in Ghostty it resets the key.
    public struct GhosttyLine: Sendable, Equatable {
        public let key: String
        public let value: String
        public init(_ key: String, _ value: String) {
            self.key = key
            self.value = value
        }
    }

    // Kana's own keys. Anything else is Ghostty's.

    /// `skin`
    public var skin = "default"
    /// `intro`
    public var intro = IntroMode.on
    /// `banner`: on/off (also true/false, yes/no, 1/0)
    public var banner = true
    /// `suggestions`: on/off
    public var suggestions = true
    /// `notify-on-command-finish`: Kana's default is `unfocused`
    /// (Ghostty's is `never`). Kana posts these itself, so this key is not
    /// passed to Ghostty.
    public var notifyOnCommandFinish = NotifyMode.unfocused
    /// `notify-on-command-finish-after`, in seconds. Accepts Ghostty's
    /// duration syntax: `10s`, `1m30s`, `500ms`, or a bare number of seconds.
    public var notifyAfter: Double = 10
    /// `quick-terminal-hotkey`, in Ghostty's trigger syntax, e.g. `ctrl+backquote`.
    /// Empty turns the quick terminal's hotkey off.
    public var quickTerminalHotkey = "ctrl+backquote"
    /// `theme`, raw: a name, an absolute path, or `light:X,dark:Y`. nil when
    /// unset. Not passed through as is: see `renderGhostty`.
    public var theme: String?

    /// Every Ghostty line, in file order.
    public var ghostty: [GhosttyLine] = []

    /// Lines that couldn't be read, e.g. `line 12: expected key = value`, and
    /// bad values for Kana's keys (the key keeps its default).
    public var issues: [String] = []

    public init() {}

    /// Reads the file's text. `configDirectory` is where the file lives:
    /// relative `config-file = ...` includes are made absolute against it,
    /// because Ghostty reads the rendered copy from somewhere else. (Ghostty's
    /// `?` prefix for optional includes is kept in front of the path.)
    public static func parse(_ text: String, configDirectory: URL) -> KanaConfig { fatalError("T1.3") }

    /// The whole Ghostty config: `defaults` first, then the user's `ghostty`
    /// lines, then the theme, then `enforced` last so it wins (Kana's
    /// keybind unbinds). The theme line is `theme = <resolved>`, where each
    /// name (both sides of `light:X,dark:Y`) goes through `resolveTheme`,
    /// and a name it returns nil for is written unchanged. No theme line
    /// when `theme` is nil. Values that need it are quoted so Ghostty reads
    /// them back exactly.
    public func renderGhostty(
        defaults: [GhosttyLine],
        enforced: [GhosttyLine],
        resolveTheme: (String) -> String?
    ) -> String { fatalError("T1.3") }
}
