# Phase 0 kickoff prompt

Paste everything below the line into Claude Code, started from the repo root.

**Before you paste**

1. Install Codex CLI and log in
2. Connect it to Claude Code:
   ```
   claude mcp add codex-cli -- npx -y codex-mcp-server
   ```
   Then run `/mcp` in Claude Code and check that `codex-cli` shows as connected
3. Clone Ghostty next to the repo as a read-only reference:
   ```
   git clone https://github.com/ghostty-org/ghostty ../ghostty
   ```
4. Make sure Xcode and the command line tools are installed

---

We're starting Phase 0 of Kana.

Read these first, in order: `AGENTS.md`, `CLAUDE.md`, `docs/KANA.md` (sections 2 to 6, 7 for the skins contract, and 13), and `TASKS.md`.

Then run it like this:

1. **Kick off Codex first.** Tasks T0.5, T0.6, T0.7 and T0.8 are Codex's and have no dependencies or overlap with your files. Delegate them through the `codex` tool now, one at a time or together, following the delegation rules in CLAUDE.md. For T0.6, include contract C1 from TASKS.md in the message.

2. **While Codex works, do T0.1 to T0.4 yourself, in order.** For the libghostty package in T0.2, compare the prebuilt libghostty-spm options (Lakr233/libghostty-spm, sethdeckard/libghostty-spm, and any others you find), pick one, pin it, and tell me why. For T0.3 and T0.4, read how `../ghostty/macos/Sources/` handles the surface, input and resize before writing code, and name the files you based your code on.

3. **Review loop.** After each of your tasks, have Codex review your uncommitted changes. When each Codex task comes back, review its diff yourself. Max 2 rounds either way, bugs and risks only. Log disagreements in TASKS.md under Decisions needed.

4. **Keep TASKS.md current** as statuses change.

5. **Stop and check with me:**
   - After T0.1 builds, so I can confirm the empty window opens
   - After T0.3, with a manual test checklist for the terminal
   - If the libghostty package won't build or link, before trying workarounds
   - If anything needs a decision from me

**Done when:** the Phase 0 done criteria in TASKS.md are met. Finish with a short report: what's done, what Codex built, anything still open, and my manual test checklist.
