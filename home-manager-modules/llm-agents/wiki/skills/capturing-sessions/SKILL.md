---
name: capturing-sessions
description: Use when the user wants to save material from the CURRENT Claude Code session into their LLM wiki — phrases like "capture this to the wiki", "save what we figured out about X to my wiki", "dump this conversation into the wiki", "stash this in the wiki for later". Writes a self-contained markdown extract to the wiki's raw/sessions/ directory and suggests ingesting it later; it does NOT ingest. Runs from any session, not only inside the wiki repo.
---

# capturing-sessions

Save material from the current Claude Code session into the LLM wiki's `raw/sessions/` directory. This skill **only captures** — it writes the raw extract and stops; it does **not** file the material into pages. Filing happens later, separately, via `ingesting-sources` (run by you in a fresh session, or by the `handing-off` skill, which orchestrates capture→ingest itself).

**Why ingest is deferred, not automatic.** `ingesting-sources` edits `index.md`/`log.md`/task pages in place and is not concurrency-safe, so running it implicitly on every capture made it easy to race two ingests at once. Decoupling puts you in control of *when* ingest runs — capture freely now (it touches only one new file), then ingest the backlog deliberately, one at a time. Capture runs from any project directory, not just inside the wiki repo.

## Setup contract

This skill requires the `LLM_WIKI_PATH` environment variable to point at the user's LLM wiki repository. The user wires this up via home-manager (or however they manage their shell environment).

## Hard constraints

- **`LLM_WIKI_PATH` must be set and point at a valid LLM wiki.** If not, abort with a clear setup hint pointing the user at their home-manager config. Do NOT guess a path.
- **Dates are America/Los_Angeles.** Derive today's date with `TZ='America/Los_Angeles' date +%Y-%m-%d`. Use that date in the filename prefix and in the frontmatter `captured` field.
- **`capturing-sessions` only writes one file under `raw/sessions/`.** It never edits `pages/`, `index.md`, or `log.md`, and it never spawns `ingesting-sources`. Those are `ingesting-sources`'s job, run separately later. Capture also does **not** commit the file — it leaves the new `raw/sessions/` extract untracked (a later `ingesting-sources` stages it in the same commit as the pages it produces; uncommitted captures are also the lightweight signal for "not yet ingested").
- **One capture per invocation.** If the user wants to capture several discrete topics, run the skill multiple times.
- **Never include raw secret values.** Treat `raw/sessions/` as a public-facing file even when the repo isn't currently public — it's committed and may be pushed to a remote. Before writing, scan the drafted body for anything that looks like a credential: passwords, API keys, tokens, private keys, CHAP secrets, OAuth client secrets, signed URLs, session cookies, OpenVPN auth env values, etc. For each one:
  - **If the user has the secret in 1Password**, replace the raw value with a `op read` command that retrieves it. Format: `$(op read --account <account> "op://<vault>/<item>/<field>")`. If you know the account name and `op://` path, use it. If you don't, **do not ask before capturing** — fall back to the placeholder redaction below and note in your post-capture report (step 5) that the secret was redacted with a placeholder and could be swapped for an `op read` reference if the user provides the path. Never guess an `op://` path. (Example: `$(op read --account my "op://Private/TrueNAS iSCSI CHAP ns1010301 user/password")`.)
  - **Otherwise**, replace the value with a clear placeholder that describes what was redacted and, if relevant, where the real value lives on disk (e.g., `<REDACTED — see /persistence/secrets/foo.env on host>`). Plain `<REDACTED>` is acceptable when there's nowhere obvious to point.
  - Preserve surrounding shell syntax so command examples remain re-runnable: `-v BS8WLd...` becomes `-v $(op read --account my "op://...")`, not `-v <REDACTED>` which would break the command.
  - Apply this even for "low-value" homelab secrets. The cost of redaction is small; the cost of an exposed credential plus a history rewrite is large.
  - **Catch credentials embedded inside larger benign-looking strings.** A "redact secrets" scan misses a secret when it's *inside* another value. Explicitly redact: **JWTs and bearer/access tokens themselves** (any `eyJ…` value, even mid-string); **token-bearing QR / deep-link / device-join payloads** (redact the embedded credential even when you keep the surrounding payload text); and **production IPs / internal hostnames**. (A bulk capture once leaked a live HS256 JWT embedded in a `~|~`-delimited device-join payload because the surrounding string looked benign.)
  - **Explicitly NOT secrets — keep them** (don't over-redact useful context): repo/service names, commit SHAs, Jira/issue keys, and cloud **project ids**.

## Inputs

A free-text user instruction about what to capture and under what topic. Examples of the kinds of requests this skill handles:

- "capture what we figured out about the Caddy reverse proxy issue"
- "save this conversation as a note on Postgres tuning gotchas"
- "dump our asset allocation discussion to the wiki under topic personal-finance"

**Do not ask the user to confirm scope or topic before writing.** This skill is autonomous: infer the best scope and topic from the conversation, capture immediately, and surface any assumptions or caveats *after* the write (see step 5). Even when the instruction is vague ("save this"), pick the most reasonable scope and topic slug, write the capture, and note what you assumed afterward — the user can correct it and you can re-run. The only thing that ever stops a capture before it's written is the hard abort in the constraints above (missing `LLM_WIKI_PATH`).

> **Handoffs:** when ending a session for a fresh agent to pick up, you normally invoke the `handing-off`
> skill, not `capturing-sessions` directly. `handing-off` drives a capture that *additionally* carries a
> `## Handoff guidance` section + `handoff: true` frontmatter, then spawns `ingesting-sources` synchronously
> so the in-flight work lands on `type/task` pages right away. That guidance format and the
> ingest-spawn live in the `handing-off` skill — `capturing-sessions` itself has no special handoff mode.

## Workflow

### 1. Verify the setup contract

Check that `LLM_WIKI_PATH` is set and points at a valid wiki:

```bash
test -n "$LLM_WIKI_PATH" \
  && test -d "$LLM_WIKI_PATH/.git" \
  && test -d "$LLM_WIKI_PATH/raw/sessions"
```

If any check fails, tell the user:

> `LLM_WIKI_PATH` must be set to your LLM wiki git repository (e.g., `~/worktrees/cjlarose/llm-wiki/default`). Add the export to your home-manager config. Once it's set, retry.

Then abort — do not write anything.

### 2. Decide scope and topic yourself — do not ask

Determine what to capture and under what topic from the conversation and the user's instruction. Choose a short kebab-case topic slug (lowercase, hyphens, under ~50 chars). **Do not pause for confirmation and do not wait for a response** — proceed straight to writing. Keep a short mental list of any assumptions you made (scope boundaries, topic slug choice, anything you left out or guessed at) so you can report them in step 5 after the capture exists.

### 3. Derive the filename and host

```bash
TODAY=$(TZ='America/Los_Angeles' date +%Y-%m-%d)
# FILENAME format: ${TODAY}-<topic-slug>.md
HOST="$(whoami)@$(hostname)"
```

### 4. Write the capture

Write `$LLM_WIKI_PATH/raw/sessions/<filename>` with this structure:

```markdown
---
captured: <today's LA date, YYYY-MM-DD>
source: claude-code-session
host: <whoami>@<hostname>  # the machine where this session ran, not the subject of the discussion
project: <basename of current working directory, OR omit if not useful>
topic: <user-confirmed short prose, one line>
---

# <Descriptive title>

<Self-contained synthesis of the material the user wanted captured.>

<Include enough context that a future ingesting-sources run can make sense
of this file alone, without access to the original conversation.
If material references "the file we just looked at" or "the issue we
discussed", spell those out explicitly: file paths, commit SHAs, URLs,
commands, error messages.>
```

The body **must be self-contained**. The ingesting-sources workflow that processes this file later will not have the original session's conversation.

**Before writing, do a final secret scan.** Read through the drafted body and apply the "Never include raw secret values" constraint above to every credential-shaped string. This is the last point of intervention; once the file is committed, removing a leaked secret requires a history rewrite.

### 5. Report — where it landed, how to ingest, and caveats

The capture now exists on disk, untracked and not yet filed into pages. Do **not** spawn `ingesting-sources` and do **not** commit. Tell the user what happened, **in this order**:

1. Where the capture landed: `$LLM_WIKI_PATH/raw/sessions/<filename>`.
2. **How to file it into pages:** it is not ingested yet. To file it, run `ingest raw/sessions/<filename>` in a fresh session (ingest edits pages in place and is best run one at a time). To clear the whole backlog of not-yet-ingested captures at once, a fresh session can find them by cross-referencing `log.md` (every ingest entry cites its source path) against `raw/sessions/`:

   ```bash
   comm -23 \
     <(cd "$LLM_WIKI_PATH" && ls raw/sessions/*.md | sort) \
     <(grep -oE 'raw/sessions/[^)]+\.md' "$LLM_WIKI_PATH/log.md" | sort -u)
   ```

   then ingest each listed file one at a time.
3. **Only if there's anything worth flagging**, a short "Notes" section for capture-side caveats. Include things like:
   - The topic slug or scope you chose, especially if the instruction was vague.
   - Anything you deliberately left out, summarized aggressively, or were unsure belonged.
   - Secrets you redacted with a placeholder that could become an `op read` reference if the user supplies the `op://` path.

   If you made no meaningful assumptions and there's nothing to flag, omit the Notes section entirely — don't manufacture caveats. (Caveats about the *source material* — contradictions, ambiguities — are surfaced later by `ingesting-sources` when the file is filed, not by capture.)

## Examples of when this skill fires

- "capture what we figured out about Caddy reverse proxy to the wiki"
- "save this to my wiki under topic homelab-backups"
- "stash this conversation in the wiki for later"
- "add what we just discussed about asset allocation to the wiki"

## Examples of when this skill does NOT fire

- "ingest raw/articles/foo.md" → ingesting-sources directly (that's an existing raw/ file, not the current session)
- "what does my wiki say about X" → querying-notes
- "remember this for next time" → not a wiki request; might be a memory request
- "save this file" → ambiguous; ask first whether they mean the wiki
