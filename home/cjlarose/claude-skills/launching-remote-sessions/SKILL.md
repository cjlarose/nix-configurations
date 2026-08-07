---
name: launching-remote-sessions
description: Use when the user wants to launch/open/start a NEW Claude Code session with Remote Control enabled — in a fresh neovim tab — optionally in a specific directory and/or seeded with an initial prompt. Triggers on phrasing like "start a new remote session", "launch a remote-control claude over in <dir>", "spin up a new session to work on X".
---

# launching-remote-sessions

Launch a **new** Claude Code session with Remote Control enabled, in a fresh tab of the neovim
instance this session lives inside, by driving the *parent* neovim over its RPC socket. This skill is
the operational recipe; the reusable mechanics and *why* live in the wiki — read
`[[Driving Neovim from a Shell over RPC]]` (directly or via `wiki:querying-notes`; `LLM_WIKI_PATH` is set
wherever this skill is deployed). Background on the feature and its flags: `[[Claude Code Remote
Control]]`; the always-on counterpart is `[[Claude remoteControlAtStartup HM Option]]`.

Assumes you are running inside a neovim terminal buffer (`$NVIM` set); if not, see the Step 0 fallback.

## Gather the inputs

- **directory** — where the new session runs. If named, resolve to an absolute path; else default to
  this session's `pwd`.
- **prompt** — an optional initial prompt to send.
- **name** — resolve in order: (1) user-specified; (2) else derive a short name from the prompt;
  (3) else ask the user what the session is for, and derive from their answer. Slugify to a single
  whitespace-free token (lowercase, runs of non-alphanumerics → one hyphen, trim hyphens) — it's both
  the Remote Control session name and the neovim buffer label, and `<f-args>` splits on whitespace.

Substitute your resolved `<DIR>` (absolute), `<NAME>` (slug), `<PROMPT>` below.

## Step 0 — find the neovim socket

```sh
test -n "$NVIM" && echo "socket: $NVIM"
```

If `$NVIM` is empty, fall back to a single live socket — `/run/user/"$(id -u)"/nvim.*`; if there
isn't exactly one, stop and tell the user you can't determine which neovim to control. In the
commands below, `--server "$NVIM"` means whichever socket you resolved. (See
`[[Driving Neovim from a Shell over RPC]]` for the socket details.)

## Step 1 — open the tab and start the session

```sh
nvim --server "$NVIM" --remote-expr "execute(['tabnew', 'tcd ' . fnameescape('<DIR>'), 'CreateClaudeTerminalBuffer --remote-control <NAME>', 'RenameTerminalBuffer <NAME>', 'let g:launch_rc_jid = b:terminal_job_id'])"
```

`tabnew` → new tab; `tcd <DIR>` sets the **tab-local** cwd so `CreateClaudeTerminalBuffer` (which
opens its terminal with `termopen(..., {'cwd': getcwd()})`) starts `claude --remote-control <NAME>`
in the right directory; `RenameTerminalBuffer <NAME>` sets the statusline/picker label; the final
`let g:launch_rc_jid = b:terminal_job_id` stashes the job id for Step 2. `<DIR>`/`<NAME>` are
shell-interpolated into the single-quoted Vimscript (a single-quote in the path breaks quoting — rare;
handle manually).

## Step 2 — send the prompt (only if there is one)

Skip entirely if no prompt. Don't inline prose into Vimscript (escaping is fragile) and don't `sleep`
in the shell (the Bash tool blocks foreground sleeps). Write the prompt to a temp file and defer the
send **inside** neovim with `timer_start`:

```sh
TMP="$(mktemp)"
printf '%s' '<PROMPT>' > "$TMP"
nvim --server "$NVIM" --remote-expr "timer_start(2500, {-> [chansend(g:launch_rc_jid, join(readfile('$TMP'), \"\n\") . \"\r\"), delete('$TMP')]})"
```

`readfile`+`join` reconstruct the exact text (preserving line breaks); the trailing `\r` submits it in
the claude TUI; the lambda deletes the temp file after sending. The `nvim` call returns immediately;
the send fires after the timer. Use a heredoc to write the temp file if the prompt contains a single
quote. (Rationale: `[[Driving Neovim from a Shell over RPC]]`.)

## After launching

Tell the user the session is up: its name, the directory, and that Remote Control is enabled (named
`<NAME>`). It lives in a separate neovim tab; switch with normal neovim tab navigation.
