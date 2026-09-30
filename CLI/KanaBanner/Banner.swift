import Foundation
import KanaSkins

/// Kana's welcome screen, printed into the terminal so it stays in the
/// scrollback. One box:
///
///   ╭─── Kana カナ 0.1.0 ──────────────────────────────────────────╮  head
///   │                ██╗  ██╗ █████╗ ███╗   ██╗ █████╗            │
///   │                (KANA wordmark)                              │
///   │      [ the skin's whole animation, as big as fits,        ] │  art
///   │      [ playing, then resting on its last frame            ] │
///   ╰─ ~/code · skin akira ──────── kana keys · kana replays it ─╯  bottom
///
/// While it plays the box is closed right under the art. Then the bottom
/// line slides down and the panels (keys, suggestions, features) appear
/// above it as it goes.
public struct Banner {
    public static let version = "0.1.0"

    public struct Options {
        public var columns: Int
        public var rows: Int
        public var accent: RGB
        public var workingDirectory: String
        public var skinName: String?
        public var clip: KanaClip?

        public init(columns: Int, rows: Int, accent: RGB, workingDirectory: String, skinName: String?, clip: KanaClip?) {
            self.columns = columns
            self.rows = rows
            self.accent = accent
            self.workingDirectory = workingDirectory
            self.skinName = skinName
            self.clip = clip
        }
    }

    /// Top border and wordmark.
    public let head: [String]
    /// The boxed panel lines the bottom line uncovers as it slides down.
    public let panels: [String]
    /// The bottom border.
    public let bottom: String
    /// The clip scaled to the box, or nil when there's no clip or room.
    public let clip: KanaClip?
    public var artHeight: Int { clip?.height ?? 0 }
    public var height: Int { head.count + artHeight + panels.count + 1 }

    let boxWidth: Int
    let artIndent: Int
    let side: String

    // MARK: content

    static let wordmark = [
        "██╗  ██╗ █████╗ ███╗   ██╗ █████╗ ",
        "██║ ██╔╝██╔══██╗████╗  ██║██╔══██╗",
        "█████╔╝ ███████║██╔██╗ ██║███████║",
        "██╔═██╗ ██╔══██║██║╚██╗██║██╔══██║",
        "██║  ██╗██║  ██║██║ ╚████║██║  ██║",
        "╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝",
    ]
    static let wordmarkWidth = 34

    struct Section {
        let title: String
        let items: [(String, String)] // (keys, what)
    }

    static let keys = Section(title: "Keys", items: [
        ("⌘T", "new tab"),
        ("⌘D", "split right"),
        ("⌘⇧D", "split down"),
        ("⌘1…9", "go to tab"),
        ("⌘⌥←→", "move split"),
        ("⌘⇧↩", "zoom split"),
        ("⌘W", "close"),
        ("⌘⇧F", "focus mode"),
        ("⌘↑ ↓", "prompts"),
    ])

    static let suggestions = Section(title: "Suggestions", items: [
        ("Tab →", "accept"),
        ("⌥→", "one word"),
        ("⌃⌥Space", "on / off"),
    ])

    static let features = Section(title: "In Kana", items: [
        ("✦", "libghostty engine"),
        ("✦", "smart suggestions"),
        ("◇", "soon: AI, agents"),
    ])

    // MARK: layout

    public init(_ o: Options) {
        let columns = max(40, o.columns)
        boxWidth = columns
        let inner = boxWidth - 4
        let accent = o.accent
        let border = accent.mix(.black, 0.25)
        let side = Ansi.paint("│", border)
        self.side = side

        // head: top border, wordmark
        var headLines: [String] = []
        let title = " " + Ansi.plain("Kana", bold: true) + " " + Ansi.paint("カナ", accent)
            + " " + Ansi.paint(Self.version, .grey) + " "
        let titleWidth = Ansi.visibleWidth(title)
        headLines.append(Ansi.paint("╭───", border) + title
            + Ansi.paint(String(repeating: "─", count: max(0, boxWidth - 5 - titleWidth)) + "╮", border))
        let mark = inner >= Self.wordmarkWidth
            ? Self.paintWordmark(accent: accent)
            : [Ansi.paint("K A N A", accent, bold: true)]
        headLines += mark.map { Self.boxed(Ansi.fit($0, inner, align: .center), inner: inner, side: side) }

        // panels, uncovered after the art plays, then the bottom border
        var panelLines = [Self.boxed("", inner: inner, side: side)]
        panelLines += Self.panels(accent: accent, inner: inner).map { Self.boxed($0, inner: inner, side: side) }
        let bottomLine = Self.bottomBorder(o, width: boxWidth, border: border, accent: accent)

        // art: the whole picture, never cropped, as big as fits: the box's
        // width, or less when the window is short. Head, art and the bottom
        // line should be on screen together while it plays.
        var scaled: KanaClip?
        var indent = 0
        if let clip = o.clip.map(Self.prepared), clip.width > 0, clip.height > 0 {
            let size = Self.artSize(inner: inner, rows: o.rows, headCount: headLines.count,
                                    footCount: panelLines.count + 1,
                                    clipWidth: clip.width, clipHeight: clip.height)
            if size.width >= 20, size.height >= 5 {
                scaled = AsciiResampler.resample(clip, width: size.width, height: size.height)
                indent = (inner - size.width) / 2
            }
        }
        clip = scaled
        artIndent = indent
        self.head = headLines
        panels = panelLines
        bottom = bottomLine
    }

    /// Head lines: top border and six wordmark rows.
    static let headCount = 7

    /// The clip as it's drawn: blank edges trimmed, and no empty rows above
    /// the subject in the frame it rests on.
    static func prepared(_ clip: KanaClip) -> KanaClip {
        AsciiResampler.trimmedTopForRest(AsciiResampler.trimmed(clip))
    }

    /// The art's size for a clip of this shape: as wide as the box, keeping
    /// its aspect, and short enough that the finished screen (head, art,
    /// panels, bottom line) plus the two-line prompt fits, so the wordmark
    /// is still in view at the end. Tiny windows get at least 10 rows.
    static func artSize(inner: Int, rows: Int, headCount: Int, footCount: Int, clipWidth: Int, clipHeight: Int) -> (width: Int, height: Int) {
        var width = inner
        var height = Int((Double(width) * Double(clipHeight) / Double(clipWidth)).rounded())
        let room = max(min(10, rows - 2), rows - headCount - footCount - 2)
        if height > room {
            height = room
            width = Int((Double(height) * Double(clipWidth) / Double(clipHeight)).rounded())
        }
        return (width, height)
    }

    /// How wide the art will be in this terminal, so the caller can load the
    /// conversion made closest to that width. Any conversion of the clip
    /// works as `probe`, since they share a shape.
    public static func plannedArtWidth(columns: Int, rows: Int, probe: KanaClip) -> Int {
        let clip = prepared(probe)
        let inner = max(40, columns) - 4
        let foot = panels(accent: .white, inner: inner).count + 2
        return artSize(inner: inner, rows: rows, headCount: headCount, footCount: foot,
                       clipWidth: clip.width, clipHeight: clip.height).width
    }

    static func boxed(_ content: String, inner: Int, side: String) -> String {
        side + " " + Ansi.fit(content, inner) + " " + side
    }

    /// Keys, suggestions and features: four short columns when there's
    /// room, fewer when narrow.
    static func panels(accent: RGB, inner: Int) -> [String] {
        let divider = "  "
        let k = keys.items
        let keys1 = Section(title: keys.title, items: Array(k[0 ..< 3]))
        let keys2 = Section(title: "", items: Array(k[3 ..< 6]))
        let keys3 = Section(title: "", items: Array(k[6 ..< 9]))
        if inner >= 100 {
            // five short columns: three of keys, suggestions, features
            let width = (inner - divider.count * 4) / 5
            let last = inner - divider.count * 4 - width * 4
            return zipColumns([lines(keys1, accent, width), lines(keys2, accent, width), lines(keys3, accent, width),
                               lines(suggestions, accent, width), lines(features, accent, last)],
                              widths: [width, width, width, width, last], divider: divider)
        }
        if inner >= 56 {
            let width = (inner - divider.count * 2) / 3
            let last = inner - divider.count * 2 - width * 2
            let top = zipColumns([lines(keys1, accent, width), lines(keys2, accent, width), lines(keys3, accent, last)],
                                 widths: [width, width, last], divider: divider)
            let bottom = zipColumns([lines(suggestions, accent, width), lines(features, accent, width)],
                                    widths: [width, inner - divider.count - width], divider: divider)
            return top + bottom
        }
        return lines(keys, accent, inner) + lines(suggestions, accent, inner) + lines(features, accent, inner)
    }

    static func lines(_ section: Section, _ accent: RGB, _ width: Int) -> [String] {
        var out = [section.title.isEmpty ? "" : Ansi.paint(section.title, accent, bold: true)]
        let keyWidth = section.items.map { Ansi.visibleWidth($0.0) }.max() ?? 0
        for (keys, what) in section.items {
            let bullet = keys == "✦" || keys == "◇"
            let k = bullet ? Ansi.paint(keys, keys == "✦" ? accent : .dim) : Ansi.plain(keys, bold: true)
            out.append(Ansi.fit(" " + Ansi.fit(k, bullet ? 1 : keyWidth) + "  " + Ansi.paint(what, .grey), width))
        }
        return out
    }

    static func zipColumns(_ columns: [[String]], widths: [Int], divider: String) -> [String] {
        let height = columns.map(\.count).max() ?? 0
        return (0 ..< height).map { i in
            zip(columns, widths).map { column, width in
                Ansi.fit(i < column.count ? column[i] : "", width)
            }.joined(separator: divider)
        }
    }

    static func bottomBorder(_ o: Options, width: Int, border: RGB, accent: RGB) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var cwd = o.workingDirectory
        if cwd == home { cwd = "~" } else if cwd.hasPrefix(home + "/") { cwd = "~" + cwd.dropFirst(home.count) }
        let where_ = " " + Ansi.plain(cwd) + (o.skinName.map { Ansi.paint(" · skin " + $0.lowercased(), .grey) } ?? "") + " "
        let hint = " " + Ansi.paint("kana keys", accent) + Ansi.paint(" for this list · ", .grey)
            + Ansi.paint("kana", accent) + Ansi.paint(" replays the intro", .grey) + " "
        let plain = Ansi.paint("╰" + String(repeating: "─", count: width - 2) + "╯", border)
        var fill = width - 4 - Ansi.visibleWidth(where_) - Ansi.visibleWidth(hint)
        if fill >= 2 {
            return Ansi.paint("╰─", border) + where_ + Ansi.paint(String(repeating: "─", count: fill), border) + hint + Ansi.paint("─╯", border)
        }
        fill = width - 4 - Ansi.visibleWidth(where_)
        return fill >= 1 ? Ansi.paint("╰─", border) + where_ + Ansi.paint(String(repeating: "─", count: fill) + "─╯", border) : plain
    }

    static func paintWordmark(accent: RGB) -> [String] {
        let light = accent.mix(.white, 0.35)
        let shade = accent.mix(.black, 0.45)
        return wordmark.map { row in
            let chars = Array(row)
            var out = ""
            for (i, ch) in chars.enumerated() {
                if ch == " " { out += " "; continue }
                // blocks run light to accent, left to right; the outline is a darker shade
                let t = Double(i) / Double(max(1, chars.count - 1))
                out += Ansi.fg(ch == "█" ? light.mix(accent, t) : shade) + String(ch)
            }
            return out + Ansi.reset
        }
    }

    // MARK: rendering

    /// One art row as coloured text, `clip.width` columns wide.
    public func renderRow(frame: Int, row: Int) -> String {
        guard let clip, clip.frames.indices.contains(frame) else { return "" }
        let f = clip.frames[frame]
        var out = ""
        var last: (UInt8, UInt8, UInt8)?
        for (x, ch) in f.rows[row].enumerated() {
            if ch != " ", let c = f.color(x: x, y: row, width: clip.width) {
                if last.map({ $0 != (c.r, c.g, c.b) }) ?? true {
                    out += Ansi.fg(RGB(c.r, c.g, c.b))
                    last = (c.r, c.g, c.b)
                }
            }
            out.append(ch)
        }
        return out + Ansi.reset
    }

    /// The art with `frame` in it, one boxed line per row.
    public func artLines(frame: Int) -> [String] {
        (0 ..< artHeight).map {
            Self.boxed(String(repeating: " ", count: artIndent) + renderRow(frame: frame, row: $0), inner: boxWidth - 4, side: side)
        }
    }

    /// Everything, still: the resting frame in the box.
    public func render() -> String {
        (head + artLines(frame: clip?.portraitIndex ?? 0) + panels + [bottom]).joined(separator: "\n") + "\n"
    }
}
