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
    public static func parse(_ text: String, configDirectory: URL) -> KanaConfig {
        var config = KanaConfig()
        let defaults = KanaConfig()
        // Config.loadReader skips a UTF-8 BOM; LineIterator splits on LF.
        let text = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        for (index, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r"))
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let equals = line.firstIndex(of: "=") else {
                config.issues.append("line \(index + 1): expected key = value")
                continue
            }
            let key = trim(String(line[..<equals]))
            var value = trim(String(line[line.index(after: equals)...]))
            // File values are NOT Zig string literals: only the outer quotes
            // are removed. Backslashes and embedded quotes remain literal.
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            var valid = true
            switch key {
            case "skin": config.skin = value
            case "intro":
                let parsed = IntroMode(rawValue: value)
                valid = parsed != nil
                config.intro = parsed ?? defaults.intro
            case "banner":
                let parsed = boolean(value)
                valid = parsed != nil
                config.banner = parsed ?? defaults.banner
            case "suggestions":
                let parsed = boolean(value)
                valid = parsed != nil
                config.suggestions = parsed ?? defaults.suggestions
            case "notify-on-command-finish":
                let parsed = NotifyMode(rawValue: value)
                valid = parsed != nil
                config.notifyOnCommandFinish = parsed ?? defaults.notifyOnCommandFinish
            case "notify-on-command-finish-after":
                let parsed = duration(value)
                valid = parsed != nil
                config.notifyAfter = parsed ?? defaults.notifyAfter
            case "quick-terminal-hotkey":
                valid = validHotkey(value)
                config.quickTerminalHotkey = valid ? value : defaults.quickTerminalHotkey
            case "theme": config.theme = value
            default:
                if key == "config-file" {
                    value = includePath(value, directory: configDirectory)
                }
                config.ghostty.append(GhosttyLine(key, value))
            }
            if !valid {
                config.issues.append("line \(index + 1): invalid value for \(key): \(value)")
            }
        }
        return config
    }

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
    ) -> String {
        var lines = defaults + ghostty
        if let theme {
            lines.append(GhosttyLine("theme", Self.resolvedTheme(theme, resolve: resolveTheme)))
        }
        lines += enforced
        return lines.map { "\($0.key) = \(Self.quoted($0.value))\n" }.joined()
    }

    private static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
    }

    private static func boolean(_ value: String) -> Bool? {
        switch value {
        case "on", "true", "yes", "1": true
        case "off", "false", "no", "0": false
        default: nil
        }
    }

    private static func validHotkey(_ value: String) -> Bool {
        // Empty disables the shortcut. Otherwise follow input.Binding.Trigger.parse
        // from the pinned Ghostty source, including modifier aliases and literal +.
        if value.isEmpty { return true }
        let aliases = ["cmd": "super", "command": "super", "opt": "alt",
                       "option": "alt", "control": "ctrl"]
        let modifiers: Set<String> = ["shift", "ctrl", "alt", "super", "caps_lock", "num_lock"]
        var seen: Set<String> = []
        var hasKey = false
        var parts = value.components(separatedBy: "+")
        if parts.last == "" { parts.removeLast() }
        for part in parts {
            let modifier = aliases[part] ?? part
            if modifiers.contains(modifier) {
                guard seen.insert(modifier).inserted else { return false }
                continue
            }
            guard !hasKey else { return false }
            let w3c = part.enumerated().map { index, character -> String in
                if character.isASCII && (character.isUppercase || character.isNumber) {
                    return (index == 0 ? "" : "_") + String(character).lowercased()
                }
                return String(character)
            }.joined()
            guard part.isEmpty || part.unicodeScalars.count == 1 || part == "catch_all"
                    || triggerKeys.contains(part.lowercased()) || triggerKeys.contains(w3c)
                    || legacyTriggerKeys.contains(part) else { return false }
            // fromW3C can return unidentified, which still counts as an unset key.
            hasKey = part.lowercased() != "unidentified"
        }
        return true
    }

    // Key names/compatibility names from Ghostty's input/key.zig and Binding.zig
    // at 0538f7535be0. Keep in sync when the libghostty pin changes.
    private static let triggerKeys: Set<String> = Set("""
        unidentified backquote backslash bracket_left bracket_right comma digit_0 digit_1 digit_2 digit_3
        digit_4 digit_5 digit_6 digit_7 digit_8 digit_9 equal intl_backslash intl_ro intl_yen key_a key_b
        key_c key_d key_e key_f key_g key_h key_i key_j key_k key_l key_m key_n key_o key_p key_q key_r
        key_s key_t key_u key_v key_w key_x key_y key_z minus period quote semicolon slash alt_left
        alt_right backspace caps_lock context_menu control_left control_right enter meta_left meta_right
        shift_left shift_right space tab convert kana_mode non_convert delete end help home insert page_down
        page_up arrow_down arrow_left arrow_right arrow_up num_lock numpad_0 numpad_1 numpad_2 numpad_3
        numpad_4 numpad_5 numpad_6 numpad_7 numpad_8 numpad_9 numpad_add numpad_backspace numpad_clear
        numpad_clear_entry numpad_comma numpad_decimal numpad_divide numpad_enter numpad_equal
        numpad_memory_add numpad_memory_clear numpad_memory_recall numpad_memory_store
        numpad_memory_subtract numpad_multiply numpad_paren_left numpad_paren_right numpad_subtract
        numpad_separator numpad_up numpad_down numpad_right numpad_left numpad_begin numpad_home numpad_end
        numpad_insert numpad_delete numpad_page_up numpad_page_down escape f1 f2 f3 f4 f5 f6 f7 f8 f9 f10
        f11 f12 f13 f14 f15 f16 f17 f18 f19 f20 f21 f22 f23 f24 f25 fn fn_lock print_screen scroll_lock
        pause browser_back browser_favorites browser_forward browser_home browser_refresh browser_search
        browser_stop eject launch_app_1 launch_app_2 launch_mail media_play_pause media_select media_stop
        media_track_next media_track_previous power sleep audio_volume_down audio_volume_mute
        audio_volume_up wake_up copy cut paste
        """.split(whereSeparator: { $0.isWhitespace }).map(String.init))

    private static let legacyTriggerKeys: Set<String> = Set("""
        zero one two three four five six seven eight nine plus apostrophe grave_accent left_bracket
        right_bracket up down left right kp_0 kp_1 kp_2 kp_3 kp_4 kp_5 kp_6 kp_7 kp_8 kp_9 kp_add
        kp_subtract kp_multiply kp_divide kp_decimal kp_enter kp_equal kp_separator kp_left kp_right kp_up
        kp_down kp_page_up kp_page_down kp_home kp_end kp_insert kp_delete kp_begin left_shift right_shift
        left_control right_control left_alt right_alt left_super right_super physical:zero physical:one
        physical:two physical:three physical:four physical:five physical:six physical:seven physical:eight
        physical:nine physical:apostrophe physical:grave_accent physical:left_bracket physical:right_bracket
        physical:up physical:down physical:left physical:right physical:kp_0 physical:kp_1 physical:kp_2
        physical:kp_3 physical:kp_4 physical:kp_5 physical:kp_6 physical:kp_7 physical:kp_8 physical:kp_9
        physical:kp_add physical:kp_subtract physical:kp_multiply physical:kp_divide physical:kp_decimal
        physical:kp_enter physical:kp_equal physical:kp_separator physical:kp_left physical:kp_right
        physical:kp_up physical:kp_down physical:kp_page_up physical:kp_page_down physical:kp_home
        physical:kp_end physical:kp_insert physical:kp_delete physical:kp_begin physical:left_shift
        physical:right_shift physical:left_control physical:right_control physical:left_alt
        physical:right_alt physical:left_super physical:right_super
        """.split(whereSeparator: { $0.isWhitespace }).map(String.init))

    private static func duration(_ value: String) -> Double? {
        let value = value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\u{0B}\u{0C}"))
        // Kana additionally accepts a bare (possibly fractional) seconds value.
        if let seconds = Double(value), seconds.isFinite, seconds >= 0 {
            return seconds
        }
        let units: [(String, UInt64)] = [
            ("ms", 1_000_000), ("µs", 1_000), ("us", 1_000), ("ns", 1),
            ("y", 31_536_000_000_000_000), ("w", 604_800_000_000_000),
            ("d", 86_400_000_000_000), ("h", 3_600_000_000_000),
            ("m", 60_000_000_000), ("s", 1_000_000_000),
        ]
        var remaining = value[...]
        var total: UInt64 = 0
        var found = false
        while !remaining.isEmpty {
            remaining = remaining.drop(while: { " \t\r\n\u{0B}\u{0C}".contains($0) })
            if remaining.isEmpty { break }
            let digits = remaining.prefix(while: { $0.isASCII && $0.isNumber })
            guard !digits.isEmpty, let number = UInt64(digits) else { return nil }
            remaining = remaining.dropFirst(digits.count)
            // Ghostty treats a terminal unitless zero as zero for the entire duration.
            if remaining.isEmpty, number == 0 { return 0 }
            guard let (unit, factor) = units.first(where: { remaining.hasPrefix($0.0) }) else {
                return nil
            }
            remaining = remaining.dropFirst(unit.count)
            let product = number.multipliedReportingOverflow(by: factor)
            let sum = total.addingReportingOverflow(product.overflow ? .max : product.partialValue)
            total = sum.overflow ? .max : sum.partialValue
            found = true
        }
        return found ? Double(total) / 1_000_000_000 : nil
    }

    private static func includePath(_ value: String, directory: URL) -> String {
        // Preserve an empty value: it resets the list of includes.
        guard !value.isEmpty else { return value }
        let optional = value.hasPrefix("?")
        var path = optional ? String(value.dropFirst()) : value
        // Path.parse also permits quotes after the optional marker.
        if path.count >= 2, path.hasPrefix("\""), path.hasSuffix("\"") {
            path = String(path.dropFirst().dropLast())
        }
        guard !path.isEmpty else { return optional ? "?" : "" }
        let absolute: String
        if path.hasPrefix("~/") {
            absolute = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2))).standardizedFileURL.path
        } else if path.hasPrefix("/") {
            absolute = path
        } else {
            absolute = directory.appendingPathComponent(path).standardizedFileURL.path
        }
        return (optional ? "?" : "") + absolute
    }

    private static func resolvedTheme(_ theme: String, resolve: (String) -> String?) -> String {
        guard let pair = themePair(theme) else { return resolve(theme) ?? theme }
        return pair.map { mode, name in
            "\(mode):\(quotedThemeName(resolve(name) ?? name))"
        }.joined(separator: ",")
    }

    private static func themePair(_ theme: String) -> [(String, String)]? {
        // Theme.parseCLI uses CommaSplitter, then parseAutoStruct. Unlike the
        // outer file parser, double-quoted struct values are Zig strings.
        var parts: [String] = []
        var part = ""
        var inQuotes = false
        var escaped = false
        for character in theme {
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                parts.append(part)
                part = ""
                continue
            }
            part.append(character)
        }
        guard !inQuotes, !escaped else { return nil }
        // CommaSplitter.next() stops at EOF, allowing a trailing comma.
        if !part.isEmpty { parts.append(part) }
        guard parts.count == 2 else { return nil }
        var result: [(String, String)] = []
        for part in parts {
            guard let colon = part.firstIndex(of: ":") else { return nil }
            let mode = trim(String(part[..<colon]))
            guard mode == "light" || mode == "dark" else { return nil }
            let raw = trim(String(part[part.index(after: colon)...]))
            let name: String
            if raw.hasPrefix("\"") {
                guard raw.count >= 2, raw.hasSuffix("\""),
                      let decoded = decodeThemeName(String(raw.dropFirst().dropLast())) else { return nil }
                name = decoded
            } else {
                name = raw
            }
            result.append((mode, name))
        }
        return result[0].0 != result[1].0 ? result : nil
    }

    private static func decodeThemeName(_ text: String) -> String? {
        var input = ArraySlice(text.utf8)
        var output: [UInt8] = []
        while let byte = input.popFirst() {
            guard byte == 92 else {
                guard byte != 34, byte >= 32 else { return nil }
                output.append(byte)
                continue
            }
            guard let escape = input.popFirst() else { return nil }
            switch escape {
            case 110: output.append(10) // n
            case 114: output.append(13) // r
            case 116: output.append(9) // t
            case 92, 39, 34: output.append(escape)
            case 120: // xNN: byte escape
                let digits = input.prefix(2)
                guard digits.count == 2, let value = UInt8(String(decoding: digits, as: UTF8.self), radix: 16) else {
                    return nil
                }
                output.append(value)
                input = input.dropFirst(2)
            case 117: // u{NNNN}: Unicode scalar escape
                guard input.popFirst() == 123, let end = input.firstIndex(of: 125),
                      let value = UInt32(String(decoding: input[..<end], as: UTF8.self), radix: 16),
                      let scalar = Unicode.Scalar(value) else { return nil }
                output.append(contentsOf: String(scalar).utf8)
                input = input[input.index(after: end)...]
            default: return nil
            }
        }
        return String(bytes: output, encoding: .utf8)
    }

    private static func quotedThemeName(_ name: String) -> String {
        guard name != trim(name) || name.contains(where: { ",\"\\\n\r\t".contains($0) }) else { return name }
        var escaped = ""
        for character in name {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default: escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }

    private static func quoted(_ value: String) -> String {
        // LineIterator does no escape decoding (unlike parseAutoStruct).
        // Adding backslashes here would change the value Ghostty receives.
        let needsQuotes = value != value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r"))
            || value.contains("#")
            || (value.count >= 2 && value.hasPrefix("\"") && value.hasSuffix("\""))
        return needsQuotes ? "\"\(value)\"" : value
    }
}
