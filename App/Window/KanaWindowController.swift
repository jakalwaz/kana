import AppKit
import KanaCore

/// One tab: a split tree of panes, the one with focus, and the view that
/// lays them out.
@MainActor
final class Tab {
    var tree: SplitTree<TerminalPane>
    var focused: TerminalPane
    let container = SplitContainerView()

    init(pane: TerminalPane) {
        tree = SplitTree(leaf: pane)
        focused = pane
    }

    var panes: [TerminalPane] { tree.leaves }
}

/// One Kana window: the header with tabs, and a split tree per tab.
/// Based on Ghostty's macos/Sources/Features/Terminal/TerminalController.swift
/// for the window setup (transparent title bar, full-size content), and
/// BaseTerminalController.swift for splits, close confirmation and occlusion.
@MainActor
final class KanaWindowController: NSWindowController, NSWindowDelegate {
    private let settings: KanaSettings
    private let skin: SkinInfo?
    private let header = HeaderBar()
    private let content = NSView()
    private var tabs: [Tab] = []
    private var selected = 0
    /// What the next tab's welcome screen does. With `intro = first-window`
    /// only the very first tab animates; with `on`, every tab does.
    private var nextBanner: TerminalSession.Banner

    private(set) var focusMode = false
    /// The open "close this?" sheet and the busy panes it's about, so it
    /// goes away if they all exit on their own first.
    private var closeSheet: (panes: [TerminalPane], alert: NSAlert)?
    /// While a whole tab is closing: its busy panes, to ask about once.
    private var tabClose: (tab: Tab, busy: [TerminalPane])?

    var onClose: ((KanaWindowController) -> Void)?

    init(settings: KanaSettings, skin: SkinInfo?, playIntro: Bool, workingDirectory: String? = nil) {
        self.settings = settings
        self.skin = skin
        nextBanner = !settings.banner ? .off : playIntro ? .animate : .still

        // roomy by default, so the welcome screen's art has space: 80% of the
        // screen, capped
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let size = NSSize(width: min(1180, (screen.width * 0.8).rounded()), height: min(820, (screen.height * 0.8).rounded()))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.isOpaque = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 480, height: 300)
        window.title = "Kana"
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        super.init(window: window)
        window.delegate = self

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = root
        root.addSubview(content)
        root.addSubview(header)

        header.accent = NSColor(hex: skin?.accentHex ?? settings.accentHex) ?? .systemRed
        header.onSelect = { [weak self] in self?.select($0) }
        header.onClose = { [weak self] in self?.closeTab(at: $0) }
        header.onNewTab = { [weak self] in self?.newTab() }

        newTab(workingDirectory: workingDirectory)
        window.center()
        layoutWindow()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    // MARK: layout

    private func layoutWindow() {
        guard let root = window?.contentView else { return }
        let headerHeight = focusMode ? 0 : HeaderBar.height
        header.isHidden = focusMode
        header.frame = NSRect(x: 0, y: root.bounds.height - headerHeight, width: root.bounds.width, height: headerHeight)
        content.frame = NSRect(x: 0, y: 0, width: root.bounds.width, height: root.bounds.height - headerHeight)
        for tab in tabs { tab.container.frame = content.bounds }
        placeTrafficLights()
    }

    /// Centre the traffic lights in the taller header. AppKit puts them back
    /// on some resizes, so this runs from every layout pass.
    private func placeTrafficLights() {
        guard let window else { return }
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (i, type) in buttons.enumerated() {
            guard let button = window.standardWindowButton(type), let bar = button.superview else { continue }
            button.isHidden = focusMode
            guard !window.styleMask.contains(.fullScreen) else { continue }
            let y = bar.bounds.height - HeaderBar.height / 2 - button.frame.height / 2
            button.setFrameOrigin(NSPoint(x: 16 + CGFloat(i) * 20, y: y))
        }
    }

    func windowDidResize(_: Notification) { layoutWindow() }
    func windowDidEnterFullScreen(_: Notification) { layoutWindow() }
    func windowDidExitFullScreen(_: Notification) { layoutWindow() }

    // MARK: tabs

    func newTab(workingDirectory: String? = nil) {
        let cwd = workingDirectory ?? currentPane?.workingDirectory
        let pane = makePane(banner: nextBanner, workingDirectory: cwd)
        if nextBanner == .animate, settings.intro != .on { nextBanner = .still }
        let tab = Tab(pane: pane)
        tab.container.onResize = { [weak self, weak tab] path, ratio in
            guard let self, let tab else { return }
            tab.tree = tab.tree.resizing(path, ratio: ratio)
            apply(tab)
        }
        tab.container.onEqualize = { [weak self, weak tab] in
            guard let self, let tab else { return }
            tab.tree = tab.tree.equalized()
            apply(tab)
        }
        tabs.append(tab)
        content.addSubview(tab.container)
        tab.container.frame = content.bounds
        apply(tab)
        select(tabs.count - 1)
    }

    private func makePane(banner: TerminalSession.Banner, workingDirectory: String?) -> TerminalPane {
        let pane = TerminalPane(settings: settings, skin: skin, banner: banner, workingDirectory: workingDirectory)
        pane.session.onTitleChange = { [weak self, weak pane] title in
            guard let self, let pane else { return }
            pane.title = title
            refreshHeader()
        }
        pane.session.onWorkingDirectoryChange = { [weak pane] path in
            pane?.workingDirectory = path
        }
        // a click into a split focuses it
        pane.session.onFocusChange = { [weak self, weak pane] focused in
            guard focused, let self, let pane, let tab = tab(containing: pane), tab.focused !== pane else { return }
            tab.focused = pane
            apply(tab)
            refreshHeader()
        }
        pane.session.onClose = { [weak self, weak pane] processAlive in
            guard let self, let pane else { return }
            if processAlive {
                if let closing = tabClose, closing.tab.tree.contains(pane) {
                    tabClose?.busy.append(pane)
                } else {
                    confirmClose([pane])
                }
            } else {
                remove(pane)
            }
        }
        return pane
    }

    private func tab(containing pane: TerminalPane) -> Tab? {
        tabs.first { $0.tree.contains(pane) }
    }

    /// Pushes a tab's tree into its view: layout, dimming, what renders.
    private func apply(_ tab: Tab) {
        tab.container.show(tab.tree, focused: tab.focused)
        syncVisibility()
    }

    func select(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        selected = index
        for (i, tab) in tabs.enumerated() {
            tab.container.isHidden = i != index
        }
        syncVisibility()
        tabs[index].focused.session.focus()
        refreshHeader()
    }

    /// Only the shown splits of the selected tab in an unoccluded window
    /// render. Before the window is first shown it counts as visible.
    private func syncVisibility() {
        let occluded = window.map { $0.isMiniaturized || ($0.isVisible && !$0.occlusionState.contains(.visible)) } ?? false
        for (i, tab) in tabs.enumerated() {
            let zoomed = tab.tree.zoomed
            for pane in tab.panes {
                pane.session.setVisible(i == selected && !occluded && (zoomed == nil || zoomed === pane))
            }
        }
    }

    func windowDidChangeOcclusionState(_: Notification) { syncVisibility() }

    // MARK: splits

    /// ⌘D and ⌘⇧D: the new split starts in the focused one's folder.
    func split(_ side: SplitSide) {
        guard let tab = currentTab else { return }
        let pane = makePane(banner: .off, workingDirectory: tab.focused.workingDirectory)
        tab.tree = tab.tree.inserting(pane, at: tab.focused, side: side)
        tab.focused = pane
        apply(tab)
        pane.session.focus()
        refreshHeader()
    }

    /// ⌘[ ⌘] and ⌘⌥arrows. Moving off a zoomed split unzooms first.
    func moveFocus(_ direction: SplitFocus) {
        guard let tab = currentTab else { return }
        var tree = tab.tree
        if let zoomed = tree.zoomed { tree = tree.toggledZoom(zoomed) }
        guard let target = tree.focusTarget(from: tab.focused, direction, in: tab.container.bounds),
              target !== tab.focused
        else { return }
        tab.tree = tree
        tab.focused = target
        apply(tab)
        target.session.focus()
        refreshHeader()
    }

    func toggleZoom() {
        guard let tab = currentTab else { return }
        tab.tree = tab.tree.toggledZoom(tab.focused)
        apply(tab)
        tab.focused.session.focus()
    }

    func equalizeSplits() {
        guard let tab = currentTab else { return }
        tab.tree = tab.tree.equalized()
        apply(tab)
    }

    // MARK: closing

    /// ⌘W: the focused split. Ghostty decides whether to confirm, then calls
    /// back through the session's onClose.
    func closeFocused() {
        currentPane?.session.requestClose()
    }

    /// The tab's × and ⌥⌘W: every split in it. Ghostty answers each close
    /// request straight away; idle splits close, and the busy ones are
    /// asked about together in one sheet.
    func closeTab(at index: Int) {
        guard tabs.indices.contains(index), tabClose == nil else { return }
        let tab = tabs[index]
        tabClose = (tab, [])
        for pane in tab.panes {
            pane.session.requestClose()
        }
        let busy = tabClose?.busy.filter { tab.tree.contains($0) } ?? []
        tabClose = nil
        if !busy.isEmpty { confirmClose(busy) }
    }

    func closeCurrentTab() { closeTab(at: selected) }

    private func confirmClose(_ panes: [TerminalPane]) {
        // a late busy answer while the sheet is up joins it rather than
        // being dropped
        if let sheet = closeSheet {
            closeSheet?.panes = sheet.panes + panes.filter { new in !sheet.panes.contains { $0 === new } }
            return
        }
        guard let window, window.attachedSheet == nil, let first = panes.first else { return }
        let alert = NSAlert()
        if panes.count == 1 {
            alert.messageText = "Close “\(first.title)”?"
            alert.informativeText = "Something is still running in it. Closing it will stop it."
        } else {
            alert.messageText = "Close this tab?"
            alert.informativeText = "\(panes.count) splits are still running something. Closing the tab will stop them."
        }
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        closeSheet = (panes, alert)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            let panes = closeSheet?.panes ?? []
            closeSheet = nil
            guard response == .alertFirstButtonReturn else { return }
            panes.forEach(remove)
        }
    }

    /// Drops a split. Its neighbour takes focus; the last split closes the tab.
    private func remove(_ pane: TerminalPane) {
        guard let tab = tab(containing: pane) else { return }
        if let sheet = closeSheet, sheet.panes.contains(where: { $0 === pane }) {
            let rest = sheet.panes.filter { $0 !== pane }
            closeSheet?.panes = rest
            if rest.isEmpty, let window { window.endSheet(sheet.alert.window, returnCode: .abort) }
        }
        let next = tab.focused === pane
            ? tab.tree.focusTarget(from: pane, .previous, in: tab.container.bounds)
            : tab.focused
        tab.tree = tab.tree.removing(pane)
        pane.removeFromSuperview()
        guard let first = tab.tree.leaves.first else {
            removeTab(tab)
            return
        }
        tab.focused = next.flatMap { $0 === pane ? nil : $0 } ?? first
        apply(tab)
        if tab === currentTab { tab.focused.session.focus() }
        refreshHeader()
    }

    /// Closing a background tab keeps the current one selected.
    private func removeTab(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        let current = currentTab
        tabs.remove(at: index)
        tab.container.removeFromSuperview()
        if tabs.isEmpty {
            window?.close()
            return
        }
        if let current, current !== tab, let i = tabs.firstIndex(where: { $0 === current }) {
            selected = i
            refreshHeader()
        } else {
            select(min(index, tabs.count - 1))
        }
    }

    func selectNext() { select((selected + 1) % max(tabs.count, 1)) }
    func selectPrevious() { select((selected - 1 + tabs.count) % max(tabs.count, 1)) }

    private var currentTab: Tab? {
        tabs.indices.contains(selected) ? tabs[selected] : nil
    }

    private var currentPane: TerminalPane? { currentTab?.focused }

    private func refreshHeader() {
        header.titles = tabs.map(\.focused.title)
        header.selectedIndex = selected
        window?.title = currentPane?.title ?? "Kana"
    }

    // MARK: modes

    func toggleFocusMode() {
        focusMode.toggle()
        layoutWindow()
    }

    func windowWillClose(_: Notification) {
        onClose?(self)
    }

    func windowDidBecomeKey(_: Notification) {
        currentPane?.session.focus()
    }
}
