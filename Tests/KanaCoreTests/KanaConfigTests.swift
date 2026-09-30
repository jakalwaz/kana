import Foundation
import KanaCore
import Testing

@Suite struct KanaConfigTests {
    private let directory = URL(fileURLWithPath: "/tmp/kana-config", isDirectory: true)
    private typealias Line = KanaConfig.GhosttyLine

    private func parse(_ text: String) -> KanaConfig {
        KanaConfig.parse(text, configDirectory: directory)
    }

    @Test func defaultsAndEmptyRender() {
        let config = parse("\u{FEFF}# comment\r\n\t # indented\n \t\r\n")
        #expect(config == KanaConfig())
        #expect(config.skin == "default")
        #expect(config.intro == .on)
        #expect(config.banner && config.suggestions)
        #expect(config.notifyOnCommandFinish == .unfocused)
        #expect(config.notifyAfter == 10)
        #expect(config.quickTerminalHotkey == "ctrl+backquote")
        #expect(config.renderGhostty(defaults: [], enforced: [], resolveTheme: { _ in
            Issue.record("nil theme must not call the resolver")
            return nil
        }).isEmpty)
    }

    @Test func orderedRoundTripAndRepeatableKeys() {
        let config = parse("""
        # First equals separates the key from the entire value.
        font-family = Mono One
        keybind = ctrl+a=text:a=b
        palette = 0=#010203
        font-family = Mono Two
        keybind = ctrl+b=ignore
        palette = 1=#abcdef
        font-family =
        unknown-future-key = enabled
        """)
        let expected = [Line("font-family", "Mono One"), Line("keybind", "ctrl+a=text:a=b"),
                        Line("palette", "0=#010203"), Line("font-family", "Mono Two"),
                        Line("keybind", "ctrl+b=ignore"), Line("palette", "1=#abcdef"),
                        Line("font-family", ""), Line("unknown-future-key", "enabled")]
        #expect(config.ghostty == expected)
        let rendered = config.renderGhostty(defaults: [], enforced: [], resolveTheme: { _ in nil })
        #expect(parse(rendered).ghostty == expected)
        #expect(config.issues.isEmpty)
    }

    @Test func kanaKeysAreStripped() {
        let config = parse("""
        skin = akira
        intro = first-window
        banner = off
        suggestions = no
        notify-on-command-finish = always
        notify-on-command-finish-after = 1m30s
        quick-terminal-hotkey = super+space
        theme = Rose Pine
        font-size = 14
        """)
        #expect(config.skin == "akira")
        #expect(config.intro == .firstWindow)
        #expect(!config.banner && !config.suggestions)
        #expect(config.notifyOnCommandFinish == .always)
        #expect(config.notifyAfter == 90)
        #expect(config.quickTerminalHotkey == "super+space")
        #expect(config.theme == "Rose Pine")
        #expect(config.ghostty == [Line("font-size", "14")])
        #expect(config.issues.isEmpty)
    }

    @Test func booleansAndEnums() {
        for value in ["on", "true", "yes", "1"] {
            let config = parse("banner = \(value)\nsuggestions = \(value)")
            #expect(config.banner && config.suggestions)
            #expect(config.issues.isEmpty)
        }
        for value in ["off", "false", "no", "0"] {
            let config = parse("banner = \(value)\nsuggestions = \(value)")
            #expect(!config.banner && !config.suggestions)
            #expect(config.issues.isEmpty)
        }
        for value in ["on", "off", "first-window"] {
            #expect(parse("intro = \(value)").intro.rawValue == value)
        }
        for value in ["never", "unfocused", "always"] {
            #expect(parse("notify-on-command-finish = \(value)").notifyOnCommandFinish.rawValue == value)
        }
    }

    @Test func badValuesRestoreDefaultsAndReportLineNumbers() {
        let config = parse("""
        # line one

        not a setting
        banner = off
        banner = maybe
        intro = off
        intro = sometimes
        suggestions = 0
        suggestions =
        notify-on-command-finish = always
        notify-on-command-finish = yes
        notify-on-command-finish-after = 2
        notify-on-command-finish-after = -1s
        font-size = 16
        also broken
        """)
        #expect(config.banner && config.suggestions)
        #expect(config.intro == .on)
        #expect(config.notifyOnCommandFinish == .unfocused)
        #expect(config.notifyAfter == 10)
        #expect(config.ghostty == [Line("font-size", "16")])
        #expect(config.issues.count == 7)
        #expect(config.issues.first == "line 3: expected key = value")
        #expect(config.issues.last == "line 15: expected key = value")
        for (issue, line) in zip(config.issues, [3, 5, 7, 9, 11, 13, 15]) {
            #expect(issue.hasPrefix("line \(line): "))
        }
    }

    @Test func durations() {
        let cases: [(String, Double)] = [
            ("0", 0), ("2.5", 2.5), ("10s", 10), ("1m30s", 90),
            ("500ms", 0.5), ("2h 3m 4s", 7384), ("1d", 86400),
            ("1w", 604800), ("1y", 31536000), ("1us", 0.000001),
            ("1µs1ns", 0.000001001), ("100ns100ns", 0.0000002),
            (" 1m\t30s ", 90), ("1s0", 0),
            ("600y", Double(UInt64.max) / 1_000_000_000),
            ("18446744073709551615ns1ns", Double(UInt64.max) / 1_000_000_000),
        ]
        for (value, expected) in cases {
            let config = parse("notify-on-command-finish-after = \"\(value)\"")
            #expect(abs(config.notifyAfter - expected) < 1e-12)
            #expect(config.issues.isEmpty, "\(value)")
        }
    }

    @Test func hotkeyTriggerSyntaxAndDefaultOnErrors() {
        for value in ["", "ctrl+backquote", "cmd+shift+KeyA", "option+ArrowUp", "ctrl++",
                      "ctrl+é", "caps_lock+f1", "super+kp_enter", "ctrl+physical:one",
                      "ctrl+F25", "control+Digit1", "alt+catch_all", "a+shift"] {
            let config = parse("quick-terminal-hotkey = \(value)")
            #expect(config.quickTerminalHotkey == value, "\(value)")
            #expect(config.issues.isEmpty, "\(value)")
        }
        for value in ["ctrl+not-a-key", "ctrl+control+a", "super+cmd+a", "a+b", "ctrl+a>b", "ctrl+e\u{301}"] {
            let config = parse("quick-terminal-hotkey = alt+x\nquick-terminal-hotkey = \(value)")
            #expect(config.quickTerminalHotkey == "ctrl+backquote", "\(value)")
            #expect(config.issues.count == 1, "\(value)")
            #expect(config.issues.first?.hasPrefix("line 2: invalid value for quick-terminal-hotkey:") == true)
        }
    }

    @Test func invalidDurations() {
        for value in ["", "-1", "-1s", "nan", "inf", "1e999", "1.5s", "1 s", "s", "1x", "1m30", "1m trailing", "18446744073709551616ns"] {
            let config = parse("notify-on-command-finish-after = \(value)")
            #expect(config.notifyAfter == 10, "\(value)")
            #expect(config.issues.count == 1, "\(value)")
        }
    }

    @Test func includePaths() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let config = parse("""
        config-file = nested/config
        config-file = ?../optional
        config-file = /absolute/config
        config-file = ?/absolute/optional
        config-file = ~/config
        config-file = ?~/optional
        config-file = "with spaces/config"
        config-file = ?"optional spaces/config"
        config-file =
        config-file = ?
        """)
        #expect(config.ghostty.map(\.value) == [
            "/tmp/kana-config/nested/config", "?/tmp/optional", "/absolute/config",
            "?/absolute/optional", "\(home)/config", "?\(home)/optional",
            "/tmp/kana-config/with spaces/config", "?/tmp/kana-config/optional spaces/config", "", "?",
        ])
        #expect(parse(config.renderGhostty(defaults: [], enforced: [], resolveTheme: { _ in nil })).ghostty == config.ghostty)
    }

    @Test func quotedValuesAndWhitespaceMatchGhostty() {
        let config = parse("\t font-family\t =\t\" spaced \"\t\r\ncommand = \"echo \\\"literal\\\" \\n #kept\"\ncolor = #123456\nword = 'single quoted'\nword = \"unmatched\nword = x # inline text\n")
        #expect(config.ghostty == [Line("font-family", " spaced "),
                                  Line("command", #"echo \"literal\" \n #kept"#),
                                  Line("color", "#123456"), Line("word", "'single quoted'"),
                                  Line("word", "\"unmatched"), Line("word", "x # inline text")])
        #expect(config.issues.isEmpty)
        #expect(parse(config.renderGhostty(defaults: [], enforced: [], resolveTheme: { _ in nil })).ghostty == config.ghostty)
    }

    @Test func renderQuotesWithoutInventingEscapes() {
        var config = KanaConfig()
        config.ghostty = [Line("a", " padded\t"), Line("b", "#abcdef"),
                          Line("c", "\"literal\""), Line("d", #"a\b"c"#), Line("e", "")]
        let rendered = config.renderGhostty(defaults: [], enforced: [], resolveTheme: { _ in nil })
        #expect(rendered == "a = \" padded\t\"\nb = \"#abcdef\"\nc = \"\"literal\"\"\nd = a\\b\"c\ne = \n")
        #expect(parse(rendered).ghostty == config.ghostty)
    }

    @Test func precedenceAndPlainThemeResolution() {
        let config = parse("font-size = 14\nkeybind = ctrl+d=ignore\ntheme = Named")
        var names: [String] = []
        let rendered = config.renderGhostty(
            defaults: [Line("font-size", "12"), Line("background", "#000000")],
            enforced: [Line("keybind", "ctrl+d=unbind")],
            resolveTheme: { names.append($0); return "/themes/\($0)" }
        )
        #expect(names == ["Named"])
        #expect(rendered == "font-size = 12\nbackground = \"#000000\"\nfont-size = 14\nkeybind = ctrl+d=ignore\ntheme = /themes/Named\nkeybind = ctrl+d=unbind\n")
        #expect(config.renderGhostty(defaults: [], enforced: [], resolveTheme: { _ in nil }).hasSuffix("theme = Named\n"))
    }

    @Test func lightDarkThemeResolutionAndMisses() {
        for source in ["light:Day,dark:Night", " light : Day , dark : Night ", "light:Day,dark:Night,"] {
            let config = parse("theme = \"\(source)\"")
            var names: [String] = []
            #expect(config.renderGhostty(defaults: [], enforced: [], resolveTheme: {
                names.append($0)
                return $0 == "Day" ? "/themes/Day" : nil
            }) == "theme = light:/themes/Day,dark:Night\n")
            #expect(names == ["Day", "Night"])
            #expect(config.renderGhostty(defaults: [], enforced: [], resolveTheme: { "/themes/\($0)" }) == "theme = light:/themes/Day,dark:/themes/Night\n")
            #expect(config.renderGhostty(defaults: [], enforced: [], resolveTheme: { _ in nil }) == "theme = light:Day,dark:Night\n")
        }
        #expect(parse("theme = dark:Night,light:Day").renderGhostty(defaults: [], enforced: [], resolveTheme: { _ in nil }) == "theme = dark:Night,light:Day\n")
    }

    @Test func rawStringsAndThemeReset() {
        let config = parse("skin = \"a custom skin\"\nquick-terminal-hotkey =\ntheme =")
        #expect(config.skin == "a custom skin")
        #expect(config.quickTerminalHotkey.isEmpty)
        #expect(config.theme == "")
        #expect(config.renderGhostty(defaults: [], enforced: [], resolveTheme: { _ in nil }) == "theme = \n")
        let absolute = parse("theme = /themes/Custom #1")
        #expect(absolute.renderGhostty(defaults: [], enforced: [], resolveTheme: { _ in nil }) == "theme = \"/themes/Custom #1\"\n")
    }

    @Test func quotedThemePairNamesAndResolvedPaths() {
        let config = parse(#"theme = light:"Day, Bright",dark:"Ni\x67ht\u{21}""#)
        var names: [String] = []
        let rendered = config.renderGhostty(defaults: [], enforced: [], resolveTheme: {
            names.append($0)
            return "/themes/\($0)"
        })
        #expect(names == ["Day, Bright", "Night!"])
        #expect(rendered == #"theme = light:"/themes/Day, Bright",dark:/themes/Night!"# + "\n")
        #expect(parse(rendered).renderGhostty(defaults: [], enforced: [], resolveTheme: { _ in nil }) == rendered)
        let literal = parse(#"theme = light:"A\\B\"C",dark:Night"#)
        names = []
        _ = literal.renderGhostty(defaults: [], enforced: [], resolveTheme: { names.append($0); return nil })
        #expect(names == [#"A\B"C"#, "Night"])
    }
}
