import Foundation

/// A skin folder: `skin.json` plus an optional intro and portrait clip.
public struct Skin: Sendable {
    public let name: String
    /// "#rrggbb"
    public let accentHex: String
    public let portraitOpacity: Double
    public let intro: KanaClip?
    /// Falls back to the intro's portrait frame when nil. Use `restingClip`.
    public let portrait: KanaClip?

    public init(name: String, accentHex: String, portraitOpacity: Double, intro: KanaClip?, portrait: KanaClip?) {
        self.name = name
        self.accentHex = accentHex
        self.portraitOpacity = portraitOpacity
        self.intro = intro
        self.portrait = portrait
    }

    /// The clip whose portrait frame the app rests on.
    public var restingClip: KanaClip? { portrait ?? intro }
}

public enum SkinLoader {
    public static let defaultAccent = "#e0262f"
    public static let defaultOpacity = 0.35

    public static func load(directory: URL) throws -> Skin {
        let manifest = directory.appendingPathComponent("skin.json")
        guard let data = try? Data(contentsOf: manifest) else { throw KanaClipError.unreadable }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw KanaClipError.malformed("skin.json is not a JSON object")
        }

        let name = (json["name"] as? String) ?? directory.lastPathComponent
        var accent = (json["accent"] as? String) ?? defaultAccent
        if !isHexColor(accent) { accent = defaultAccent }
        let opacity = min(max((json["portrait_opacity"] as? Double) ?? defaultOpacity, 0), 1)

        func clip(_ key: String, fallback: String) throws -> KanaClip? {
            let file = (json[key] as? String) ?? fallback
            let url = directory.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try KanaClipLoader.load(from: url)
        }

        let intro = try clip("intro", fallback: "intro.kana")
        let portrait = try clip("portrait", fallback: "portrait.kana")
        return Skin(name: name, accentHex: accent, portraitOpacity: opacity, intro: intro, portrait: portrait)
    }

    /// Skin folders under `root` that contain a skin.json, sorted by name.
    public static func available(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        return entries
            .filter { fm.fileExists(atPath: $0.appendingPathComponent("skin.json").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func isHexColor(_ s: String) -> Bool {
        s.count == 7 && s.hasPrefix("#") && s.dropFirst().allSatisfy(\.isHexDigit)
    }
}
