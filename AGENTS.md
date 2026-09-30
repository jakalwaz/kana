# AGENTS.md

Shared rules for every coding agent working on Kana (Claude Code, Codex, anyone else). Read this before doing anything.

## The project

Kana is a native macOS terminal built on libghostty with a Mew-style layout, a BYOK AI assistant and agent panes. The full spec is `docs/KANA.md`. Read the sections relevant to your task before writing code.

## The team

| Role | Agent | Owns |
|---|---|---|
| Lead | Claude Code | Architecture, `App/`, the libghostty bridge, merging, final say on code |
| Teammate | Codex | Tasks assigned to `codex` in `TASKS.md`, and reviewing Claude's work |
| Owner | Jak | Product decisions, manual testing, anything in "Decisions needed" |

## TASKS.md is the source of truth

- Every task has an owner, a list of files, dependencies and a status
- **Only edit files listed under your own task.** No exceptions
- Need a change in someone else's files? Add it under **Requests** in `TASKS.md` and keep going with what you can do
- Code against the **Contracts** section. Don't change a contract. If one is wrong, add it to **Decisions needed**
- When you finish, set the status to `review` and write a one to three line summary of what changed and how you tested it

## How the two agents work at the same time

**Delegated mode (default).** Claude calls Codex through the `codex-cli` MCP tool with a task from `TASKS.md`. Both work in the same checkout, which is safe because their files never overlap. Codex does not commit. Claude reviews Codex's diff, runs the build and tests, then commits.

**Parallel mode (for longer Codex tasks).** Jak runs Codex in its own terminal in a worktree:

```
git worktree add ../kana-codex -b codex/<task-id>
```

Codex commits on its branch. Claude reviews the branch and merges it.

## Review loop

Every non-trivial change gets reviewed by the other agent before it's marked done.

- Label each finding: **bug** (wrong behavior or crash), **risk** (will likely break later, security, performance) or **nit** (style, naming)
- Bugs and risks get fixed. Nits are optional and never block
- **Max 2 review rounds per task.** If you still disagree after round 2, write both positions under **Decisions needed** and move on. Jak decides
- Review what changed, not the whole codebase. Don't suggest rewrites outside the task

## Code rules

- Swift 6, macOS 14+, Apple silicon only
- AppKit for windows, tabs, splits and the terminal view. SwiftUI for settings, palette and sidebars
- **Every call into `ghostty.h` lives in `App/Terminal/TerminalBridge*.swift`.** Nothing else imports the C API
- For how Ghostty does something (input, IME, resize, splits, focus), read Ghostty's Mac app source in `../ghostty/macos/Sources/` first and follow its approach. It's MIT licensed
- Don't add dependencies without writing the reason in the task summary
- Python tools use only the standard library plus what's in `tools/ascii/requirements.txt`
- Small commits, message prefixed with the area: `terminal: handle resize`, `skins: add loader`, `tools: add tests`

## Never commit

- Anything in `assets/private/`
- Video files or `.kana` files, except `Resources/skins/default/`
- API keys, tokens, `.env` files

The repo is public. The `.gitignore` covers these, but check `git status` before every commit anyway.

## Definition of done

- It builds (`script/build`) and tests pass (`script/test`) once those exist
- The other agent reviewed it (or the 2 round limit was hit and logged)
- `TASKS.md` is updated
- Anything that needs a human to check by eye or by feel (rendering, typing, scrolling) is listed for Jak as a short manual test checklist
