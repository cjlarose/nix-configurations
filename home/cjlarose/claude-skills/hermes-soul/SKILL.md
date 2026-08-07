---
name: hermes-soul
description: Read, edit, and apply the hermes agent's SOUL.md identity file. Use when asked to read/show/view Hermes's SOUL.md, update Hermes's persona/identity/tone, or rename/rewrite the Hermes agent personality.
---

# hermes-soul

Read the current SOUL.md, optionally revise it based on user instruction, write the
result back, and restart the hermes-agent service. Reference: [[Hermes Soul Md]].

**SOUL.md path:** `/var/lib/hermes/.hermes/SOUL.md` on the hermes guest (`10.0.0.5`).
**Do not use `write_file`** — it forces mode 0600 and makes the file unreadable by
group members ([[Agent Sandbox Writable Paths]]). Use `tee` instead.
**Always ask** before restarting the service ([[Ask Before Restarting a Microvm]]).

## Step 1: read current SOUL.md

```bash
ssh cjlarose@10.0.0.5 "cat /var/lib/hermes/.hermes/SOUL.md"
```

Display the contents to the user. If they only asked to read (e.g. `--show`), stop
here.

## Step 2: draft the revision

Based on the user's instruction, draft the revised SOUL.md content. Keep the result
**200–400 words** — longer causes slower, more confused behavior (20,000-char hard cap
exists, but brevity wins). Show the user the diff or the full proposed text and ask
for approval before writing.

Content guidance (from [[Hermes Soul Md]]):

| Belongs in SOUL.md | Lives elsewhere |
|---|---|
| Tone, style, verbosity | User facts → `USER.md` |
| Values, hard behavioral rules | Env facts → `MEMORY.md` |
| Uncertainty / disagreement handling | Project conventions → `AGENTS.md` |
| | Repeatable workflows → `skills/` |
| | One-session mode change → `/personality` |

## Step 3: write the revised SOUL.md

```bash
ssh cjlarose@10.0.0.5 "tee /var/lib/hermes/.hermes/SOUL.md > /dev/null" << 'ENDSOUL'
<revised content>
ENDSOUL
```

## Step 4: restart the agent (after confirmation)

Ask the user for confirmation before restarting. SOUL.md is read at session start, so
a restart is required for the change to take effect.

```bash
ssh cjlarose@10.0.0.5 "sudo systemctl restart hermes-agent.service"
```

Verify the restart was clean:

```bash
ssh cjlarose@10.0.0.5 "sudo systemctl status hermes-agent.service --no-pager -l"
```

The Discord bot reconnects automatically within a few seconds.
