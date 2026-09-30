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

### C2: SplitTree (KanaCore)

The split layout of one tab: a pure value type in `Core/SplitTree.swift`. **The API is the stub in that file** (types, signatures and the doc comment on each function are the contract). T1.1 fills in the bodies; T1.2 codes against the signatures. In short:

- `SplitTree<Leaf: AnyObject>` with `root: Node?`, `zoomed: Leaf?`. `Node` is `.leaf(Leaf)` or `.split(Split { axis, ratio, first, second })`.
- `leaves`, `contains`, `inserting(_:at:side:)`, `removing`, `toggledZoom`, `equalized`, `resizing(_:ratio:)`, `focusTarget(from:_:in:)`, `layout(in:divider:) -> SplitLayout`.
- Leaves are compared by identity. Coordinates are flipped (y down), and `first` of a vertical split is the top. Ratios are clamped to 0.1...0.9.

### C3: KanaConfig (KanaCore)

`~/.config/kana/config` parsing, and rendering it into the Ghostty config file the app loads. **The API is the stub in `Core/KanaConfig.swift`** (signatures plus doc comments). Kana's own keys (`skin`, `intro`, `banner`, `suggestions`, `notify-on-command-finish[-after]`, `quick-terminal-hotkey`, `theme`) are parsed into fields. Every other line passes to Ghostty unchanged and in order. `renderGhostty` writes Kana's defaults, then the user's lines, then the resolved theme, then Kana's enforced lines last.

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
| T0.8 | Original default skin: `tools/ascii/make_default_skin.py` draws a simple original animation (a red light streak sliding in and coming to rest, no copyrighted imagery) straight to frames, and writes `Resources/skins/default/intro.kana`, `portrait.kana` and `skin.json` | codex | `tools/ascii/make_default_skin.py`, `Resources/skins/default/**` | none | review (needs Jak's look) |
| T0.9 | Confirm before closing a window or quitting while something is running (Ghostty's `needs_confirm_quit`). Tab close already confirms | claude | `App/Window/*`, `App/KanaApp.swift` | T0.4 | blocked: libghostty-spm keeps the surface handle internal, see Decisions |

**Phase 0 done when:** nvim, htop and Claude Code run in Kana with no visual glitches (Jak checks), KanaSkins tests pass, and `script/test` runs everything.


## Phase 1: daily driver (plan: splits first, then config + themes, notifications + links, find, quick terminal, palette)

| ID | Task | Owner | Files | Depends on | Status |
|---|---|---|---|---|---|
| T1.1 | SplitTree per contract C2, ported from Ghostty's SplitTree.swift, with Swift Testing tests for every operation | codex | `Core/SplitTree.swift`, `Tests/KanaCoreTests/**` | none | done |
| T1.2 | Splits in the window: SplitContainerView, a split tree per tab, ⌘D / ⌘⇧D, ⌘⌥arrows, ⌘[ ], ⌘⇧↩ zoom, ⌃⌘= equalize, drag dividers, ⌘W closes a split, dim unfocused | claude | `App/Window/*`, `App/Terminal/*`, `App/KanaApp.swift`, `Package.swift` | T1.1 contract | review (needs Jak's checklist) |
| T1.3 | KanaConfig: Kana keys vs Ghostty passthrough, render one Ghostty config file; vendor themes | codex | `Core/KanaConfig.swift`, `Tests/KanaCoreTests/**`, `tools/themes/**`, `Resources/themes/**` | C3 | done |
| T1.4 | Config wiring: controller from the rendered file, `theme =`, ⌘⇧, reload, error banner | claude | `App/Terminal/*`, `App/KanaSettings.swift`, `script/build` | T1.3 | review (needs Jak's checklist) |
| T1.5 | Notifications (command finished, OSC 9/777, bell), tab attention dot + dock badge, progress bar, ⌘-click URLs + hover preview | claude | `App/Notify/*`, `App/Terminal/*`, `App/Window/*` | T1.2 | todo |
| T1.6 | Find in scrollback: ⌘F bar, ⌘G / ⇧⌘G, ⌘E | claude | `App/Window/*`, `App/Terminal/*` | T1.2 | todo |
| T1.7 | Quick terminal: global hotkey drop-down panel | claude | `App/Window/*`, `App/KanaApp.swift` | T1.2 | todo |
| T1.8 | FuzzyMatch + CommandPaletteView (SwiftUI) per C4 | codex | `Core/FuzzyMatch.swift`, `App/Palette/**`, `Tests/KanaCoreTests/**` | C4 (to write) | todo |
| T1.9 | Palette commands for every action, theme switching, ⌘⇧K / ⌘⇧P | claude | `App/KanaApp.swift`, `App/Window/*` | T1.8 | todo |

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
- **Process: Codex review of last session's work.** Codex is connected now (called with `model: gpt-6-astra`). Batch 1 (bridge, input, window, tabs: T0.1 to T0.4, P2.2) is reviewed and fixed. Batch 2 (zsh layer P2.1, welcome screen P2.3, scripts T0.5, KanaSkins T0.6) is still to do.
- **T0.9: how to get `ghostty_surface_needs_confirm_quit`.** libghostty-spm's `AppTerminalView.surface` is internal, so Kana can't ask whether a window's tabs are busy. Open an issue or PR upstream (Lakr233/libghostty-spm) asking for a public `needsConfirmQuit` (claude recommends; it's outward-facing, so Jak's call), or vendor a patched copy (claude: no, it breaks the exact pin).

## Done log

_(newest first)_

- **2026-09-30, codex + claude: config + themes (T1.3, T1.4).**
  - T1.3 (codex): `KanaConfig` parses `~/.config/kana/config`. Kana's keys become fields; every other line goes to Ghostty in order. It renders one Ghostty config file. 15 tests. `tools/themes/vendor_themes.py` vendors 657 themes (MIT) from iTerm2-Color-Schemes, pinned to the 2026-09-28 release (Claude ran it; Codex's sandbox has no network).
  - T1.4 (claude): Kana loads `~/Library/Application Support/Kana/ghostty.conf` with an empty wrapper theme (the wrapper's default Afterglow would win over the user's theme). `theme = <name>` or `light:X,dark:Y` uses bundled or `~/.config/kana/themes`. ⌘⇧, reloads live. Config problems, including Ghostty's "unknown field" diagnostics, show as a sheet.
  - Window, header and split chrome follow the theme's background; the ink flips on light themes, and the welcome banner uses the default foreground. Checked live with Dracula, GitHub Light, and a light/dark pair.
  - Codex review: round 1 found 3 bugs (pairs couldn't follow the system appearance, reload left banner and skin stale, a failed write reloaded the old file); round 2 found 3 edge cases (quoted commas, an explicit `background` override, quoted theme values). All fixed, the last three after the round limit.

- **2026-09-30, codex + claude: splits (T1.1, T1.2).**
  - T1.1 (codex): `Core/SplitTree.swift` in a new `KanaCore` target, ported from Ghostty's SplitTree. 22 Swift Testing tests. Round 1 fixed spatial focus: it skipped a nearer split because it ranked overlap above distance, and the contract wording caused it.
  - T1.2 (claude): a split tree per tab, `SplitContainerView` with draggable dividers (double-click evens them out), the Split menu, and dimmed unfocused splits. Based on Ghostty's Features/Splits and BaseTerminalController.
  - ⌘W closes a split; the last split closes the tab. Closing a tab asks once about every busy split (codex round-1 bug); a late busy answer joins the open sheet (round-2 risk, fixed after the limit).
  - AppKit ignores Shift when matching Return, checked with a probe. So one menu item takes both ⇧⌘↩ (zoom) and ⌘↩ (full screen) and checks the event.

- **2026-09-30, claude: fixes from Codex's review of the bridge and window code.**
  - Codex reviewed T0.1 to T0.4 and P2.2 against `../ghostty-pinned` and found 7 bugs and 1 risk. All were real and all are fixed; the fixes took two review rounds and ended clean.
  - Ghostty's zsh integration never loaded. Surface env vars are applied after the integration sets ZDOTDIR (Exec.zig), so Kana's ZDOTDIR replaced it. Kana now sets `GHOSTTY_ZSH_ZDOTDIR`, and the chain is ghostty → Kana → the user's files. Tested headlessly. kana.zsh leaves the title to Ghostty when Ghostty's integration sets it.
  - ⌘W and × now ask Ghostty (`close_surface`) and confirm when something is running, like Ghostty's BaseTerminalController. The sheet closes itself if the tab exits first.
  - Closing a background tab no longer changes the selected tab.
  - Unsafe pastes and OSC 52 now ask instead of being silently denied (they had no confirmation delegate).
  - ⌘Q and ⌘, reach the menu again. ⌥⌘W and ⌘↩ work as hidden shortcuts.
  - Minimized or covered windows stop rendering (occlusion).
  - Header tabs fit: eight tabs at the minimum window width, with the wordmark giving way.

- **2026-09-30, claude: the bundled default skin is the default.**
  - `skin` now defaults to `default`. The app and `kana` fall back to it when the configured skin is missing, so a fresh clone plays an intro. Jak's `~/.config/kana/config` now has `skin = akira`.
  - Reviewed by Codex in two rounds. It found that `kana` run from PATH resolved `argv[0]` against the working directory; it now uses `Bundle.main.executableURL`. Checked from `/tmp` with a missing skin name.

- **2026-09-30, codex → claude: T0.8 default skin.**
  - `tools/ascii/make_default_skin.py` draws a red light sliding in on a cubic ease-out and settling, analytically (no source media, no randomness, byte-identical runs). It writes `Resources/skins/default/` at 108×26, 48 frames at 20 fps (693 KB).
  - Two review rounds. First, the light rested flush right because the banner trims columns blank in every frame, so now it rests centred and fills the grid. Second, the fix had shrunk the grid to 48×16, which the banner upscaled into doubled characters, so the geometry now scales to 108 wide.
  - Nit, not done: above ~120 columns the banner upscales and repeats some rows. The generator could also write `intro-<w>.kana` at several widths like the Akira skin.

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
