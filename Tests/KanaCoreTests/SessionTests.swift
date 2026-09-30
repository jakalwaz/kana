import Foundation
import KanaCore
import Testing

private final class Leaf {
    let directory: String?
    let title: String

    init(_ directory: String?, _ title: String) {
        self.directory = directory
        self.title = title
    }
}

private func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}

private func session(_ id: String = "run", saved: String = "2026-09-30T18:02:11Z",
                     folders: [String?] = ["/Users/jak"]) -> Session {
    Session(id: id, saved: date(saved), windows: [SessionWindow(tabs: folders.map {
        SessionTab(layout: .pane(directory: $0, title: "shell"))
    })])
}

private func withStore(keep: Int = 30, _ body: (SessionStore) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(SessionStore(directory: root.appendingPathComponent("sessions"), keep: keep))
}

@Suite struct SessionTests {
    @Test func emptyTreeHasNoLayout() {
        var calls = 0
        let layout = SessionLayout(SplitTree<Leaf>()) { leaf in
            calls += 1
            return (leaf.directory, leaf.title)
        }
        #expect(layout == nil)
        #expect(calls == 0)
    }

    @Test func singlePaneRoundTrip() throws {
        let layout = SessionLayout.pane(directory: nil, title: "untitled")
        let tree = layout.tree(Leaf.init)
        #expect(tree.leaves.count == 1)
        #expect(tree.leaves.first?.directory == nil)
        #expect(tree.leaves.first?.title == "untitled")
        #expect(SessionLayout(tree) { ($0.directory, $0.title) } == layout)
    }

    @Test func nestedLayoutRoundTripAndReadingOrder() throws {
        let a = Leaf("/a", "A"), b = Leaf(nil, "B"), c = Leaf("/c", "C"), d = Leaf("/d", "D")
        typealias Tree = SplitTree<Leaf>
        let root = Tree.Node.split(.init(axis: .horizontal, ratio: 0.3,
            first: .split(.init(axis: .vertical, ratio: 0.7, first: .leaf(a), second: .leaf(b))),
            second: .split(.init(axis: .horizontal, ratio: 0.4, first: .leaf(c), second: .leaf(d)))))
        let tree = Tree(root: root, zoomed: b)
        var captured: [String] = []
        let layout = try #require(SessionLayout(tree) {
            captured.append($0.title)
            return ($0.directory, $0.title)
        })
        let expected = SessionLayout.split(horizontal: true, ratio: 0.3,
            first: .split(horizontal: false, ratio: 0.7,
                          first: .pane(directory: "/a", title: "A"), second: .pane(directory: nil, title: "B")),
            second: .split(horizontal: true, ratio: 0.4,
                           first: .pane(directory: "/c", title: "C"), second: .pane(directory: "/d", title: "D")))
        #expect(layout == expected)
        #expect(captured == ["A", "B", "C", "D"])
        #expect(layout.panes.map(\.title) == captured)
        #expect(layout.panes.map(\.directory) == ["/a", nil, "/c", "/d"])
        var made: [String] = []
        let restored = layout.tree { directory, title in
            made.append(title)
            return Leaf(directory, title)
        }
        #expect(made == captured)
        #expect(restored.leaves.map(\.title) == captured)
        #expect(restored.zoomed == nil)
        #expect(SessionLayout(restored) { ($0.directory, $0.title) } == expected)
    }

    @Test func ratiosClampInBothDirections() throws {
        let pane = SessionLayout.pane(directory: nil, title: "shell")
        let layout = SessionLayout.split(horizontal: true, ratio: -2, first: pane,
            second: .split(horizontal: false, ratio: 4, first: pane, second: pane))
        let tree = layout.tree(Leaf.init)
        guard case .split(let root) = tree.root,
              case .split(let nested) = root.second else {
            Issue.record("Expected nested splits")
            return
        }
        #expect(root.ratio == 0.1)
        #expect(nested.ratio == 0.9)
        #expect(root.axis == .horizontal)
        #expect(nested.axis == .vertical)
        let raw = SplitTree<Leaf>(root: .split(.init(axis: .vertical, ratio: 9,
            first: .leaf(Leaf(nil, "shell")), second: .leaf(Leaf(nil, "shell")))), zoomed: nil)
        #expect(SessionLayout(raw) { ($0.directory, $0.title) }
                == .split(horizontal: false, ratio: 0.9, first: pane, second: pane))
    }

    @Test func runIDUsesLocalTimeAndSeconds() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let started = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30,
                                                         hour: 14, minute: 2, second: 11))!
        #expect(Session.id(startedAt: started) == "2026-09-30T14-02-11")
    }

    @Test func foldersAndTabCountAcrossWindowsAndSplits() {
        var value = session(folders: ["/Users/jak/", "/", nil, "/work/kana", "/work/kana/"])
        value.windows.append(SessionWindow(tabs: [SessionTab(layout: .split(horizontal: true, ratio: 0.5,
            first: .pane(directory: "/work/ghostty", title: "one"),
            second: .pane(directory: "/work/kana", title: "two")))]))
        #expect(value.tabCount == 6)
        #expect(value.folderNames(home: "/Users/jak") == ["~", "/", "kana", "ghostty"])
        #expect(session(folders: [nil]).folderNames(home: "/Users/jak").isEmpty)
    }

    @Test func summaryTitleForms() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        calendar.locale = Locale(identifier: "fr_FR")
        let now = date("2026-09-30T23:00:00Z")
        let examples = [
            ("2026-09-30T18:02:11Z", "Today 14:02"),
            ("2026-09-29T13:15:00Z", "Yesterday 09:15"),
            ("2026-09-28T22:40:00Z", "Mon 18:40"),
            ("2026-09-24T22:40:00Z", "Thu 18:40"),
            ("2026-09-23T22:40:00Z", "Sep 23 18:40"),
            ("2026-09-12T22:40:00Z", "Sep 12 18:40"),
            ("2025-12-12T23:40:00Z", "Dec 12 18:40"),
            ("2026-10-01T22:40:00Z", "Oct 1 18:40"),
        ]
        for (saved, prefix) in examples {
            #expect(session(saved: saved).summary(now: now, calendar: calendar, home: "/Users/jak").title
                    == "\(prefix) · 1 window · 1 tab")
        }
        var plural = session(folders: ["/a", "/b", "/c"])
        plural.windows.append(SessionWindow(tabs: [SessionTab(layout: .pane(directory: nil, title: "")),
                                                  SessionTab(layout: .pane(directory: nil, title: ""))]))
        #expect(plural.summary(now: now, calendar: calendar, home: "/Users/jak").title
                == "Today 14:02 · 2 windows · 5 tabs")
    }

    @Test func distinctFoldersWithSameShortNameArePreserved() {
        let value = session(folders: ["/work/foo", "/other/foo", "/work/foo/", "/a", "/b", "/c"])
        #expect(value.folderNames(home: "/Users/jak") == ["foo", "foo", "a", "b", "c"])
        #expect(value.summary(now: value.saved, calendar: Calendar(identifier: .gregorian),
                              home: "/Users/jak").subtitle == "foo, foo, a, b, …")
    }

    @Test func summaryUsesCalendarDaysAcrossMidnightAndDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        // 23:30 local yesterday, only an hour before now.
        let midnight = session(saved: "2026-09-30T03:30:00Z")
        #expect(midnight.summary(now: date("2026-09-30T04:30:00Z"), calendar: calendar, home: "/").title
                == "Yesterday 23:30 · 1 window · 1 tab")
        // More than 24 hours ago, but still yesterday across the fall DST change.
        let dst = session(saved: "2026-11-01T04:15:00Z")
        #expect(dst.summary(now: date("2026-11-02T05:30:00Z"), calendar: calendar, home: "/").title
                == "Yesterday 00:15 · 1 window · 1 tab")
    }

    @Test func summarySubtitleLimitsFolders() {
        let now = date("2026-09-30T18:02:11Z")
        let calendar = Calendar(identifier: .gregorian)
        for (folders, expected): ([String?], String) in [
            ([nil], ""),
            (["/Users/jak"], "~"),
            (["/a", "/b", "/c", "/d", "/a", nil], "a, b, c, d"),
            (["/a", "/b", "/c", "/d", "/e"], "a, b, c, d, …"),
        ] {
            #expect(session(folders: folders).summary(now: now, calendar: calendar, home: "/Users/jak").subtitle
                    == expected)
        }
        let empty = Session(id: "empty", saved: now, windows: [])
        #expect(empty.tabCount == 0)
        #expect(empty.summary(now: now, calendar: calendar, home: "/").title
            .hasSuffix(" · 0 windows · 0 tabs"))
    }

    @Test func storeCreatesDirectoryAndRoundTripsAllFields() throws {
        try withStore { store in
            #expect(store.keep == 30)
            #expect(store.list().isEmpty)
            let layout = SessionLayout.split(horizontal: false, ratio: 0.25,
                first: .pane(directory: "/Users/jak/日本語", title: "日本語"),
                second: .pane(directory: nil, title: "shell"))
            let value = Session(id: "2026-09-30T14-02-11", saved: date("2026-09-30T18:02:11Z"), windows: [
                SessionWindow(frame: [-100, 20, 800, 600], tabs: [
                    SessionTab(layout: layout, focused: 1, zoomed: 0),
                    SessionTab(layout: .pane(directory: "/", title: "root"))], selected: 1),
                SessionWindow(tabs: [])])
            try store.save(value)
            #expect(store.list() == [value])
            let url = store.directory.appendingPathComponent(value.id + ".json")
            let data = try Data(contentsOf: url)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["saved"] as? String == "2026-09-30T18:02:11Z")
            #expect(data == (try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])))
            #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
                    == [value.id + ".json"])
        }
    }

    @Test func storeOrdersBySavedAndOverwritesSameID() throws {
        try withStore { store in
            let older = session("z", saved: "2026-09-01T00:00:00Z")
            let newer = session("a", saved: "2026-09-03T00:00:00Z")
            try store.save(newer)
            try store.save(older)
            #expect(store.list() == [newer, older])
            var updated = older
            updated.saved = date("2026-09-04T00:00:00Z")
            updated.windows[0].tabs[0].focused = 2
            try store.save(updated)
            #expect(store.list() == [updated, newer])
        }
    }

    @Test func storePrunesOldestSavedEvenWhenWrittenLast() throws {
        try withStore(keep: 2) { store in
            let oldest = session("z", saved: "2026-09-01T00:00:00Z")
            let middle = session("m", saved: "2026-09-02T00:00:00Z")
            let newest = session("a", saved: "2026-09-03T00:00:00Z")
            try store.save(middle)
            try store.save(newest)
            try store.save(oldest)
            #expect(store.list() == [newest, middle])
            #expect(!FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("z.json").path))
        }
    }

    @Test func emptySessionRemovesItsFileAndStillPrunes() throws {
        try withStore { store in
            try store.save(session("a"))
            try store.save(session("b"))
            try store.save(session("c"))
            try store.save(session("a", folders: []))
            #expect(Set(store.list().map(\.id)) == ["b", "c"])
            #expect(!FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("a.json").path))
            try SessionStore(directory: store.directory, keep: 1).save(session("missing", folders: []))
            #expect(store.list().count == 1)
            let last = try #require(store.list().first)
            try store.save(Session(id: last.id, saved: last.saved, windows: []))
            #expect(store.list().isEmpty)
        }
    }

    @Test func zeroRetentionRemovesSavedSession() throws {
        try withStore(keep: 0) { store in
            try store.save(session())
            #expect(store.list().isEmpty)
            #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).isEmpty)
        }
    }

    @Test func storeSkipsGarbageAndNonJSONFiles() throws {
        try withStore(keep: 1) { store in
            let value = session()
            try store.save(value)
            let good = try Data(contentsOf: store.directory.appendingPathComponent("run.json"))
            for name in ["backup.txt", "run.json.bak", "UPPER.JSON"] {
                try good.write(to: store.directory.appendingPathComponent(name))
            }
            for (name, text) in [("broken.json", "garbage"), ("wrong.json", "{}"),
                                 ("bad-date.json", "{\"id\":\"bad\",\"saved\":0,\"windows\":[]}")] {
                try Data(text.utf8).write(to: store.directory.appendingPathComponent(name))
            }
            try FileManager.default.createDirectory(at: store.directory.appendingPathComponent("folder.json"),
                                                    withIntermediateDirectories: false)
            #expect(store.list() == [value])
            let newer = session("new", saved: "2026-10-01T00:00:00Z")
            try store.save(newer)
            #expect(store.list() == [newer])
            #expect(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("broken.json").path))
        }
    }

    @Test func deleteIsIdempotentAndOnlyRemovesRequestedSession() throws {
        try withStore { store in
            store.delete(id: "missing")
            try store.save(session("a"))
            try store.save(session("b"))
            store.delete(id: "a")
            store.delete(id: "a")
            #expect(store.list().map(\.id) == ["b"])
            store.delete(id: "b")
            #expect(store.list().isEmpty)
        }
    }

    @Test func savePropagatesFileErrors() throws {
        try withStore { store in
            try FileManager.default.createDirectory(at: store.directory.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data("file blocks directory".utf8).write(to: store.directory)
            #expect(throws: (any Error).self) { try store.save(session()) }
        }
    }
}
