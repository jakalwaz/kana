import AppKit
import SwiftUI

/// Hosts CommandPaletteView over a window: the palette hangs under the
/// header, and a click anywhere else closes it. Based on Ghostty's
/// Features/Command Palette/TerminalCommandPalette.swift (overlay, dismiss
/// on outside click, focus back to the terminal).
@MainActor
final class PaletteOverlay: NSView {
    var onDismiss: (() -> Void)?

    init(commands: [PaletteCommand], topInset: CGFloat) {
        super.init(frame: .zero)
        let host = NSHostingView(rootView: CommandPaletteView(commands: commands) { [weak self] in
            self?.onDismiss?()
        })
        host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.centerXAnchor.constraint(equalTo: centerXAnchor),
            host.topAnchor.constraint(equalTo: topAnchor, constant: topInset + 12),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    /// Only reached when the click missed the palette.
    override func mouseDown(with _: NSEvent) {
        onDismiss?()
    }
}

extension PaletteCommand {
    /// Every menu item that does something, with its real shortcut. The
    /// menu is the one list of actions, so the palette never falls behind.
    @MainActor
    static func fromMenu(_ menu: NSMenu, section: String? = nil) -> [PaletteCommand] {
        menu.update() // runs validation, so isEnabled is current
        return menu.items.flatMap { item -> [PaletteCommand] in
            if let submenu = item.submenu {
                return fromMenu(submenu, section: submenu.title.isEmpty ? item.title : submenu.title)
            }
            guard let action = item.action, !item.isSeparatorItem, !item.isHidden, item.isEnabled,
                  action != #selector(AppDelegate.showCommandPalette(_:))
            else { return [] }
            let target = item.target
            return [PaletteCommand(
                // the item itself: two windows called "zsh" both list in Window
                id: "menu:\(ObjectIdentifier(item).hashValue)",
                title: item.title,
                subtitle: section,
                shortcut: shortcutText(item),
                run: { [weak item] in NSApp.sendAction(action, to: target, from: item) }
            )]
        }
    }

    /// "⌃⌥⇧⌘D" style, like the menu shows it.
    @MainActor
    static func shortcutText(_ item: NSMenuItem) -> String? {
        let key = item.keyEquivalent
        guard !key.isEmpty else { return nil }
        let mods = item.keyEquivalentModifierMask
        var text = ""
        if mods.contains(.control) { text += "⌃" }
        if mods.contains(.option) { text += "⌥" }
        if mods.contains(.shift) { text += "⇧" }
        if mods.contains(.command) { text += "⌘" }
        switch key.unicodeScalars.first.map({ Int($0.value) }) {
        case 13: text += "↩"
        case NSUpArrowFunctionKey: text += "↑"
        case NSDownArrowFunctionKey: text += "↓"
        case NSLeftArrowFunctionKey: text += "←"
        case NSRightArrowFunctionKey: text += "→"
        default: text += key.uppercased()
        }
        return text
    }
}
