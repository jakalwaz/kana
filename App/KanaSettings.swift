import Foundation
import KanaCore

/// `~/.config/kana/config` (docs/KANA.md section 11): Ghostty's format. Kana's
/// own keys are read here; every other line is Ghostty's and goes into the
/// config file TerminalBridge renders (KanaConfig, contract C3).
struct KanaSettings: Sendable {
    typealias IntroMode = KanaConfig.IntroMode

    var config = KanaConfig()
    var accentHex = "#e0262f"

    /// A skin folder name; "default" ships in the app bundle.
    var skin: String { config.skin }
    var intro: IntroMode { config.intro }
    var banner: Bool { config.banner }
    var suggestions: Bool { config.suggestions }

    /// `~/.config/kana`, or KANA_CONFIG_DIR when set (screenshots, tests).
    static var configDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["KANA_CONFIG_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/kana")
    }

    static var configFile: URL { configDirectory.appendingPathComponent("config") }

    /// A missing file is fine: everything has a default.
    static func load() -> KanaSettings {
        let text = (try? String(contentsOf: configFile, encoding: .utf8)) ?? ""
        return KanaSettings(config: KanaConfig.parse(text, configDirectory: configDirectory))
    }
}

/// Colour themes: `~/.config/kana/themes/<name>` first, then the ones bundled
/// in Kana.app (iTerm2-Color-Schemes, vendored by tools/themes).
enum ThemeLibrary {
    static var directories: [URL] {
        var dirs = [KanaSettings.configDirectory.appendingPathComponent("themes")]
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("themes") { dirs.append(bundled) }
        return dirs
    }

    /// The theme file for a name, or nil to leave it to Ghostty (an absolute
    /// path, or a name we don't have).
    static func path(for name: String) -> String? {
        guard !name.hasPrefix("/"), !name.contains("/") else { return nil }
        return directories
            .map { $0.appendingPathComponent(name).path }
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    /// `light:X,dark:Y` split into its two names, or nil for a single theme.
    static func pair(_ theme: String) -> (light: String, dark: String)? {
        var light: String?, dark: String?
        // commas inside quotes belong to the name
        var parts: [String] = [], current = "", quoted = false
        for c in theme {
            if c == "\"" { quoted.toggle() }
            if c == ",", !quoted { parts.append(current); current = "" } else { current.append(c) }
        }
        parts.append(current)
        for part in parts where !part.trimmingCharacters(in: .whitespaces).isEmpty {
            let side = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard side.count == 2 else { return nil }
            let name = side[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if side[0] == "light" { light = name } else if side[0] == "dark" { dark = name } else { return nil }
        }
        guard let light, let dark else { return nil }
        return (light, dark)
    }

    /// A theme file's `background`, for window chrome when Ghostty's own
    /// resolved colour can't be trusted (a light/dark pair after the system
    /// appearance changes).
    static func background(ofTheme name: String) -> String? {
        guard let path = path(for: name) ?? (name.hasPrefix("/") ? name : nil),
              let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let kv = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0] == "background" { return kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }
        return nil
    }

    /// Every theme name, sorted, for the palette.
    static var names: [String] {
        let all = directories.flatMap { (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) ?? [] }
        return Set(all.filter { !$0.hasPrefix(".") && $0 != "LICENSE" }).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}

enum KanaResources {
    /// The `kana` command (script/build puts it in Contents/Resources/bin).
    /// Not there in a plain `swift run`; the zsh layer then skips the banner.
    static var binDirectory: URL? {
        guard let bin = Bundle.main.resourceURL?.appendingPathComponent("bin"),
              FileManager.default.isExecutableFile(atPath: bin.appendingPathComponent("kana").path)
        else { return nil }
        return bin
    }

    /// Kana's zsh layer. In Kana.app it sits in Contents/Resources/zsh
    /// (script/build puts it there); in a plain `swift run` it comes from the
    /// SwiftPM resource bundle.
    static var zshDirectory: URL? {
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("zsh")
            if FileManager.default.fileExists(atPath: bundled.appendingPathComponent(".zshenv").path) {
                return bundled
            }
        }
        return Bundle.module.url(forResource: "zsh", withExtension: nil)
    }
}
