import AppKit

/// One Kana window: the header with tabs, and one TerminalPane per tab.
/// Based on Ghostty's macos/Sources/Features/Terminal/TerminalController.swift
/// for the window setup (transparent title bar, full-size content), and
/// BaseTerminalController.swift for close confirmation and occlusion.
@MainActor
final class KanaWindowController: NSWindowController, NSWindowDelegate {
    private let settings: KanaSettings
    private let skin: SkinInfo?
    private let header = HeaderBar()
    private let content = NSView()
    private var panes: [TerminalPane] = []
    private var selected = 0
    /// What the next tab's welcome screen does. With `intro = first-window`
    /// only the very first tab animates; with `on`, every tab does.
    private var nextBanner: TerminalSession.Banner

    private(set) var focusMode = false
    /// The open "close this tab?" sheet, so it goes away if its tab closes
    /// on its own first.
    private var closeSheet: (pane: TerminalPane, alert: NSAlert)?

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
        for pane in panes { pane.frame = content.bounds }
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
        let pane = TerminalPane(settings: settings, skin: skin, banner: nextBanner, workingDirectory: cwd)
        if nextBanner == .animate, settings.intro != .on { nextBanner = .still }
        pane.session.onTitleChange = { [weak self, weak pane] title in
            guard let self, let pane else { return }
            pane.title = title
            refreshHeader()
        }
        pane.session.onWorkingDirectoryChange = { [weak pane] path in
            pane?.workingDirectory = path
        }
        pane.session.onClose = { [weak self, weak pane] processAlive in
            guard let self, let pane else { return }
            if processAlive {
                confirmClose(pane)
            } else {
                remove(pane)
            }
        }
        panes.append(pane)
        content.addSubview(pane)
        pane.frame = content.bounds
        select(panes.count - 1)
    }

    func select(_ index: Int) {
        guard panes.indices.contains(index) else { return }
        selected = index
        for (i, pane) in panes.enumerated() {
            pane.isHidden = i != index
        }
        syncVisibility()
        panes[index].session.focus()
        refreshHeader()
    }

    /// Only the selected tab of an unoccluded window renders. Before the
    /// window is first shown it counts as visible.
    private func syncVisibility() {
        let occluded = window.map { $0.isMiniaturized || ($0.isVisible && !$0.occlusionState.contains(.visible)) } ?? false
        for (i, pane) in panes.enumerated() {
            pane.session.setVisible(i == selected && !occluded)
        }
    }

    func windowDidChangeOcclusionState(_: Notification) { syncVisibility() }

    /// ⌘W and the tab's ×: Ghostty decides whether to confirm, then calls
    /// back through the session's onClose.
    func closeTab(at index: Int) {
        guard panes.indices.contains(index) else { return }
        panes[index].session.requestClose()
    }

    private func confirmClose(_ pane: TerminalPane) {
        guard let window, window.attachedSheet == nil, panes.contains(pane) else { return }
        let alert = NSAlert()
        alert.messageText = "Close “\(pane.title)”?"
        alert.informativeText = "Something is still running in it. Closing the tab will stop it."
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        closeSheet = (pane, alert)
        alert.beginSheetModal(for: window) { [weak self, weak pane] response in
            guard let self else { return }
            closeSheet = nil
            guard response == .alertFirstButtonReturn, let pane else { return }
            remove(pane)
        }
    }

    /// Drops the pane. Closing a background tab keeps the current one selected.
    private func remove(_ pane: TerminalPane) {
        guard let index = panes.firstIndex(of: pane) else { return }
        if let sheet = closeSheet, sheet.pane === pane, let window {
            window.endSheet(sheet.alert.window, returnCode: .abort)
        }
        let current = currentPane
        panes.remove(at: index)
        pane.removeFromSuperview()
        if panes.isEmpty {
            window?.close()
            return
        }
        if let current, current !== pane, let i = panes.firstIndex(of: current) {
            selected = i
            refreshHeader()
        } else {
            select(min(index, panes.count - 1))
        }
    }

    func closeCurrentTab() { closeTab(at: selected) }
    func selectNext() { select((selected + 1) % max(panes.count, 1)) }
    func selectPrevious() { select((selected - 1 + panes.count) % max(panes.count, 1)) }

    private var currentPane: TerminalPane? {
        panes.indices.contains(selected) ? panes[selected] : nil
    }

    private func refreshHeader() {
        header.titles = panes.map(\.title)
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
