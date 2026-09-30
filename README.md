# Kana

A native macOS terminal built on libghostty, with a Mew-style layout, a bring-your-own-key AI assistant and panes for running coding agents side by side. Built for my own daily use.

Early days, but it runs:

```
script/run     # builds build/Kana.app and opens it
script/test    # KanaSkins, zsh suggestions, and the app build
```

Needs macOS 14+ on Apple silicon. Either Xcode or the Command Line Tools can build it. Tests need Xcode.

What's there now:
- libghostty terminal on pure black, with tabs in a Mew-style header (⌘T, ⌘W, ⌘1-9) and Focus Mode (⌘⇧F)
- Inline suggestions in zsh: the rest of a likely command shows in grey, and Tab, → or End accepts it (Alt-→ takes one word, Ctrl-Alt-Space toggles). They come from history, then command names, then files
- A welcome screen in the terminal itself, like Claude Code's. It's one red box: the KANA wordmark on top, then the skin's whole ASCII animation as big as the window allows. When the animation rests on its last frame, the box's bottom line slides down and the keys and features appear. It's sized so all of it and the prompt fit on one screen, and it's normal output in the scrollback. Any key skips the animation. It plays in every new tab, `kana` replays it, and `kana keys` shows just the list

Settings live in `~/.config/kana/config`: `skin`, `intro` (`on` animates every new tab, `first-window` only the first, `off` never), `banner` (`off` hides the welcome screen), `suggestions`, `font-size`, `font-family`.

## Docs

- `docs/KANA.md`: the full spec and roadmap
- `TASKS.md`: current task board
- `AGENTS.md` and `CLAUDE.md`: how the AI agents working on this repo split and review work
- `tools/ascii/README.md`: turning a clip into ASCII frames for the intro and portrait

## License

TBD. Kana builds on Ghostty's libghostty, which is MIT licensed.
