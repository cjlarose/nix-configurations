# Neovim Integration

When you're running inside a neovim terminal session (the `$NVIM` environment variable is set to a socket path), and you want the user to run a shell command themselves — for example an interactive login, a long-running rebuild they should kick off, or any command you're deferring to them — populate neovim's `"c` register with the exact command so they can paste it quickly.

## How to write the register

Use the parent neovim's RPC socket via `$NVIM`:

```sh
nvim --server "$NVIM" --remote-expr 'setreg("c", "<the command>")'
```

Escape double quotes and backslashes inside the command string as needed for the Vim expression.

## Telling the user

After writing the register, mention briefly that the command is in register `"c` and can be pasted with `"cp` in normal mode (or `<C-r>c` in insert/command-line mode). Don't also paste the full command inline in your message if it's long — the register is the point.

## When not to do this

- When `$NVIM` is unset (you're not inside a neovim terminal).
- For commands you're going to run yourself via the Bash tool — only use the register for commands the user will execute.
- Don't clobber the register with throwaway commands; reserve it for the specific command you're asking the user to run.
