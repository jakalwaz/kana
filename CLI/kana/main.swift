// `kana`: the helper command inside Kana.app (docs/KANA.md section 5).
//
//   kana                     the welcome screen: the intro plays, then the keys
//   kana banner --still      the same, straight to the last frame
//   kana keys                just the keys and features
//
// Kana's zsh layer runs `kana banner` before the first prompt of a new tab.

import Darwin
import Foundation
import KanaBanner
import KanaSkins

let env = ProcessInfo.processInfo.environment
nonisolated(unsafe) var args = Array(CommandLine.arguments.dropFirst())

func flag(_ name: String) -> Bool {
    if let i = args.firstIndex(of: name) { args.remove(at: i); return true }
    return false
}

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let value = args[i + 1]
    args.removeSubrange(i ... i + 1)
    return value
}

func terminalSize() -> (columns: Int, rows: Int) {
    var size = winsize()
    if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 {
        return (Int(size.ws_col), Int(size.ws_row))
    }
    return (Int(env["COLUMNS"] ?? "") ?? 100, Int(env["LINES"] ?? "") ?? 40)
}

func write(_ s: String) {
    FileHandle.standardOutput.write(Data(s.utf8))
}

/// The active skin's folder: KANA_SKIN_DIR from the app, else `skin = ` in
/// the config.
func skinDirectory() -> URL {
    if let dir = env["KANA_SKIN_DIR"] { return URL(fileURLWithPath: dir) }
    let config = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/kana")
    var name = "akira"
    if let text = try? String(contentsOf: config.appendingPathComponent("config"), encoding: .utf8) {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == "skin" { name = parts[1] }
        }
    }
    return config.appendingPathComponent("skins/\(name)")
}

struct SkinParts {
    var name: String?
    var accentHex: String?
    var clip: KanaClip?
}

/// Reads skin.json, then loads the one intro conversion that best fits
/// the terminal. A skin can hold the intro at several widths
/// (intro-96.kana, intro-120.kana, ...): converting from the video at the
/// right width looks far better than shrinking ASCII. Without them it
/// falls back to intro.kana (or portrait.kana) and resamples.
func loadSkin(columns: Int, rows: Int) -> SkinParts {
    let dir = skinDirectory()
    var parts = SkinParts()
    if let data = try? Data(contentsOf: dir.appendingPathComponent("skin.json")),
       let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    {
        parts.name = json["name"] as? String
        parts.accentHex = json["accent"] as? String
    }

    let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    var sized: [(width: Int, name: String)] = files.compactMap { file in
        guard file.hasPrefix("intro-"), file.hasSuffix(".kana"),
              let width = Int(file.dropFirst(6).dropLast(5)) else { return nil }
        return (width, file)
    }
    sized.sort { $0.width < $1.width }

    if let smallest = sized.first, let probe = try? KanaClipLoader.load(from: dir.appendingPathComponent(smallest.name)) {
        let want = Banner.plannedArtWidth(columns: columns, rows: rows, probe: probe)
        // the smallest conversion at least as wide as needed, else the largest
        let pick = sized.first { $0.width >= want } ?? sized.last!
        parts.clip = pick.name == smallest.name ? probe : try? KanaClipLoader.load(from: dir.appendingPathComponent(pick.name))
    }
    if parts.clip == nil {
        for name in ["intro.kana", "portrait.kana"] {
            if let clip = try? KanaClipLoader.load(from: dir.appendingPathComponent(name)) {
                parts.clip = clip
                break
            }
        }
    }
    return parts
}

// MARK: raw input, so any key skips the animation

nonisolated(unsafe) var savedTermios = termios()
nonisolated(unsafe) var rawMode = false

func enterRawMode() {
    guard !rawMode, isatty(STDIN_FILENO) == 1, tcgetattr(STDIN_FILENO, &savedTermios) == 0 else { return }
    var raw = savedTermios
    raw.c_lflag &= ~tcflag_t(ICANON | ECHO | ISIG)
    tcsetattr(STDIN_FILENO, TCSANOW, &raw)
    rawMode = true
}

func restoreTerminal() {
    if rawMode { tcsetattr(STDIN_FILENO, TCSANOW, &savedTermios); rawMode = false }
    write("\u{1B}[0m\u{1B}[?25h")
}

/// Waits up to `ms` for a key. Returns true (and swallows the input) if one came.
func keyPressed(within ms: Int32) -> Bool {
    guard rawMode else { usleep(useconds_t(max(0, ms)) * 1000); return false }
    var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
    guard poll(&fds, 1, ms) > 0 else { return false }
    var buffer = [UInt8](repeating: 0, count: 64)
    repeat {
        _ = read(STDIN_FILENO, &buffer, buffer.count)
        fds.revents = 0
    } while poll(&fds, 1, 0) > 0
    return true
}

/// Asks the terminal where the cursor is (DSR). 1-based row, or nil.
func cursorRow() -> Int? {
    guard rawMode else { return nil }
    write("\u{1B}[6n")
    var reply = [UInt8]()
    var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
    var byte: UInt8 = 0
    while poll(&fds, 1, 200) > 0, read(STDIN_FILENO, &byte, 1) == 1 {
        reply.append(byte)
        if byte == UInt8(ascii: "R") { break }
    }
    // ESC [ row ; col R
    guard let text = String(bytes: reply, encoding: .ascii),
          let open = text.firstIndex(of: "["), let semi = text.firstIndex(of: ";")
    else { return nil }
    return Int(text[text.index(after: open) ..< semi])
}

/// A new tab starts with macOS's "Last login: …" line. When that's all
/// that's on screen, clear it so the welcome screen starts at the top.
func clearLoginLine() {
    if let row = cursorRow(), row <= 2 {
        write("\u{1B}[H\u{1B}[2J")
    }
}

for sig in [SIGTERM, SIGHUP, SIGINT] {
    signal(sig) { _ in
        restoreTerminal()
        exit(1)
    }
}

// MARK: commands

func banner(animate: Bool, first: Bool) {
    defer { if rawMode { restoreTerminal() } }
    if first, isatty(STDOUT_FILENO) == 1 {
        enterRawMode()
        clearLoginLine()
    }
    let size = terminalSize()
    let columns = Int(option("--columns") ?? "") ?? size.columns
    let rows = Int(option("--rows") ?? "") ?? size.rows
    let skin = loadSkin(columns: columns, rows: rows)
    let accent = RGB(hex: env["KANA_ACCENT"] ?? skin.accentHex ?? "") ?? RGB(0xE0, 0x26, 0x2F)
    let b = Banner(.init(
        columns: columns, rows: rows, accent: accent,
        workingDirectory: FileManager.default.currentDirectoryPath,
        skinName: skin.name, clip: skin.clip
    ))

    guard animate, let clip = b.clip, clip.frames.count > 1, isatty(STDOUT_FILENO) == 1 else {
        write(b.render())
        return
    }

    // The box, closed right under the art while it plays.
    write("\u{1B}[?25l")
    enterRawMode()
    write((b.head + b.artLines(frame: 0) + [b.bottom]).joined(separator: "\n") + "\n")

    // Redraw the art in place. The cursor sits on the line under the
    // bottom border, so the art starts artHeight + 1 lines up.
    func draw(_ frame: Int) {
        var out = "\u{1B}[\(b.artHeight + 1)A"
        for (r, line) in b.artLines(frame: frame).enumerated() {
            if r > 0 { out += "\u{1B}[1B" }
            out += "\r" + line
        }
        out += "\u{1B}[2B\r"
        write(out)
    }

    let start = Date()
    let fps = Double(max(1, clip.fps))
    var shown = 0
    var skipped = false
    while shown < clip.frames.count - 1 {
        let next = start.addingTimeInterval(Double(shown + 1) / fps)
        let wait = Int32(max(0, next.timeIntervalSinceNow * 1000))
        if keyPressed(within: wait) { skipped = true; break }
        shown = min(clip.frames.count - 1, Int(Date().timeIntervalSince(start) * fps))
        draw(shown)
    }
    // always land on the resting frame
    draw(clip.portraitIndex)

    // Then the bottom line slides down, uncovering the panels above it.
    if !skipped, keyPressed(within: 180) { skipped = true }
    for line in b.panels {
        write("\u{1B}[1A\r" + line + "\n" + b.bottom + "\n")
        if !skipped, keyPressed(within: 28) { skipped = true }
    }
}

func keys() {
    let skin = loadSkin(columns: 0, rows: 0)
    let accent = RGB(hex: env["KANA_ACCENT"] ?? skin.accentHex ?? "") ?? RGB(0xE0, 0x26, 0x2F)
    let b = Banner(.init(columns: terminalSize().columns, rows: 60, accent: accent,
                         workingDirectory: FileManager.default.currentDirectoryPath, skinName: skin.name, clip: nil))
    write((b.head + b.panels + [b.bottom]).joined(separator: "\n") + "\n")
}

let command = args.first(where: { !$0.hasPrefix("-") }) ?? "banner"
args.removeAll { $0 == command }
switch command {
case "banner":
    // animates unless told not to; --animate is kept for older callers
    _ = flag("--animate")
    banner(animate: !flag("--still"), first: flag("--new-tab"))
case "keys", "help":
    keys()
case "version", "--version":
    write("kana \(Banner.version)\n")
default:
    write("usage: kana [banner [--still] | keys | version]\n")
    exit(2)
}
