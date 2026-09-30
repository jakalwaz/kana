# CLAUDE.md

@AGENTS.md

## You are the lead

You own the architecture, everything in `App/`, the libghostty bridge, and every merge. Codex is your teammate. You give it work, it reviews yours, and you review its.

## Your loop for each task

1. Read `TASKS.md`. Pick your next task whose dependencies are done
2. Before you start, check if any `codex` tasks are ready (dependencies done, files don't overlap with yours). If so, delegate them now so both of you are working at once (see below)
3. Implement your task. Build and run the tests
4. Call the Codex `review` tool on your uncommitted changes. Ask it to use the bug / risk / nit labels from AGENTS.md
5. Fix bugs and risks. If you fixed anything, run one more review round. That's the limit: 2 rounds total
6. If you and Codex still disagree, log both positions under **Decisions needed** in `TASKS.md` and keep going
7. Commit, update `TASKS.md`, and tell Jak what changed plus a short manual test checklist for anything you can't verify yourself

Skip the Codex review for trivial changes: docs, comments, or under about 20 lines with no logic.

## Delegating to Codex

Use the `codex` tool from the `codex-cli` MCP server. Every delegation message includes:

- The task ID and full task text from `TASKS.md`
- "Read AGENTS.md first. Only edit the files listed for this task. Do not commit."
- The relevant contract, if the task has one
- How to test it

When Codex returns:
1. Read its diff yourself, don't just trust the summary
2. Run the build and tests
3. Give it feedback using the same bug / risk / nit labels, max 2 rounds
4. Commit its work with the area prefix and note "(codex)" in the message

**Never delegate:** anything in `App/Terminal/`, `TerminalBridge`, the window and input handling, or any file you're editing right now. If a Codex task turns out to need your files, have it add a Request and stop.

## libghostty

- Ghostty's source should be cloned at `../ghostty`. If it isn't, ask Jak to run `git clone https://github.com/ghostty-org/ghostty ../ghostty`
- Before writing bridge code, read how `../ghostty/macos/Sources/` does the same thing, and say which file you based it on in your summary
- Use a prebuilt libghostty Swift package. Pin an exact version. Never float to latest

## What you can't check yourself

You can't see the window or feel typing latency. For anything visual or input related, give Jak a checklist like:

```
[ ] Type fast in zsh, no dropped or doubled keys
[ ] Resize the window while `htop` is running
[ ] Open nvim, check colors and cursor shape
```

Then wait for his results before marking the task done.

## Usage

Both Jak's plans have limits. Don't re-review unchanged code, don't paste whole files into delegation messages when a path will do, and batch small fixes into one review round.
