---
name: launch-remote-session
description: Use when the user wants to launch/open/start a NEW Claude Code session with Remote Control enabled — in a fresh neovim tab — optionally in a specific directory and/or seeded with an initial prompt. Triggers on phrasing like "start a new remote session", "launch a remote-control claude over in <dir>", "spin up a new session to work on X".
---

# launch-remote-session

Launch a **new** Claude Code session with Remote Control enabled, running in a
fresh tab of the neovim instance this session lives inside. You drive the parent
neovim over its RPC socket: open a tab, point it at the target directory, start
`claude --remote-control`, and (optionally) type an initial prompt into it.

This skill assumes you are running inside a neovim terminal buffer — i.e. `$NVIM`
is set. If it is not, see the fallback in Step 0.

## Gather the inputs

From the user's request, determine three things:

- **directory** — where the new session should run. If the user named a
  directory, resolve it to an absolute path. If not, default to this session's
  current working directory (`pwd`).
- **prompt** — an initial prompt to send, if the user gave one. Optional.
- **name** — the session name. Resolve in this order:
  1. If the user specified a name, use it.
  2. Else if there is a prompt, derive a short name from it (a few words
     capturing the task).
  3. Else (no name and no prompt), **ask the user what the session will be used
     for**, and derive the name from their answer.

  Slugify the resolved name: lowercase, replace any run of non-alphanumeric
  characters with a single hyphen, and trim leading/trailing hyphens. The slug
  must be a single token with no whitespace or quotes — it is used both as the
  Remote Control session name and the neovim buffer label.

Throughout the steps below, substitute your resolved values for `<DIR>` (absolute
path), `<NAME>` (slug), and `<PROMPT>`.

## Step 0 — find the neovim socket

Use the parent neovim's RPC socket from `$NVIM` (set in every neovim terminal
buffer and inherited by this process). Confirm it is set:

```sh
test -n "$NVIM" && echo "socket: $NVIM"
```

If `$NVIM` is empty, fall back to a single live socket:

```sh
sockets=( /run/user/"$(id -u)"/nvim.* )
# If exactly one exists, use it as the --server target; otherwise stop and tell
# the user you cannot determine which neovim to control.
```

In the commands below, `--server "$NVIM"` stands for whichever socket you
resolved.

## Step 1 — open the tab and start the session

Issue one RPC call that runs an ex-command chain in the parent neovim:

```sh
nvim --server "$NVIM" --remote-expr "execute(['tabnew', 'tcd ' . fnameescape('<DIR>'), 'CreateClaudeTerminalBuffer --remote-control <NAME>', 'RenameTerminalBuffer <NAME>', 'let g:launch_rc_jid = b:terminal_job_id'])"
```

What each step does:

- `tabnew` — new tab.
- `tcd <DIR>` — set the **tab-local** working directory. `CreateClaudeTerminalBuffer`
  opens its terminal with `termopen(..., {'cwd': getcwd()})`, so the new `claude`
  process inherits this directory. This is what makes the session start in the
  right place.
- `CreateClaudeTerminalBuffer --remote-control <NAME>` — runs
  `claude --remote-control <NAME>` in a new terminal buffer in this tab. `<NAME>`
  is a single token, so it passes through the command's `<f-args>` cleanly.
- `RenameTerminalBuffer <NAME>` — sets the buffer's `b:display_name`, so the name
  shows in the statusline and the telescope buffer picker.
- `let g:launch_rc_jid = b:terminal_job_id` — stash the terminal's job id so
  Step 2 can send the prompt to it.

The `<DIR>` and `<NAME>` values are interpolated by your shell into the
single-quoted Vimscript strings. (Paths containing a single quote would break the
quoting — extremely rare; handle manually if you hit it.)

## Step 2 — send the prompt (only if there is one)

Skip this step entirely if the user gave no prompt.

Do **not** try to inline the prompt text into a Vimscript string (escaping
arbitrary prose is fragile). Instead write it to a temp file and have neovim read
it back, sending it to the session's terminal a couple seconds later — long
enough for the claude TUI to finish starting. Use neovim's own `timer_start` for
the delay (do not `sleep` in the shell):

```sh
TMP="$(mktemp)"
printf '%s' '<PROMPT>' > "$TMP"
nvim --server "$NVIM" --remote-expr "timer_start(2500, {-> [chansend(g:launch_rc_jid, join(readfile('$TMP'), \"\n\") . \"\r\"), delete('$TMP')]})"
```

- `readfile` + `join(..., "\n")` reconstruct the exact prompt text, preserving any
  internal line breaks.
- The trailing `\r` submits the prompt in the claude TUI.
- The lambda also `delete`s the temp file after sending, so nothing is left
  behind. The `nvim` command returns immediately; the send happens inside neovim
  after the timer fires.

Write `<PROMPT>` into the temp file using single quotes as shown, or a heredoc, so
the shell does not mangle it. If the prompt itself contains a single quote, use a
heredoc to write the file instead.

## After launching

Tell the user the session is up: its name, the directory it is running in, and
that Remote Control is enabled (named `<NAME>`). The new session lives in a
separate neovim tab; the user can switch to it with normal neovim tab navigation.
