import AppKit
import UniformTypeIdentifiers

/// Whether a link from terminal output is safe to open. Ported from
/// Ghostty's macos/Sources/Helpers/UntrustedURL.swift (MIT). Ghostty applies
/// it to OSC 8 targets only; libghostty-spm doesn't say which links came from
/// OSC 8, so Kana applies it to every ⌘-click. A program can print a link to
/// an app or script, and opening it would run it.
struct UntrustedURL {
    enum Decision: Equatable {
        /// http(s), mailto, and plain local files and folders.
        case allow(URL)
        /// A custom scheme, which hands the URL to whatever app claims it.
        case confirm(URL)
        case deny(String)
    }

    let string: String

    var decision: Decision {
        guard !string.isEmpty else { return .deny("The link is empty.") }
        guard !string.unicodeScalars.contains(where: Self.isUnsafeCharacter) else {
            return .deny("The link contains hidden or direction-changing characters.")
        }
        // No scheme means a path (Ghostty's Ghostty.App.swift openURL).
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
            let path = (string as NSString).expandingTildeInPath
            guard path.hasPrefix("/") else { return .deny("The link isn't a URL or a full path.") }
            return Self.fileDecision(URL(fileURLWithPath: path))
        }
        switch scheme {
        case "http", "https":
            guard let host = url.host, !host.isEmpty else { return .deny("The web address has no host.") }
            return .allow(url)
        case "mailto":
            guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), !parts.path.isEmpty else {
                return .deny("The mail link has no address.")
            }
            return .allow(url)
        case "file":
            return Self.fileDecision(url)
        default:
            return .confirm(url)
        }
    }

    private static func fileDecision(_ url: URL) -> Decision {
        guard url.isFileURL, url.query == nil, url.fragment == nil else { return .deny("The file link is malformed.") }
        if let host = url.host, !host.isEmpty, host.caseInsensitiveCompare("localhost") != .orderedSame {
            return .deny("The file link points at another machine.")
        }
        // Judge what it really is: no hiding an app behind .. or a symlink.
        let target = url.standardizedFileURL.resolvingSymlinksInPath()
        guard let values = try? target.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isExecutableKey, .isRegularFileKey]),
              values.isDirectory == true || values.isRegularFile == true
        else { return .deny("The file doesn't exist or can't be read.") }
        if unsafeExtensions.contains(target.pathExtension.lowercased())
            || values.contentType.map({ type in unsafeTypes.contains { type.conforms(to: $0) } }) == true
            || (values.isDirectory != true && values.isExecutable == true)
        {
            return .deny("It's an app, script or executable, and opening it would run it.")
        }
        return .allow(target)
    }

    private static func isUnsafeCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00 ... 0x1F, 0x7F ... 0x9F: true // controls, incl. CR/LF/NEL
        case 0x061C, 0x200B ... 0x200F, 0x202A ... 0x202E, 0x2066 ... 0x2069: true // bidi, zero-width
        case 0x2028 ... 0x2029, 0x2060, 0xFEFF: true // separators, joiners, BOM
        default: false
        }
    }

    private static let unsafeExtensions: Set<String> = [
        "action", "app", "applescript", "class", "command", "desktop", "inetloc", "jar",
        "mobileconfig", "mpkg", "pkg", "scpt", "terminal", "tool", "url", "webloc", "workflow",
    ]

    private static let unsafeTypes: [UTType] = [.application, .executable, .script]
}
