// Contract C5 (TASKS.md): saved sessions. What was open (windows, tabs, the
// split layout, each pane's folder), so ⌘⇧O can bring an old session back
// and ⌘⇧T a closed tab. Scrollback isn't saved: Ghostty doesn't keep it, so
// a restored pane is a fresh shell in the same folder.
//
// Pure Foundation, unit tested in Tests/KanaCoreTests.

import Foundation

/// One tab's split layout.
public indirect enum SessionLayout: Codable, Equatable, Sendable {
    case pane(directory: String?, title: String)
    /// `horizontal`: first | second side by side; otherwise first above second.
    case split(horizontal: Bool, ratio: Double, first: SessionLayout, second: SessionLayout)

    /// Every pane, in reading order (first before second, depth-first).
    public var panes: [(directory: String?, title: String)] {
        switch self {
        case .pane(let directory, let title): return [(directory, title)]
        case .split(_, _, let first, let second): return first.panes + second.panes
        }
    }

    /// The layout of a live split tree. nil for an empty tree. The zoom
    /// isn't part of the layout (see SessionTab).
    public init?<Leaf>(_ tree: SplitTree<Leaf>, pane: (Leaf) -> (directory: String?, title: String)) {
        guard let root = tree.root else { return nil }
        func layout(_ node: SplitTree<Leaf>.Node) -> SessionLayout {
            switch node {
            case .leaf(let leaf):
                let value = pane(leaf)
                return .pane(directory: value.directory, title: value.title)
            case .split(let split):
                return .split(horizontal: split.axis == .horizontal,
                              ratio: min(0.9, max(0.1, split.ratio)),
                              first: layout(split.first), second: layout(split.second))
            }
        }
        self = layout(root)
    }

    /// A split tree with this layout, making each leaf with `make` in
    /// reading order. Ratios are clamped to 0.1...0.9, like SplitTree's.
    public func tree<Leaf>(_ make: (_ directory: String?, _ title: String) -> Leaf) -> SplitTree<Leaf> {
        func node(_ layout: SessionLayout) -> SplitTree<Leaf>.Node {
            switch layout {
            case .pane(let directory, let title): return .leaf(make(directory, title))
            case .split(let horizontal, let ratio, let first, let second):
                return .split(.init(axis: horizontal ? .horizontal : .vertical,
                                    ratio: min(0.9, max(0.1, ratio)),
                                    first: node(first), second: node(second)))
            }
        }
        return SplitTree(root: node(self), zoomed: nil)
    }
}

public struct SessionTab: Codable, Equatable, Sendable {
    public var layout: SessionLayout
    /// The focused pane, as an index into `layout.panes`.
    public var focused: Int
    /// The zoomed pane's index into `layout.panes`, if any.
    public var zoomed: Int?

    public init(layout: SessionLayout, focused: Int = 0, zoomed: Int? = nil) {
        self.layout = layout
        self.focused = focused
        self.zoomed = zoomed
    }
}

public struct SessionWindow: Codable, Equatable, Sendable {
    /// Screen frame, x y width height, in AppKit's bottom-left coordinates.
    public var frame: [Double]?
    public var tabs: [SessionTab]
    public var selected: Int

    public init(frame: [Double]? = nil, tabs: [SessionTab], selected: Int = 0) {
        self.frame = frame
        self.tabs = tabs
        self.selected = selected
    }
}

public struct Session: Codable, Equatable, Sendable {
    /// Also the file name: one per Kana run, e.g. "2026-09-30T14-02-11".
    public var id: String
    public var saved: Date
    public var windows: [SessionWindow]

    public init(id: String, saved: Date, windows: [SessionWindow]) {
        self.id = id
        self.saved = saved
        self.windows = windows
    }

    /// A filename-safe id for a run that started at `date` (local time,
    /// seconds; no colons).
    public static func id(startedAt date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter.string(from: date)
    }

    public var tabCount: Int {
        windows.reduce(0) { $0 + $1.tabs.count }
    }

    /// Every pane's folder, once each, in order, as short names: the last
    /// path component, "~" for the home folder, "/" for root. Panes with no
    /// folder are skipped.
    public func folderNames(home: String) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        let homePath = (home as NSString).standardizingPath
        for window in windows {
            for tab in window.tabs {
                for pane in tab.layout.panes {
                    guard let directory = pane.directory else { continue }
                    let path = (directory as NSString).standardizingPath
                    guard seen.insert(path).inserted else { continue }
                    let name = path == homePath ? "~"
                        : path == "/" ? "/" : (path as NSString).lastPathComponent
                    names.append(name)
                }
            }
        }
        return names
    }

    /// For the history list. Title like "Today 14:02 · 2 windows · 5 tabs"
    /// ("Yesterday 09:15", "Mon 18:40" within the last week, else
    /// "Sep 12 18:40"; "1 window", "1 tab" singular). Subtitle: up to four
    /// `folderNames`, joined with ", ", with "…" when there are more.
    public func summary(now: Date, calendar: Calendar, home: String) -> (title: String, subtitle: String) {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: saved),
                                           to: calendar.startOfDay(for: now)).day ?? Int.max
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        switch days {
        case 0: formatter.dateFormat = "'Today' HH:mm"
        case 1: formatter.dateFormat = "'Yesterday' HH:mm"
        case 2..<7: formatter.dateFormat = "EEE HH:mm"
        default: formatter.dateFormat = "MMM d HH:mm"
        }
        let title = "\(formatter.string(from: saved)) · \(windows.count) \(windows.count == 1 ? "window" : "windows") · \(tabCount) \(tabCount == 1 ? "tab" : "tabs")"
        let names = folderNames(home: home)
        let subtitle = names.prefix(4).joined(separator: ", ") + (names.count > 4 ? ", …" : "")
        return (title, subtitle)
    }
}

/// Sessions on disk, one JSON file each: `<directory>/<id>.json`.
public struct SessionStore: Sendable {
    public let directory: URL
    /// How many sessions to keep; the oldest go first.
    public let keep: Int

    public init(directory: URL, keep: Int = 30) {
        self.directory = directory
        self.keep = keep
    }

    /// Writes the session atomically, creating the directory. A session with
    /// no tabs isn't worth keeping: its file is removed instead. Then prunes
    /// to `keep`, newest by `saved`.
    public func save(_ session: Session) throws {
        let manager = FileManager.default
        let url = directory.appendingPathComponent(session.id + ".json")
        if session.tabCount == 0 {
            if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
        } else {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(session).write(to: url, options: .atomic)
        }
        for entry in entries().dropFirst(max(0, keep)) {
            try manager.removeItem(at: entry.url)
        }
    }

    /// Newest first by `saved`. Files that don't decode are skipped.
    public func list() -> [Session] {
        entries().map(\.session)
    }

    public func delete(id: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(id + ".json"))
    }
}

private extension SessionStore {
    func entries() -> [(url: URL, session: Session)] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return urls.compactMap { url -> (url: URL, session: Session)? in
            guard url.lastPathComponent.hasSuffix(".json"),
                  let data = try? Data(contentsOf: url),
                  let session = try? decoder.decode(Session.self, from: data) else { return nil }
            return (url, session)
        }.sorted {
            if $0.session.saved != $1.session.saved { return $0.session.saved > $1.session.saved }
            return $0.url.lastPathComponent < $1.url.lastPathComponent
        }
    }
}
