// Contract C4 (TASKS.md), part 2: what the command palette lists. Claude
// builds the list (every menu action, themes...); CommandPaletteView (T1.8)
// shows and runs it.

/// One entry in the palette.
struct PaletteCommand: Identifiable {
    let id: String
    /// What's searched and shown, e.g. "Split Right".
    let title: String
    /// Shown dimmer after the title, e.g. "Theme" or a folder. Not searched.
    var subtitle: String?
    /// Display form of the shortcut, e.g. "⌘D". Shown on the right.
    var shortcut: String?
    /// Runs after the palette has closed.
    let run: @MainActor () -> Void
}
