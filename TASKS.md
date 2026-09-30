# TASKS.md

The shared task board. Owners only edit the files listed under their own tasks. Status is one of `todo`, `doing`, `review`, `done`, `blocked`.

---

## Contracts

Agreed interfaces. Code against these. Don't change them without Jak's OK (add to Decisions needed).

### C1: KanaSkins Swift package

Loads `.kana` files and skin folders. The format is defined in `docs/KANA.md` section 7 and produced by `tools/ascii/convert.py`.

```swift
// Packages/KanaSkins/Sources/KanaSkins/

public struct KanaFrame: Sendable {
    public let rows: [String]          // height strings, each width characters
    public let colors: Data?           // width * height * 3 RGB bytes, row by row, nil if no color
    public func color(x: Int, y: Int, width: Int) -> (r: UInt8, g: UInt8, b: UInt8)?
}

public struct KanaClip: Sendable {
    public let width: Int
    public let height: Int
    public let fps: Int                // 0 for a still image
    public let hasColor: Bool
    public let portraitIndex: Int
    public let frames: [KanaFrame]
    public var portrait: KanaFrame { frames[portraitIndex] }
    public var duration: TimeInterval  // 0 for a still
}

public enum KanaClipError: Error, Equatable {
    case unreadable, notKanaFile, unsupportedVersion(Int), malformed(String)
}

public enum KanaClipLoader {
    public static func load(from url: URL) throws -> KanaClip
    public static func load(data: Data) throws -> KanaClip
}

public struct Skin: Sendable {
    public let name: String
    public let accentHex: String       // "#rrggbb"
    public let portraitOpacity: Double // default 0.35
    public let intro: KanaClip?
    public let portrait: KanaClip?     // falls back to intro's portrait frame when nil
}

public enum SkinLoader {
    public static func load(directory: URL) throws -> Skin
    public static func available(in root: URL) -> [URL]   // skin folders that contain a skin.json
}
```

Rules: validate that every frame has `height` rows of exactly `width` characters (count Characters, not UTF-8 bytes, because the `blocks` and `dots` ramps use multi-byte characters) and that `colors` decodes to `width * height * 3` bytes. Clamp `portrait` into range. Throw `malformed` with a useful message otherwise.

---

## Phase 0: Engine spike

| ID | Task | Owner | Files | Depends on | Status |
|---|---|---|---|---|---|
| T0.1 | App target `Kana`: macOS 14, arm64, Swift 6, window titled Kana. Built with SwiftPM (`Package.swift`) instead of an Xcode project, see Decisions | claude | `Package.swift`, `App/KanaApp.swift`, `App/Window/*` | none | review |
| T0.2 | Add a pinned prebuilt libghostty Swift package. Evaluate the libghostty-spm options, pick one, write why in the summary | claude | `Package.swift`, `Package.resolved` | T0.1 | review |
| T0.3 | `TerminalBridge` + `TerminalPane`: one libghostty surface in the window running the user's login shell | claude | `App/Terminal/*` | T0.2 | review |
| T0.4 | Input, resize, scroll, copy and paste working like Ghostty | claude | `App/Terminal/*`, `App/Window/*` | T0.3 | review (needs Jak's checklist) |
| T0.5 | `script/build`, `script/test`, `script/run`: build with SwiftPM into `build/Kana.app`, run Swift, zsh and Python tests, launch the app | codex → claude | `script/*` | none | review |
| T0.6 | KanaSkins package per contract C1, with unit tests covering good files, stills, bad JSON, wrong row width, wrong color length, portrait clamping | codex → claude | `Packages/KanaSkins/**` | none | review |
| T0.7 | pytest suite for `convert.py`: generate a synthetic clip and image in a temp dir, check convert, portrait options, crop, no-color, and error cases | codex | `tools/ascii/tests/**` | none | done |
| T0.8 | Original default skin: `tools/ascii/make_default_skin.py` draws a simple original animation (a red light streak sliding in and coming to rest, no copyrighted imagery) straight to frames, and writes `Resources/skins/default/intro.kana`, `portrait.kana` and `skin.json` | codex | `tools/ascii/make_default_skin.py`, `Resources/skins/default/**` | none | doing |

**Phase 0 done when:** nvim, htop and Claude Code run in Kana with no visual glitches (Jak checks), KanaSkins tests pass, and `script/test` runs everything.

## Side quest: intro assets (Jak)

| ID | Task | Owner | Status |
|---|---|---|---|
| S1 | Find and trim the Akira slide clip into `assets/private/` | jak | done (`0929.mp4`) |
| S2 | Tune it with `convert.py --preview` until the slide and stand-up both read well | jak + claude | review |

## Pulled forward from Phase 2 (Jak asked)

| ID | Task | Owner | Files | Depends on | Status |
|---|---|---|---|---|---|
| P2.1 | Inline suggestions: grey ghost text from history, command names and paths, Tab / → / End accept, Alt-→ one word, Ctrl-Alt-Space toggle | claude | `App/Shell/zsh/*`, `script/test-shell.zsh` | T0.3 | review |
| P2.2 | Mew-style header with tabs (⌘T, ⌘W, ⌘1-9, ⌘⇧[ ]), Focus Mode (⌘⇧F), pure black theme | claude | `App/Window/*`, `App/Terminal/TerminalBridge.swift` | T0.3 | review |
| P2.3 | Welcome screen printed into the terminal (Claude Code style): wordmark, the skin's animation playing in place and resting on its last frame, keys and features panels. `kana` helper command (`kana`, `kana keys`), run by the zsh layer on a new tab | claude | `CLI/**`, `Tests/KanaBannerTests/**`, `App/Skins/*`, `App/Terminal/*`, `App/Shell/zsh/kana.zsh` | T0.6 | review |
| P2.4 | termframe snapshots: `convert.py snapshot` renders a frame as an SVG window screenshot | claude | `tools/ascii/convert.py` | none | review |

---

## Requests

Changes someone needs in files they don't own. Format: `from → to: what and why`.

_(none yet)_

## Decisions needed

Things for Jak. Format: `task: question, option A (who), option B (who)`.

- **T0.1: SwiftPM or an Xcode project?** Xcode wasn't usable when this started (no license accepted), so Kana is a SwiftPM package that `script/build` wraps into `build/Kana.app`. Keep SwiftPM: builds from the terminal and the Command Line Tools, no pbxproj merge conflicts (claude). Add an Xcode project later for signing, entitlements and asset catalogs (open).
- **P2.1: suggestions live in zsh, not in the app.** The spec puts them in `App/History/` and accepts with →. Kana loads its own zsh layer through ZDOTDIR (chained after libghostty's shell integration), so suggestions follow the real line editor (vi mode, multi-line, completion menus) instead of guessing what's typed. Tab accepts as you asked, → still works too. The cost: zsh only for now; bash and fish get nothing. Keep in zsh (claude), or build app-side suggestions later for every shell (open).
- **P2.3: the intro plays in the terminal, not in a native overlay.** Spec section 7 says "renders in a native overlay, never through the shell". Jak asked for a Claude Code style welcome screen that stays in the scrollback, so `kana banner` prints it through the shell before the first prompt. It only redraws its own box (relative cursor moves) and puts the terminal back afterwards (tested through a pty, with and without a skip key). The native overlay and the portrait header are gone. `clear` then `kana` brings it back. Keep it in the terminal (claude), or bring back an overlay for the first second (open).
- **Process: no Codex this session.** The `codex-cli` MCP server wasn't connected, so T0.5 and T0.6 were done by Claude and nothing got a Codex review. Connect it (`claude mcp add codex-cli -- npx -y codex-mcp-server`) and run a review pass before merging.

## Done log

_(newest first)_

- **2026-09-30, codex → claude: T0.7 convert.py tests.**
  - `tools/ascii/tests/`: 40 pytest tests through the real argparse entry point, on a generated 64×48 clip and still: the C1 rules for every ramp, sampling (fps, duration, start, max frames), portrait index and time plus clamping, grid size, crop and push-in, no-color, `info`, and error exits.
  - They found a real bug: float noise floored a crop edge one pixel early (`--crop-move 0.2,0.8`). Fixed in `crop_frame` with an epsilon, and the xfail is now a normal test. pytest is installed in `.venv`.

- **2026-09-29, claude: the intro pushes in on the bike.**
  - At rest the bike was about 30% × 19% of the frame, with smoke below it. convert.py gained `--crop-end` and `--crop-move`.
  - The intro now starts as a 2.4:1 band with the bottom smoke cut off, then eases in (0.4 s to 1.6 s) to a crop centred on the bike, measured at x 0.275 to 0.652.
  - Resting frame first centred (centre of mass at column 59.6 of 120), then nudged left at Jak's request (crop x 0.255, centre of mass 54.8). All 13 widths were regenerated.

- **2026-09-29, claude: welcome screen, second pass (Jak's feedback).**
  - One box: the wordmark (カナ moved into the title), then the whole animation with no cropping, as large as fits. While it plays the box closes under the art; then the bottom line slides down and uncovers the panels.
  - The finished screen plus the prompt always fits, so KANA stays in view. Empty rows above the resting frame are trimmed, so there's no gap under the wordmark.
  - Quality: the intro is converted from the video at 13 widths (`intro-<w>.kana`) and `kana` loads the closest one. Default window is now 80% of the screen, capped at 1180×820. Every new tab animates (`intro = on` is the default), and `kana` replays it.
  - Tests: 13 KanaBanner tests. A pty check shows the tty is restored after a full play (2.7 s) and after a skip.

- **2026-09-29, claude: welcome screen (P2.3 reworked).**
  - Intro is now the new clip (`assets/private/0929-v2.mp4`, background cut out), converted at 180×51 and 30 fps into `~/.config/kana/skins/akira/intro.kana`.
  - New `KanaBanner` library plus the `kana-cli` executable, installed as `Kana.app/Contents/Resources/bin/kana`. The `kana` command shrinks the clip to fit the box by averaging character density.
  - Tests: 9 KanaBanner tests (box width at 5 terminal sizes, fits the screen, slot matches the clip, resampler), plus a pty check that the tty is restored.

- **2026-09-29, claude: T0.1 to T0.6, P2.1 to P2.4 to review.**
  - libghostty: picked Lakr233/libghostty-spm, pinned `exact: "1.6.20260929"` (Ghostty 0538f7535be0). It's released weekly, ships an AppKit surface view with Ghostty's input, IME, resize and paste handling, bundles MIT zsh and bash integration, and runs the real login shell through the `.exec` backend. sethdeckard/libghostty-spm is only the raw C API at v0.2.0, so every view would have to be written from scratch.
  - Bridge based on libghostty-spm's `Example/GhosttyTerminalApp` and Ghostty's `src/config/Config.zig` default keybinds (Kana unbinds the ones its menu owns).
  - Tests: 11 KanaSkins tests and 10 zsh end-to-end tests (zpty) pass, and the app builds.
  - convert.py gained `--luma value`, `--normalize`, `--vivid`, `--grey-dim`, `--sat-lift` and `snapshot` (termframe).
