import KanaCore
import SwiftUI

@MainActor
struct CommandPaletteView: View {
    private let commands: [PaletteCommand]
    private let onDismiss: () -> Void
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var searchFocused: Bool

    init(commands: [PaletteCommand], onDismiss: @escaping () -> Void) {
        self.commands = commands
        self.onDismiss = onDismiss
    }

    var body: some View {
        let results = FuzzyRanker.rank(commands, query: query, text: \.title)
        VStack(spacing: 0) {
            TextField("Type a command…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(16)
                .focused($searchFocused)
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1, count: results.count)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1, count: results.count)
                    return .handled
                }
                .onKeyPress(.escape) {
                    onDismiss()
                    return .handled
                }
                .onSubmit {
                    guard results.indices.contains(selectedIndex) else { return }
                    run(results[selectedIndex].item)
                }
            Divider()
            if results.isEmpty {
                Text("No matching commands")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.item.id) { index, result in
                                row(result.item, match: result.match, selected: index == selectedIndex)
                                    .id(index)
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: CGFloat(min(results.count, 10)) * 36 + 12)
                    .onChange(of: selectedIndex) { _, index in
                        proxy.scrollTo(index)
                    }
                    .onChange(of: query) { _, _ in
                        proxy.scrollTo(0, anchor: .top)
                    }
                }
            }
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .onChange(of: query) { _, _ in selectedIndex = 0 }
        .onChange(of: commands.map(\.id)) { _, _ in selectedIndex = 0 }
        .onAppear {
            // Ghostty also defers focus until the panel has attached its field.
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private func row(_ command: PaletteCommand, match: FuzzyMatch, selected: Bool) -> some View {
        Button { run(command) } label: {
            HStack(spacing: 8) {
                Text(highlighted(command.title, positions: match.positions))
                    .foregroundStyle(.primary)
                    .layoutPriority(1)
                if let subtitle = command.subtitle {
                    Text(subtitle).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let shortcut = command.shortcut {
                    Text(shortcut).foregroundStyle(.secondary).fixedSize()
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.16) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func highlighted(_ title: String, positions: [Int]) -> AttributedString {
        var text = AttributedString(title)
        for offset in positions {
            let start = text.index(text.startIndex, offsetByCharacters: offset)
            let end = text.index(start, offsetByCharacters: 1)
            text[start..<end].font = .body.bold()
        }
        return text
    }

    private func moveSelection(by delta: Int, count: Int) {
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func run(_ command: PaletteCommand) {
        let action = command.run
        onDismiss()
        DispatchQueue.main.async { action() }
    }
}
