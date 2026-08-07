---
name: capturing-sessions
description: Use when the user wants to save material from the CURRENT session into one of their LLM wikis — phrases like "capture this to the wiki", "save what we figured out about X to my wiki", "dump this conversation into the wiki", "stash this in the wiki for later". Writes a self-contained markdown extract into the target wiki's capture queue, commits and pushes only that file, and stops; it does NOT ingest. Runs from any session, not only inside a wiki repo.
---

# capturing-sessions

Save material from the current session into one of the user's LLM wikis. This skill **only captures**: it writes one new file into the wiki's capture queue, commits and pushes just that file, and stops. It never edits `pages/`, `index.md` or `log.md`, and it never runs `ingesting-sources`.

Filing happens later and elsewhere, by the standing ingest agent for that wiki.

**Why capture and ingest are decoupled.** `ingesting-sources` rewrites `index.md`, `log.md` and task pages in place and is not concurrency-safe. Spawning it from every capture made it trivial to run two ingests at once. Splitting them means capture is cheap and always safe — it only ever *adds* a file — while ingest runs serially in one designated worktree.

That split is also what makes the push safe. A capture commit adds exactly one file under the queue directory; an ingest commit touches `pages/`, `index.md`, `log.md` and moves a file *out* of the queue. The two never touch the same lines, so a rejected push is resolved by `git pull --rebase` with no possible conflict.

## Setup contract

The wiki registry at `${XDG_CONFIG_HOME:-$HOME/.config}/llm-wiki/wikis.json` lists every installed wiki. It is written by home-manager; do not edit it.

```json
{ "version": 1,
  "wikis": {
    "personal": { "id": "personal", "repoPath": "...", "ingestPath": null,
                  "routingHint": "...", "queueDir": "raw/inbox", "indexBudgetBytes": 24576 }
  } }
```

`LLM_WIKI_PATH` is a **compatibility export only**, set when exactly one wiki is installed. Never rely on it: with two wikis it is deliberately unset, and a skill that fell back to it would file work material into the personal wiki. Resolve the target through the registry.

## Choosing the wiki — get this right or stop

**The single most damaging failure this skill has is writing to the wrong wiki**, because the capture is committed and pushed: work material in a personal wiki is a leak, and the fix is a history rewrite.

1. If the user named a wiki (`capture this to work`, `/capturing-sessions personal`), use it.
2. Otherwise match the material against each wiki's `routingHint`. Take it only when **one** wiki plausibly fits.
3. If two fit, neither fits, or you are weighing it up — **ask, and wait.** This is the one question in this skill worth interrupting for. Everything else it decides on its own.

Exactly one wiki installed and the material fits it? Proceed without asking.

## Hard constraints

- **Resolve the wiki from the registry.** Missing or unparseable registry, or an id not in it: abort with a setup hint. Never guess a path.
- **One capture per invocation.** Several discrete topics means several runs.
- **Only ever add one file.** Never modify or delete anything else in the wiki, and never `git add -A`.
- **Never run `ingesting-sources`,** not even when the queue is long and the standing agent looks idle. Ingest belongs to the standing worktree; running it from here defeats the serialization.
- **Dates are America/Los_Angeles**, `TZ='America/Los_Angeles' date +%Y-%m-%d`.
- **Never include raw secret values.** Treat the capture as public-facing even where the repo is private — it is committed and pushed. Scan the drafted body for anything credential-shaped: passwords, API keys, tokens, private keys, CHAP secrets, OAuth client secrets, signed URLs, session cookies, VPN auth values. For each:
  - **If the user keeps it in 1Password**, replace the literal with a retrieval command: `$(op read --account <account> "op://<vault>/<item>/<field>")`. Never guess an `op://` path.
  - **Otherwise** use a placeholder naming what was redacted and where the real value lives: `<REDACTED — see /persistence/secrets/foo.env on host>`.
  - Preserve surrounding shell syntax so examples stay runnable: `-v BS8WLd…` becomes `-v $(op read …)`, not `-v <REDACTED>` which breaks the command.
  - Apply this even to "low-value" homelab secrets. Redaction is cheap; an exposed credential plus a history rewrite is not.
  - **Catch credentials embedded in larger benign-looking strings.** Redact JWTs and bearer tokens themselves (any `eyJ…`, even mid-string), token-bearing QR / deep-link / device-join payloads (redact the embedded credential, keep the surrounding text), and production IPs / internal hostnames. A bulk capture once leaked a live HS256 JWT inside a `~|~`-delimited device-join payload because the wrapper looked harmless.
  - **Explicitly NOT secrets — keep them:** repo and service names, commit SHAs, issue keys, cloud project ids.

## Workflow

### 1. Resolve the target wiki

```bash
REG="${XDG_CONFIG_HOME:-$HOME/.config}/llm-wiki/wikis.json"
test -f "$REG" || { echo "no wiki registry; is programs.llmAgents.wiki enabled?"; exit 1; }
jq -r '.wikis | keys[]' "$REG"                      # what is installed
jq -r '.wikis | to_entries[] | "\(.key): \(.value.routingHint)"' "$REG"   # routing hints
```

Then, for the chosen `$ID`:

```bash
REPO=$(jq -r --arg i "$ID" '.wikis[$i].repoPath' "$REG")
QUEUE=$(jq -r --arg i "$ID" '.wikis[$i].queueDir' "$REG")
```

### 2. Get a writable worktree

`$REPO` is the canonical checkout under `~/repos` and is **read-only** — the same rule as every other repo there. Captures are written in a linked worktree in the current workspace, exactly like any other change.

If this session's workspace has no worktree of the wiki yet, add one with the **`adding-a-repo-to-a-workspace`** skill. Do not improvise `git worktree add`; that skill owns the naming rule, including the owner-prefix case when a workspace holds repos from several owners.

Work in that worktree, on the workspace's branch. Call it `$WT`.

**If there is no workspace to add it to** — the session is not running under `~/workspaces/<task>/` — fall back to the spool: write the capture to `${XDG_STATE_HOME:-$HOME/.local/state}/llm-wiki/<id>/spool/` instead, and skip steps 4 and 5. The standing agent drains the spool alongside the queue. Say plainly in step 6 that the capture is spooled and not yet in git.

### 3. Write the capture

Filename `$WT/$QUEUE/<YYYY-MM-DD>-<topic-slug>.md`, kebab-case slug under ~50 chars. If that name already exists, append `-2`, `-3`: two captures on one day about one topic is a collision, not a re-capture.

```markdown
---
captured: <today's LA date>
source: claude-code-session
host: <whoami>@<hostname>   # where the session ran, not the subject
project: <basename of cwd, or omit>
topic: <one line of prose>
---

# <Descriptive title>

<Self-contained synthesis of the material.>
```

The body **must stand alone**. Whoever ingests it will not have this conversation. Spell out anything referred to as "the file we just looked at" or "the issue we discussed": real paths, commit SHAs, URLs, commands, error text.

Do the final secret scan now, before the file is written. Once it is pushed, removing a secret means rewriting history.

### 4. Commit just that file

```bash
git -C "$WT" add "$QUEUE/<filename>"
git -C "$WT" commit -m "Capture <topic>"
```

Stage the path explicitly. The workspace may hold unrelated work in that same worktree, and `git add -A` would sweep it into a commit that is about to be pushed to `main`.

### 5. Push to main

The queue lives on `main` so the standing agent finds it without hunting for branches. Capture commits are additive, so this fast-forwards or rebases cleanly:

```bash
git -C "$WT" push origin HEAD:main || {
  git -C "$WT" fetch origin main
  git -C "$WT" rebase origin/main
  git -C "$WT" push origin HEAD:main
}
```

If it still fails — no network, no credentials, a hook rejection — **stop and report**. The commit is safe locally; do not retry blindly and do not force. Tell the user it is committed but unpushed, and name the worktree.

### 6. Wake the standing agent, best effort

If `herdr` is available, find or start the standing space for this wiki and send it a prompt to drain the queue. Use the **`herdr`** skill for the current syntax.

This is an optimization, not a requirement. **A herdr failure never fails the capture** — the capture is already pushed, and the session-start hook reports the backlog to every session on the machine, so the work surfaces even if the standing agent is dead. Report honestly whether the wake landed.

### 7. Report

1. Which wiki, and why that one if the material could have gone either way.
2. Where it landed: the queue path and the pushed commit (or that it is spooled/unpushed).
3. Whether the standing agent was woken.
4. **Only if there is something to flag:** assumptions you made — the slug or scope you chose for a vague instruction, anything deliberately left out, secrets redacted with a placeholder that could become an `op read` reference if the user supplies the path. Nothing to flag, no section.

## Examples of when this skill fires

- "capture what we figured out about the Caddy reverse proxy"
- "save this to my work wiki under topic payroll-exports"
- "stash this conversation in the wiki for later"

## Examples of when this skill does NOT fire

- "ingest the queue" / "file the backlog" → `ingesting-sources`, in the standing worktree
- "what does my wiki say about X" → `querying-notes`
- "hand this off" → `handing-off`, which writes a handoff doc and fires a capture itself
- "remember this for next time" → not a wiki request
