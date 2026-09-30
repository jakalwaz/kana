import AppKit

/// Finds the active skin folder: `skin = <name>` in the config, looked up in
/// ~/.config/kana/skins/, then the app's bundled skins, falling back to
/// the bundled `default`. The app only needs
/// the folder and the accent colour; the `kana` command loads the clips.
struct SkinInfo: Sendable {
    let directory: URL
    let name: String
    let accentHex: String
}

@MainActor
enum SkinManager {
    private static var cache: SkinInfo??

    static func find(settings: KanaSettings) -> SkinInfo? {
        if let cache { return cache }
        var found: SkinInfo?
        // A missing or misspelt skin falls back to the bundled default.
        let names = settings.skin == "default" ? ["default"] : [settings.skin, "default"]
        let candidates = names.flatMap { name in searchRoots.map { $0.appendingPathComponent(name) } }
        for dir in candidates {
            let manifest = dir.appendingPathComponent("skin.json")
            guard let data = try? Data(contentsOf: manifest),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }
            let accent = (json["accent"] as? String).flatMap { NSColor(hex: $0) != nil ? $0 : nil } ?? settings.accentHex
            found = SkinInfo(directory: dir, name: (json["name"] as? String) ?? dir.lastPathComponent, accentHex: accent)
            break
        }
        cache = .some(found)
        return found
    }

    private static var searchRoots: [URL] {
        var roots = [KanaSettings.configDirectory.appendingPathComponent("skins")]
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("skins") {
            roots.append(bundled)
        }
        return roots
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
