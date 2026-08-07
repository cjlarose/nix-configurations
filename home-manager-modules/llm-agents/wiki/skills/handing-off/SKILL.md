---
name: handing-off
description: Use at the end of a long session to hand off to another agent — phrases like "hand off", "write a handoff", "compact this for a fresh session", "I'm running low on context, hand this off". Captures the session into the LLM wiki via capturing-sessions (with handoff guidance), then spawns ingesting-sources synchronously so durable knowledge becomes pages and each in-flight piece of work becomes/refreshes a type/task page with a "## Next steps" section — then reports the touched task pages for the next agent to querying-notes.
---

# handing-off

Hand a long-running session off to a fresh agent by **promoting its context into the wiki**, not into
a throwaway doc. This skill **orchestrates the capture→ingest cycle**: it runs `capturing-sessions` to write
a handoff-shaped extract, then spawns `ingesting-sources` itself (synchronously, in a subagent) to file it,
then relays the result. There is no separate handoff file — the "handoff doc" is the `type/task`
page(s) the ingest creates or updates, each carrying a `## Next steps` section the next agent picks up
from.

`capturing-sessions` is **capture-only** and does not ingest on its own; the synchronous ingest is *this
skill's* job, because a handoff is only useful if the task pages exist immediately for the next agent
to `querying-notes`.

This skill is **wiki-coupled**: it requires `LLM_WIKI_PATH`. If `LLM_WIKI_PATH` is unset, say the wiki
isn't wired up here and fall back to a plain in-chat handoff summary.

## Why capture first

At a handoff the session is long and the context is rich — exactly what's about to be lost to
compaction or a fresh start. Capturing **now, while context is full** is the point: durable learnings
become wiki pages, and the where-I-left-off state lands on the relevant `type/task` page(s) as
`## Next steps`, queryable by whoever picks up.

## What to do

1. **Invoke `capturing-sessions`, directing it to write a handoff-shaped extract.** A handoff capture is a
   normal capture *plus* two additions — instruct `capturing-sessions` to include both (it has no handoff
   mode of its own, so you must spell these out):
   - the **durable knowledge** from this session (decisions+rationale, gotchas, how-things-work,
     contracts, perf/security learnings, open questions) — as any capture would; **and**
   - a **`## Handoff guidance` section** plus a **`handoff: true` frontmatter marker**. The marker is
     the deterministic signal `ingesting-sources` keys on to build `type/task` pages. The section holds **one
     subsection per distinct in-flight piece of work**, each self-contained (the ingest subagent sees
     only the capture file, not this conversation — spell out paths/SHAs/exact next actions):
     - **Work** — a short title, and its stable **`slug:`** if it already has one (so ingest
       matches/links the existing `type/task`); omit the slug for new ad-hoc work (ingest creates a
       task and assigns one).
     - **Mission** — what this work is trying to achieve.
     - **Current state** — what's done and *verified* vs. assumed.
     - **Next steps** — the concrete pick-up-here actions, in order.
     - **Repos / branches / commits** in play, and any **open threads / blockers**.

   The durable-knowledge body is still written as usual (the guidance is *additional*). The capture's
   secret scan applies to the handoff guidance too. `capturing-sessions` writes the file and stops — it does
   **not** ingest or commit.

2. **Spawn `ingesting-sources` synchronously on the capture file.** Once `capturing-sessions` reports the written
   path, spawn a **subagent** to run `ingesting-sources` on `$LLM_WIKI_PATH/raw/sessions/<filename>` (the
   real absolute path). The subagent gets a clean context — it sees only the raw file, not this
   session — which keeps its synthesis grounded in the captured artifact. Prompt it along these lines:

   > Invoke the `ingesting-sources` skill on `$LLM_WIKI_PATH/raw/sessions/<filename>`. Run it to completion:
   > it is autonomous, resolves the wiki via `$LLM_WIKI_PATH`, and commits its own work. The capture
   > file is currently untracked, so its commit step stages it alongside the pages/index/log in one
   > commit. This is a handoff capture (`handoff: true`) — create-or-update a `type/task` page per
   > `## Handoff guidance` item with a refreshed `## Next steps`. Return your full step-10 report
   > verbatim — pages created/updated, the task pages touched, the commit SHA, and any contradictions
   > or judgment calls — as your final message.

   `ingesting-sources` is reachable as a user-scoped skill and inherits `LLM_WIKI_PATH` from the environment.
   Because ingest keys on the `handoff: true` frontmatter (not on who spawned it), it builds the task
   pages whether spawned here, run by hand, or picked up later in a backlog sweep.

   **Failure safeguard.** If the subagent reports that ingest failed (locked git index, merge conflict,
   a secret it refused to commit, etc.), the capture must not be left as a lost untracked file. Commit
   the raw extract on its own so it's preserved for a later manual ingest:

   ```bash
   git -C "$LLM_WIKI_PATH" add raw/sessions/<filename>
   git -C "$LLM_WIKI_PATH" commit -m "Capture <topic> (ingest deferred)"
   ```

   End that commit message with the standard `Co-Authored-By` trailer, then tell the user ingest failed
   and why, and that they can retry from any session with `ingest raw/sessions/<filename>`.

3. **Relay the `ingesting-sources` subagent's report**, then add a **"Next session"** pointer: list **every**
   `type/task` page the ingest touched (as `[[links]]`) and tell the next agent to **`querying-notes` each
   one and read its `## Next steps`** before starting. Also surface the durable pages worth reading.

4. **End with the `ingesting-sources` subagent's review banner verbatim** — dead last, nothing after it (the
   `⚠️ REVIEW NEEDED …` block, or its `✓ No review items flagged.` line). If ingest failed and produced
   no banner, the failure notice from step 2 is the last thing instead.

## Known limitation — concurrent ingests

`ingesting-sources` edits `index.md`/`log.md` (and task pages) in place and is **not concurrency-safe**: two
ingests at once race (a check-then-write hazard). Since `handing-off` ingests, don't invoke it while
another ingest is in flight against the same wiki — a bulk backfill, a manual `ingest`, or another
`handing-off`. (A plain `capturing-sessions` is safe to run alongside — it only writes one new file and no longer
ingests.) If you suspect an ingest is running (recent uncommitted page writes in the wiki worktree),
wait for it to finish first.

## Examples of when this skill fires

- "hand this off to a fresh session"
- "write a handoff, I'm running low on context"
- "compact this for another agent to pick up"
- "let's wrap up and hand off the remaining work"

## Examples of when this skill does NOT fire

- "capture this to the wiki" (no handoff intended) → `capturing-sessions` directly
- "what does the wiki say about X" → `querying-notes`
- a brand-new short session with nothing durable and no continuation → just answer; a handoff is overkill
