# Kana

A native macOS terminal built on libghostty. It has Ghostty's engine, a Mew-style workspace layer, and AI built in: a bring-your-own-key assistant plus panes for running coding agents side by side.

The name comes from Kaneda, and kana are also the Japanese syllable characters. A terminal is a grid of characters, and the mascot is an anime scene turned into characters, so it fits both ways.

The code lives in a public GitHub repo, but Kana is built for my own daily use first. Nothing in v1 is designed around other users.

---

## 1. Goals and non-goals

**Goals**
- Feel as fast and correct as Ghostty for everyday terminal use (nvim, htop, tmux, ssh, Claude Code)
- Mew-style quality of life: profiles, history search, inline suggestions, command palette, Focus Mode
- An AI assistant that uses my own API keys, reads terminal context, and never runs anything without me hitting enter
- Run several CLI agents (Claude Code, Codex, Gemini CLI, etc.) in parallel, each optionally in its own git worktree, with a heads-up when one needs me
- An ASCII anime intro: the Akira bike slide on launch, then Kaneda standing up as the resting portrait
- Swappable skins so the intro and portrait can change (Guts, Edgerunners, whatever)

**Non-goals (v1)**
- Writing a terminal emulator from scratch. libghostty does emulation, rendering, fonts and the PTY
- Linux or Windows support
- Intel Macs
- Local models (Ollama, LM Studio). The provider interface should allow them later, but they're not in v1
- Building my own coding agent. Agent panes run existing CLIs
- Cloud sync, accounts, teams, telemetry

---

## 2. Locked decisions

| Decision | Choice |
|---|---|
| Name | Kana (app and `kana` CLI helper) |
| Platform | macOS 14+, Apple silicon only |
| Engine | libghostty through a prebuilt Swift package, pinned to one Ghostty revision |
| UI | AppKit for windows, tabs, splits and the terminal view. SwiftUI for settings, palette and sidebars |
| Repo | Public on GitHub, built for my own use |
| Distribution | Ad hoc signed build, optional personal Homebrew tap |
| Default skin | Akira bike slide intro, holds on Kaneda standing up as the portrait. Kept local only (see section 7) |
| v1 AI scope | BYOK assistant, agent panes, worktree per agent |

---

## 3. Stack

- **Language:** Swift 6
- **Terminal engine:** libghostty (`ghostty.h` embedder API, the same C API Ghostty's own Mac app uses). Pull it in with one of the `libghostty-spm` packages so I'm not fighting the Zig toolchain
- **Storage:** SQLite through GRDB for history, sessions and agent runs
- **Secrets:** macOS Keychain
- **Networking:** URLSession with streaming (SSE) for AI responses
- **Tooling:** Xcode, SwiftLint, Python + OpenCV for the ASCII converter, ffmpeg (optional)

---

## 4. What comes from where

**Free from libghostty**
- VT emulation, scrollback, selection
- Metal rendering, fonts, ligatures, Unicode, emoji
- Themes and colors
- Shell integration (prompt marks, cwd tracking), which the AI context capture depends on
- PTY and process spawning

**Rebuilt in Kana (Ghostty's app-level features)**
- Windows, tabs, splits (resize, zoom, navigate)
- Quick terminal (global hotkey dropdown)
- Config file and keybindings
- Window and session restore

Ghostty's Mac app source is MIT, so it's the reference for how to wire all of this up. Read it before building each piece.

**Mew-style layer**
- Header bar with tabs, hidden in Focus Mode
- Profiles (shell, starting folder, startup command, theme)
- History search across all sessions
- Inline command suggestions, accepted with →, toggleable
- Command palette
- Clickable URLs and file paths
- Settings UI for themes, fonts, cursor, shortcuts, skins

---

## 5. Architecture

```
┌──────────────────────────── Window ────────────────────────────┐
│ Header: tabs · profile · agent status             (Focus Mode) │
├──────────────┬───────────────────────────────┬─────────────────┤
│ Agent        │  Split tree of TerminalPanes  │  Assistant      │
│ sidebar      │  (each = one libghostty       │  sidebar        │
│ (optional)   │   surface + PTY)              │  (optional)     │
└──────────────┴───────────────────────────────┴─────────────────┘
      ▲                    ▲                           ▲
      │                    │                           │
 AgentManager        TerminalBridge               AssistantService
 WorktreeManager     (Swift wrapper over          ProviderClients
 kana CLI socket      ghostty.h)                  ContextCapture
```

**Core modules**
- `TerminalBridge`: the only code that talks to `ghostty.h`. Everything else goes through it, so a Ghostty bump only touches one place
- `SplitTree`: the pane layout model (a binary tree of splits), serializable for restore
- `SessionStore`: SQLite for history, pane metadata, agent runs
- `ContextCapture`: uses shell integration marks to grab "last command + output + exit code + cwd"
- `AssistantService` and `ProviderClient` protocol: one client per provider
- `AgentManager`: launches agent panes, tracks status
- `WorktreeManager`: creates and cleans up git worktrees
- `SkinManager`: finds skins, loads `.kana` frame files, picks the active one
- `IntroPlayer`: plays the intro and hands off to the portrait
- `kana` CLI: a small helper binary inside the app bundle that talks to the app over a Unix socket

---

## 6. Repo structure

```
kana/
├── App/
│   ├── KanaApp.swift
│   ├── Window/            # window, header bar, Focus Mode
│   ├── Terminal/          # TerminalBridge, TerminalPane, SplitTree
│   ├── Skins/             # SkinManager, IntroPlayer, PortraitView, frame loader
│   ├── Palette/
│   ├── History/           # search + suggestions
│   ├── Profiles/
│   ├── Settings/
│   ├── Assistant/         # sidebar, prompt bar, ContextCapture
│   ├── Providers/         # Anthropic, OpenAI, Gemini, OpenRouter clients
│   ├── Agents/            # AgentManager, agent sidebar, registry
│   ├── Worktrees/
│   └── Storage/           # GRDB, Keychain
├── CLI/                   # `kana` helper binary
├── Packages/
│   └── KanaSkins/         # .kana and skin loader, its own Swift package with tests
├── Resources/
│   ├── themes/
│   └── skins/
│       └── default/       # small original placeholder skin, safe to commit
├── script/                # build, test, run
├── tools/
│   └── ascii/
│       ├── convert.py     # video or image → .kana frames file, plus terminal preview
│       ├── requirements.txt
│       ├── tests/
│       └── README.md
├── assets/
│   └── private/           # gitignored: source clips live here
├── docs/
│   ├── KANA.md            # this file
│   └── prompts/           # kickoff prompts for each phase
├── AGENTS.md              # shared rules for every coding agent
├── CLAUDE.md              # lead agent loop (imports AGENTS.md)
├── TASKS.md               # task board with owners, contracts, requests
└── .gitignore
```

The repo is public, so `.gitignore` goes in with the very first commit:

```
# source clips and anything made from them never get committed
assets/private/
*.mp4
*.mov
*.mkv
*.webm
*.kana
!Resources/skins/*/*.kana
```

---

## 7. Intro, portrait and skins

### How it plays
1. A window opens and the intro plays in an overlay on the first pane: Kaneda's bike slide, around 2 to 4 seconds
2. The clip ends on him standing up. That frame becomes the **portrait**
3. The overlay fades and the portrait stays as a faint header above the prompt, like Mew's
4. `clear` brings the portrait back. Focus Mode hides it

The shell starts loading underneath while the intro plays, so it costs no real time. Any keypress skips straight to the portrait.

### Skins
A skin is a folder with an intro, a portrait and an accent color:

```
~/.config/kana/skins/
├── akira/
│   ├── skin.json
│   ├── intro.kana          # the bike slide
│   └── portrait.kana       # optional: if missing, uses the intro's portrait frame
├── guts/
│   ├── skin.json
│   └── portrait.kana       # a skin can be portrait only, with no intro
└── ...
```

`skin.json`:
```
{
  "name": "Akira",
  "accent": "#e0262f",
  "intro": "intro.kana",
  "portrait": "portrait.kana",
  "portrait_opacity": 0.35
}
```

Kana ships two skins in `Resources/skins/`: `default`, the Akira bike slide (the intro converted at 13 widths, `intro-<w>.kana`), and `streak`, an original red light streak drawn by `tools/ascii/make_default_skin.py`. Pick one with `skin = streak` in the config, or add your own under `~/.config/kana/skins/`.

### Clip rules
- The source clips (`.mp4` and the like) never go in the repo. They stay in `assets/private/`
- The ASCII frames of the Akira skin are committed as the default skin. Jak's call (2026-10-10): a non-commercial fan project, accepting that the rights holder could ask GitHub to take it down. If that happens, `streak` becomes the default again
- Skins made from other copyrighted clips stay in `~/.config/kana/skins/`

### Picking and trimming the Akira clip
- Start just before the slide begins and end once Kaneda is fully standing, so the last frame is a clean pose
- Hold a few extra frames on the stand-up so it doesn't feel cut off
- Red bike and taillight against the dark street is what makes it read in ASCII. Crop out the extra street and sky
- If the stand-up frame is busy, pick a better frame with `--portrait-time`, or make a separate `portrait.kana` from a still

### The converter: `tools/ascii/convert.py`

Converts a video or image into a `.kana` file and previews it right in the terminal. See `tools/ascii/README.md` for all options. Typical flow:

```
# 1. convert the slide, 3.5 seconds starting at 1:23
python3 tools/ascii/convert.py convert assets/private/akira.mp4 \
  --start 83 --duration 3.5 --width 110 --fps 15 \
  --crop 0,0.15,1,0.75 --contrast 1.4 --bg-cut 0.08 \
  -o ~/.config/kana/skins/akira/intro.kana --preview

# 2. replay it any time
python3 tools/ascii/convert.py play ~/.config/kana/skins/akira/intro.kana
```

What it does per frame:
- Trims, crops and resamples to the target fps
- Resizes to the character grid (characters are about twice as tall as they are wide, so height is roughly halved)
- Applies contrast, brightness and gamma, plus optional edge boost so outlines pop
- Cuts near-black pixels to spaces so the background stays clean
- Maps brightness to a character ramp and keeps an RGB color per cell

### `.kana` format (version 1)
Plain JSON so it's easy to load from Swift and easy to inspect:

```
{
  "format": "kana-ascii",
  "version": 1,
  "width": 110,
  "height": 41,
  "fps": 15,
  "color": true,
  "portrait": 52,
  "frames": [
    { "rows": ["...", "..."], "colors": "<base64 RGB bytes, width*height*3>" }
  ]
}
```

`portrait` is the index of the frame to rest on. It defaults to the last frame. A still image makes a file with one frame and `fps` 0.

### Playback in the app
- Renders in a native overlay, never through the shell, so it can't fight with the prompt
- CoreText drawing to start. Switch to a second libghostty surface fed ANSI output only if CoreText is too slow
- Settings: intro on, off, or first window only. Portrait on or off. Portrait opacity

---

## 8. AI assistant (BYOK)

### Providers (v1)
- Anthropic
- OpenAI
- Google Gemini
- OpenRouter

All implement one `ProviderClient` protocol (send messages, stream tokens, list models). Keys are entered in Settings and stored only in Keychain, never in the config file or logs.

### Entry points
- **Prompt bar (⌘I):** type what you want ("find all node_modules over 500MB and delete them"). Kana returns a command and drops it at the prompt. It never runs it
- **Explain last error:** when a command exits non-zero, a small "Explain" chip appears. Clicking it sends the command, output and exit code
- **Assistant sidebar (⌘L):** a normal chat with the current pane's context attached
- **Selection → Ask:** select output, right-click, "Ask Kana"

### Context sent
- The last command, its output (truncated to a set limit) and exit code
- cwd, git branch and short status
- Shell and OS
- The selected text, if any

### Rules
- Nothing executes without me pressing enter
- Redact obvious secrets before sending: `.env` style assignments, `sk-...`, `ghp_...`, AWS keys, bearer tokens
- Show which model and provider answered, plus a rough token count
- A per-provider default model is set in Settings

---

## 9. Agent panes

### Registry
`~/.config/kana/agents.json`:
```
[
  { "name": "Claude Code", "command": "claude", "icon": "claude" },
  { "name": "Codex",       "command": "codex",  "icon": "codex" },
  { "name": "Gemini CLI",  "command": "gemini", "icon": "gemini" }
]
```
Any CLI can be added.

### Launch flow (⌘⇧A)
1. Pick an agent
2. Optional task label ("fix auth redirect")
3. Checkbox: run in a new worktree
4. Kana opens a pane, sets `KANA_PANE_ID` and `KANA_TASK` env vars, and runs the command

### Status detection
Each agent pane shows one of: **working**, **needs you**, **done**, **crashed**.
- **Best:** agent hooks. For Claude Code, a hook calls `kana notify --pane "$KANA_PANE_ID" --state needs-input` (and `done` on stop). Kana can offer to install these hooks for me
- **Fallback:** terminal bell, or no output for N seconds while the process is still alive, counts as "needs you"
- "Needs you" badges the tab, lights up the agent sidebar and fires a macOS notification when Kana isn't focused

### Agent sidebar
A list of running agents with name, task, branch, status and elapsed time. Click to jump to the pane.

---

## 10. Worktree per agent

When the checkbox is on:
1. Check that the cwd is a git repo with no rebase or merge in progress
2. `git worktree add ../<repo>-kana/<slug> -b kana/<slug>`
3. If `.kana/setup.sh` exists in the repo, run it in the new worktree (install deps, copy `.env`)
4. Start the agent there

**Finish action** (from the agent sidebar):
- Show the diff summary
- Options: open in editor, merge into the original branch, push the branch, or discard
- Discard removes the worktree and deletes the branch, but only after a confirm if there are uncommitted changes

Kana never deletes a worktree or branch on its own.

---

## 11. Config

`~/.config/kana/config` in Ghostty-style `key = value`. The Settings UI reads and writes this same file, so the file is the source of truth.

```
theme = kana-dark
font-family = JetBrains Mono
font-size = 14
cursor-style = bar
skin = akira
intro = first-window
portrait = on
suggestions = on
focus-mode-on-launch = off
assistant-provider = anthropic
assistant-max-output-lines = 200
agent-idle-seconds = 20
worktree-root = ../{repo}-kana
```

---

## 12. Default keybindings

| Shortcut | Action |
|---|---|
| ⌘T | New tab |
| ⌘D / ⌘⇧D | Split right / down |
| ⌘⌥ arrows | Move between panes |
| ⌘[ / ⌘] | Previous / next pane |
| ⌘⇧Enter | Zoom pane |
| ⌃⌘= | Equalize panes (or double-click a divider) |
| ⌘W / ⌥⌘W | Close pane / close tab |
| ⌘⇧T | Reopen closed tab (its splits and folders) |
| ⌘⇧O | Session history: reopen an earlier run's windows |
| ⌘Enter | Full screen |
| ⌘⇧K | Command palette |
| ⌘⇧H | History search |
| ⌘⇧P | Profiles |
| ⌘⇧F | Focus Mode |
| ⌘I | AI prompt bar |
| ⌘L | Assistant sidebar |
| ⌘⇧A | Launch agent |
| ⌘⇧S | Agent sidebar |
| ⌃⌥Space | Toggle suggestions |
| → | Accept suggestion |
| Global hotkey | Quick terminal |

All of these are editable in Settings.

---

## 13. Phases

Rough time assumes part-time work around school.

### Phase 0: Engine spike (1 to 2 weeks)
- [ ] Repo, `.gitignore` from section 6, this doc in `docs/`
- [ ] Xcode project, Swift package for libghostty wired in
- [ ] One window, one libghostty surface running zsh
- [ ] Typing, resize, scroll, copy/paste work
- **Done when:** nvim, htop and Claude Code run with no visual glitches

### Side quest: intro assets (any time, no app needed)
- [x] `convert.py` with terminal preview
- [ ] Find and trim the Akira slide clip
- [ ] Tune it until the slide and the stand-up both read well
- [ ] Make the original default skin for the repo

### Phase 1: Daily driver core (3 to 4 weeks)
- [ ] Tabs, splits, pane navigation and zoom
- [ ] Config file loading and keybindings
- [ ] Themes and fonts
- [ ] Window and session restore
- [ ] Quick terminal
- **Done when:** I use Kana instead of Ghostty for a full week

### Phase 2: Mew layer and skins (2 to 3 weeks)
- [ ] Header bar, Focus Mode
- [ ] Profiles
- [ ] History storage, search, inline suggestions
- [ ] Command palette
- [ ] Clickable URLs and paths
- [ ] Settings UI
- [ ] SkinManager, IntroPlayer, portrait header
- **Done when:** feature parity with Mew, and the Akira intro plays and lands on the portrait smoothly

### Phase 3: BYOK assistant (2 weeks)
- [ ] Keychain storage and provider settings
- [ ] Provider clients with streaming
- [ ] ContextCapture from shell integration
- [ ] Prompt bar, explain-error chip, sidebar, selection ask
- [ ] Secret redaction
- **Done when:** explaining a failed build and generating a command both work reliably with all four providers

### Phase 4: Agents and worktrees (2 to 3 weeks)
- [ ] Agent registry and launcher
- [ ] `kana` CLI and Unix socket
- [ ] Claude Code hook install, idle and bell fallback
- [ ] Agent sidebar and notifications
- [ ] WorktreeManager with setup script and finish flow
- **Done when:** three agents run in parallel on one repo without me losing track of any of them

### Phase 5: Personal polish (ongoing)
- [ ] Crash logging to a local file
- [ ] Optional personal Homebrew tap
- [ ] Performance pass (startup time, memory with many panes)

Don't start Phase 3 until Phase 1 is solid. Flaky input will kill the whole thing faster than missing AI features.

---

## 14. Testing

- **Unit:** SplitTree, config parser, `.kana` loader, skin resolution, secret redaction, provider response parsing
- **Integration:** ContextCapture against real zsh output, worktree create and cleanup against a temp repo
- **Manual checklist every Ghostty bump:** nvim, htop, tmux, ssh, Claude Code, emoji and CJK text, paste of large text, resize during output

---

## 15. Risks

| Risk | Mitigation |
|---|---|
| libghostty's embedder API isn't officially stable | Pin a revision, keep all calls inside `TerminalBridge`, bump on purpose |
| Building libghostty is fragile on new macOS versions | Use a prebuilt SPM package, keep a known-good xcframework around |
| Input, focus and IME edge cases eat Phase 1 | Copy Ghostty's Mac app approach instead of inventing one |
| Agent status detection is unreliable for some CLIs | Hooks where supported, bell and idle fallback everywhere else |
| Secrets leak into AI requests | Redaction plus a preview of exactly what gets sent |
| Anime clips or frames end up in the public repo | `.gitignore` in the first commit, skins live in `~/.config/kana/`, only the default skin is committed |
| Scope creep | Phases 0 to 3 are the real project. Everything else is a bonus |

---

## 16. Open questions

- CoreText or a second libghostty surface for the intro and portrait?
- Portrait size: fixed grid, or scale with the window?
- Assistant sidebar always on the right, or a floating panel?
- Should history search include agent pane output, or only shell commands?
- Per-profile default agent, model and skin?
- What the original default skin should be

---

## 17. References

- Ghostty docs and libghostty overview: https://ghostty.org/docs/about
- Ghostty source (Mac app is the reference implementation): https://github.com/ghostty-org/ghostty
- awesome-libghostty (other apps built on it): https://github.com/Uzaaft/awesome-libghostty
- Prebuilt libghostty Swift package: https://github.com/Lakr233/libghostty-spm
- Mew (layout inspiration): https://github.com/importkaizen/homebrew-mew
