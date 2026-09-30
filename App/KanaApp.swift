import AppKit
import KanaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings = KanaSettings.load()
    private var windows: [KanaWindowController] = []
    private var introPlayed = false
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.mainMenu = makeMenu()
        quitCleanlyOnSIGTERM()
        Notifier.shared.start()
        Notifier.shared.onOpen = { [weak self] paneID in
            guard let self, windows.contains(where: { $0.reveal(paneID: paneID) }) else { return }
            NSApp.activate(ignoringOtherApps: true)
        }
        newWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        reportConfigIssues()
        // a light:X,dark:Y theme swaps with the system appearance
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.windows.forEach { $0.applyTheme() } }
        }
        scheduleDebugSnapshots()
    }

    /// KANA_DEBUG_SNAPSHOT=/some/prefix saves PNGs of the first window during
    /// and after the intro, for checking the look without screen recording.
    private func scheduleDebugSnapshots() {
        guard let prefix = ProcessInfo.processInfo.environment["KANA_DEBUG_SNAPSHOT"] else { return }
        // KANA_DEBUG_PALETTE=1 opens the palette first, to check its look
        if ProcessInfo.processInfo.environment["KANA_DEBUG_PALETTE"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showCommandPalette(nil) }
        }
        for delay in [0.9, 1.6, 4.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let view = self?.windows.first?.window?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                let url = URL(fileURLWithPath: "\(prefix)-\(delay).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }

    func applicationDidBecomeActive(_: Notification) {
        windows.forEach { $0.clearSeen() }
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool { true }

    /// `pkill Kana` (script/run does it) quits like ⌘Q, not like a crash.
    private var termSource: DispatchSourceSignal?
    private func quitCleanlyOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termSource = source
    }

    private var skin: SkinInfo? { SkinManager.find(settings: settings) }

    private var active: KanaWindowController? {
        windows.first { $0.window?.isKeyWindow == true } ?? windows.last
    }

    // MARK: actions

    @objc func newWindow(_: Any?) {
        let playIntro: Bool
        switch settings.intro {
        case .on: playIntro = true
        case .off: playIntro = false
        case .firstWindow: playIntro = !introPlayed
        }
        introPlayed = true
        let controller = KanaWindowController(settings: settings, skin: skin, playIntro: playIntro)
        controller.onClose = { [weak self] closed in
            self?.windows.removeAll { $0 === closed }
            self?.updateDockBadge()
        }
        controller.onAttentionChange = { [weak self] in self?.updateDockBadge() }
        if let previous = active?.window {
            controller.window?.setFrameTopLeftPoint(NSPoint(x: previous.frame.minX + 28, y: previous.frame.maxY - 28))
        }
        windows.append(controller)
        controller.showWindow(nil)
    }

    @objc func newTab(_: Any?) {
        guard let active else { return newWindow(nil) }
        active.newTab()
    }

    @objc func close(_: Any?) { active?.closeFocused() }
    @objc func closeTab(_: Any?) { active?.closeCurrentTab() }
    @objc func splitRight(_: Any?) { active?.split(.right) }
    @objc func splitDown(_: Any?) { active?.split(.down) }
    @objc func focusSplit(_ sender: NSMenuItem) {
        let directions: [SplitFocus] = [.previous, .next, .up, .down, .left, .right]
        if directions.indices.contains(sender.tag) { active?.moveFocus(directions[sender.tag]) }
    }
    /// ⇧⌘↩ zooms. AppKit ignores Shift when matching Return, so this item
    /// also catches ⌘↩, which is Ghostty's full screen.
    @objc func toggleSplitZoom(_: Any?) {
        if let event = NSApp.currentEvent, event.type == .keyDown, event.keyCode == 36,
           event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift)
        {
            active?.window?.toggleFullScreen(nil)
        } else {
            active?.toggleZoom()
        }
    }
    @objc func equalizeSplits(_: Any?) { active?.equalizeSplits() }
    @objc func nextTab(_: Any?) { active?.selectNext() }
    @objc func previousTab(_: Any?) { active?.selectPrevious() }
    @objc func selectTab(_ sender: NSMenuItem) { active?.select(sender.tag) }
    @objc func toggleFocusMode(_: Any?) { active?.toggleFocusMode() }

    /// ⌘⇧K (and ⌘⇧P, Ghostty's): every menu action, plus themes to try.
    @objc func showCommandPalette(_: Any?) {
        guard let active, let menu = NSApp.mainMenu else { return }
        active.togglePalette(PaletteCommand.fromMenu(menu) + themeCommands())
    }

    /// Switches the theme for this session only; `theme = <name>` in the
    /// config keeps it.
    private func themeCommands() -> [PaletteCommand] {
        ThemeLibrary.names.map { name in
            PaletteCommand(id: "theme:\(name)", title: "Theme: \(name)", subtitle: "this session") { [weak self] in
                guard let self else { return }
                settings.config.theme = name
                TerminalBridge.reload(settings: settings)
                for window in windows {
                    window.settings = settings
                    window.applyTheme()
                }
            }
        }
    }

    /// How many panes want you, on the dock icon.
    private func updateDockBadge() {
        let count = windows.reduce(0) { $0 + $1.attentionCount }
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    /// ⌘⇧,: re-reads the config. Ghostty settings (fonts, theme, keybinds)
    /// change in every open terminal; Kana's own (banner, suggestions) apply
    /// to new tabs.
    @objc func reloadConfig(_: Any?) {
        settings = KanaSettings.load()
        TerminalBridge.reload(settings: settings)
        SkinManager.invalidate()
        for window in windows {
            window.settings = settings
            window.skin = skin
            window.applyTheme()
        }
        reportConfigIssues()
    }

    /// Config mistakes show as a sheet rather than being silently ignored.
    private func reportConfigIssues() {
        let issues = TerminalBridge.configurationIssues(settings: settings)
        guard !issues.isEmpty, let window = active?.window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Problems in your Kana config"
        alert.informativeText = issues.prefix(8).joined(separator: "\n")
            + (issues.count > 8 ? "\n…and \(issues.count - 8) more" : "")
            + "\n\n" + KanaSettings.configFile.path
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Config Folder")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertSecondButtonReturn { self?.openConfigFolder(nil) }
        }
    }

    @objc func openConfigFolder(_: Any?) {
        let dir = KanaSettings.configDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    // MARK: menu

    private func makeMenu() -> NSMenu {
        let main = NSMenu()

        func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = target
            return item
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            main.addItem(holder)
        }

        submenu("Kana", [
            item("About Kana", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp),
            .separator(),
            item("Open Config Folder", #selector(openConfigFolder(_:)), ",", target: self),
            item("Reload Config", #selector(reloadConfig(_:)), ",", [.command, .shift], target: self),
            item("Command Palette", #selector(showCommandPalette(_:)), "k", [.command, .shift], target: self),
            {
                // ⌘⇧P too, Ghostty's shortcut: works, but not listed
                let alias = item("Command Palette", #selector(showCommandPalette(_:)), "p", [.command, .shift], target: self)
                alias.isHidden = true
                alias.allowsKeyEquivalentWhenHidden = true
                return alias
            }(),
            .separator(),
            item("Hide Kana", #selector(NSApplication.hide(_:)), "h", target: NSApp),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], target: NSApp),
            .separator(),
            item("Quit Kana", #selector(NSApplication.terminate(_:)), "q", target: NSApp),
        ])

        var shell = [
            item("New Window", #selector(newWindow(_:)), "n", target: self),
            item("New Tab", #selector(newTab(_:)), "t", target: self),
            .separator(),
            item("Close", #selector(close(_:)), "w", target: self),
            item("Close Tab", #selector(closeTab(_:)), "w", [.command, .option], target: self),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]),
            .separator(),
            item("Next Tab", #selector(nextTab(_:)), "]", [.command, .shift], target: self),
            item("Previous Tab", #selector(previousTab(_:)), "[", [.command, .shift], target: self),
        ]
        for i in 1 ... 9 {
            let tab = item("Tab \(i)", #selector(selectTab(_:)), "\(i)", target: self)
            tab.tag = i - 1
            tab.isAlternate = false
            shell.append(tab)
        }
        submenu("Shell", shell)

        func arrow(_ key: Int) -> String { String(Character(UnicodeScalar(key)!)) }
        var splitItems = [
            item("Split Right", #selector(splitRight(_:)), "d", target: self),
            item("Split Down", #selector(splitDown(_:)), "d", [.command, .shift], target: self),
            .separator(),
        ]
        let moves: [(String, String, NSEvent.ModifierFlags)] = [
            ("Previous Split", "[", .command),
            ("Next Split", "]", .command),
            ("Split Above", arrow(NSUpArrowFunctionKey), [.command, .option]),
            ("Split Below", arrow(NSDownArrowFunctionKey), [.command, .option]),
            ("Split on the Left", arrow(NSLeftArrowFunctionKey), [.command, .option]),
            ("Split on the Right", arrow(NSRightArrowFunctionKey), [.command, .option]),
        ]
        for (i, move) in moves.enumerated() {
            let focus = item(move.0, #selector(focusSplit(_:)), move.1, move.2, target: self)
            focus.tag = i
            splitItems.append(focus)
        }
        splitItems += [
            .separator(),
            item("Zoom Split", #selector(toggleSplitZoom(_:)), "\r", [.command, .shift], target: self),
            item("Equalize Splits", #selector(equalizeSplits(_:)), "=", [.command, .control], target: self),
        ]
        submenu("Split", splitItems)

        submenu("Edit", [
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])

        submenu("View", [
            item("Focus Mode", #selector(toggleFocusMode(_:)), "f", [.command, .shift], target: self),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])

        submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
        ])
        NSApp.windowsMenu = main.items.last?.submenu

        return main
    }
}

@main
enum KanaMain {
    static func main() {
        handOffToHelperIfCalledAsCLI()
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.setActivationPolicy(.regular)
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        }
    }

    /// `kana banner` / `kana keys` meant the helper in Contents/Resources/bin.
    /// If a shell found this binary instead (macOS disks ignore case, and
    /// Ghostty puts Contents/MacOS in PATH), run the helper rather than
    /// opening a second Kana.
    private static func handOffToHelperIfCalledAsCLI() {
        let args = CommandLine.arguments
        guard args.count > 1, ["banner", "keys", "help", "version", "--still"].contains(args[1]) else { return }
        // a CLI call never opens a window, even when the helper is missing
        guard let helper = Bundle.main.resourceURL?.appendingPathComponent("bin/kana").path,
              FileManager.default.isExecutableFile(atPath: helper)
        else {
            FileHandle.standardError.write(Data("kana: the helper isn't in this Kana.app (Contents/Resources/bin/kana)\n".utf8))
            exit(1)
        }
        var argv: [UnsafeMutablePointer<CChar>?] = ([helper] + args.dropFirst()).map { strdup($0) }
        argv.append(nil)
        execv(helper, argv)
        perror("kana: couldn't start the helper")
        exit(1)
    }
}
