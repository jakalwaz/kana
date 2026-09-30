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
    public var panes: [(directory: String?, title: String)] { fatalError("T1.10") }

    /// The layout of a live split tree. nil for an empty tree. The zoom
    /// isn't part of the layout (see SessionTab).
    public init?<Leaf>(_ tree: SplitTree<Leaf>, pane: (Leaf) -> (directory: String?, title: String)) { fatalError("T1.10") }

    /// A split tree with this layout, making each leaf with `make` in
    /// reading order. Ratios are clamped to 0.1...0.9, like SplitTree's.
    public func tree<Leaf>(_ make: (_ directory: String?, _ title: String) -> Leaf) -> SplitTree<Leaf> { fatalError("T1.10") }
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
    public static func id(startedAt date: Date) -> String { fatalError("T1.10") }

    public var tabCount: Int { fatalError("T1.10") }

    /// Every pane's folder, once each, in order, as short names: the last
    /// path component, "~" for the home folder, "/" for root. Panes with no
    /// folder are skipped.
    public func folderNames(home: String) -> [String] { fatalError("T1.10") }

    /// For the history list. Title like "Today 14:02 · 2 windows · 5 tabs"
    /// ("Yesterday 09:15", "Mon 18:40" within the last week, else
    /// "Sep 12 18:40"; "1 window", "1 tab" singular). Subtitle: up to four
    /// `folderNames`, joined with ", ", with "…" when there are more.
    public func summary(now: Date, calendar: Calendar, home: String) -> (title: String, subtitle: String) { fatalError("T1.10") }
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
    public func save(_ session: Session) throws { fatalError("T1.10") }

    /// Newest first by `saved`. Files that don't decode are skipped.
    public func list() -> [Session] { fatalError("T1.10") }

    public func delete(id: String) { fatalError("T1.10") }
}
