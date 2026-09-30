import Foundation

/// The handful of settings Kana reads today, from `~/.config/kana/config`
/// (Ghostty-style `key = value`, see docs/KANA.md section 11).
struct KanaSettings: Sendable {
    enum IntroMode: String, Sendable { case on, off, firstWindow = "first-window" }

    /// A skin folder name; "default" ships in the app bundle.
    var skin = "default"
    var intro = IntroMode.on
    var banner = true
    var suggestions = true
    var fontSize = 13.0
    var fontFamily: String?
    var accentHex = "#e0262f"

    static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/kana")
    }

    static func load() -> KanaSettings {
        var settings = KanaSettings()
        let url = configDirectory.appendingPathComponent("config")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return settings }
        for (key, value) in parse(text) {
            switch key {
            case "skin": settings.skin = value
            case "intro": settings.intro = IntroMode(rawValue: value) ?? settings.intro
            case "banner": settings.banner = isOn(value)
            case "suggestions": settings.suggestions = isOn(value)
            case "font-size": settings.fontSize = Double(value) ?? settings.fontSize
            case "font-family": settings.fontFamily = value.isEmpty ? nil : value
            default: break
            }
        }
        return settings
    }

    static func parse(_ text: String) -> [(String, String)] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { return nil }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            var value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            return key.isEmpty ? nil : (key, value)
        }
    }

    private static func isOn(_ value: String) -> Bool {
        !["off", "false", "no", "0"].contains(value.lowercased())
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
