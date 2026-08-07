---
name: ingesting-sources
description: Use when the user wants to file queued captures or a specific raw source into an LLM wiki — phrases like "ingest the queue", "drain the backlog", "file this", "process raw/articles/foo.md", "ingest the uningested captures". Synthesizes each source into a summary page, updates related pages, refreshes index.md, appends log.md, and fast-forwards the canonical checkout. Runs only in the wiki's designated ingest worktree.
---

# ingesting-sources

File sources into an LLM wiki: one summary page, related pages created or updated, `index.md` refreshed, `log.md` appended, all committed and pushed.

Usually invoked with no argument to **drain the capture queue** — the captures other sessions have pushed since the last run.

## Where this runs, and why it matters

This skill runs **only in the wiki's designated ingest worktree** (`ingestPath` in the registry). That is the serialization mechanism, not a preference.

Ingest rewrites `index.md`, `log.md` and task pages in place. Two ingests at once corrupt all three. Confining it to one worktree makes "one agent per worktree" the lock — no lockfile to leak, no coordination protocol. The canonical checkout under `~/repos` is read-only like every other repo there, and a linked worktree cannot check out `main` anyway, since the main worktree holds it.

```bash
REG="${XDG_CONFIG_HOME:-$HOME/.config}/llm-wiki/wikis.json"
INGEST=$(jq -r --arg i "$ID" '.wikis[$i].ingestPath' "$REG")
[ "$INGEST" != "null" ] || { echo "wiki '$ID' has no ingestPath; no standing agent on this host"; exit 1; }
[ "$(cd "$INGEST" && pwd -P)" = "$(pwd -P)" ] || { echo "run this in $INGEST"; exit 1; }
```

If you are not there, **stop and say so.** Do not `cd` into it and continue: another agent may already be working there, and that is precisely what the guard exists to prevent.

## Setup contract

Resolve everything from the registry — `repoPath`, `ingestPath`, `queueDir`. `LLM_WIKI_PATH` is a compatibility export that only exists when a single wiki is installed; do not depend on it.

**The wiki's own `CLAUDE.md` is the schema authority.** Read it before writing anything. The two wikis genuinely differ — different domain tags, different page types, `repo/*` and `service/*` on one, `slug:` versus `jira:` and `airtable-*` for work-item identity — and this skill deliberately does not hardcode either. Whatever `CLAUDE.md` says about frontmatter, taxonomy and required sections wins over any example here.

## Hard constraints

- **Run autonomously.** Make the changes, commit, report afterwards. Never stop mid-workflow to ask "anything to add before I proceed?" Only genuine blockers stop you: wrong worktree, unreadable registry, locked git index, a secret you cannot redact.
- **One source per commit, sources one at a time.** Draining a queue of six means six full cycles, each ending in its own commit. Never batch them: a failure halfway through a batch leaves the wiki in a state no one can reason about.
- **Never modify, rename or delete anything under `raw/` other than moving a queued capture out of the queue directory** (below).
- **Flag review items with a literal `⚠️ REVIEW:` marker.** A review item is something the user may need to act on or override: a contradiction with an existing page (surface it, never resolve it silently), an unresolved open question, a material judgment call, a change to an existing page's framing. Routine created/updated work is not one. They appear in exactly two places and must match: one bullet each in `log.md`, and the same list in the closing banner.
- **Dates are America/Los_Angeles**, `TZ='America/Los_Angeles' date +%Y-%m-%d`.
- **Do not author, modify or delete skills.** Skills live in the `llm-agents` home-manager module now, not in the wiki, and they are deployed as read-only store copies. If a source suggests a skill is wrong or missing, record it as a `🔧 SKILL-CANDIDATE:` bullet in `log.md` and say so in the report. That is the whole of your involvement.

## Workflow

### 1. Build the work list

With no argument, drain the queue — and the spool, which holds captures written by sessions that had no workspace to make a worktree in:

```bash
git -C . pull --rebase                       # other sessions have been pushing captures
ls "$QUEUE"/*.md 2>/dev/null                 # the queue, in the worktree
ls "${XDG_STATE_HOME:-$HOME/.local/state}/llm-wiki/$ID/spool"/*.md 2>/dev/null
```

Process oldest first. With an explicit path or URL argument, that is the whole list; fetch a URL into `raw/articles/YYYY-MM-DD-<slug>.md` first.

Then, for each source, run steps 2-7 to completion before starting the next.

### 2. Read the source and check for prior ingestion

Read it in full; treat its frontmatter as ground truth. Then:

```bash
grep -l "$(basename "$SRC")" pages/*.md 2>/dev/null
```

A hit means re-ingestion: integrate in place, updating existing pages rather than duplicating them, and never delete prior content wholesale. Note it in the report.

### 3. Decide what it touches

Form your own three to five takeaways. Read `index.md` and identify the pages this affects — typically 5-15: existing entities and concepts to enrich, new ones worth a page, comparisons or syntheses the material warrants, and work items.

Do not present the plan for approval. Carry it straight into the edits and report what you actually did.

### 4. Write the pages

A `type/summary` page for the source, plus the related pages. Frontmatter per the wiki's `CLAUDE.md`. `sources:` always uses the **final** wiki-relative path — `raw/sessions/<file>.md`, where step 6 moves it, not the queue path it came from.

**Work items.** Create or update a `type/task` page for each substantial piece of work the source represents, matched by the wiki's own durable identifier (`slug:`, `jira:` — `CLAUDE.md` says which) and then by title. Update `status/*` in place rather than duplicating the page; a long-running task stays one page across many ingests.

**Task pages do not carry `## Next steps`.** Live next-steps belong to the handoff document, which `handing-off` writes outside the wiki and keeps current without waiting for an ingest. A `## Next steps` section here would be stale the moment it mattered — it is written by whoever last ingested, not by whoever last worked. Record what the work *is*, its status, and the decisions taken; drop any `## Next steps` you find on a page you touch.

### 5. Refresh `index.md`

Add an entry for every new non-work-log page under the right domain and topic heading, one line each. This file is also what the session-start hook injects, under a byte budget — so a bloated entry costs every session on the machine, not just this one.

### 6. Move the capture out of the queue

For a queued capture, in the same commit as the pages:

```bash
git mv "$QUEUE/<file>.md" "raw/sessions/<file>.md"
```

This *is* the "ingested" marker. Presence in the queue means not yet filed; nothing else records it, so the move and the pages must land together or the file is either ingested twice or lost. For a spooled capture, write it to `raw/sessions/` and delete the spool copy only after the commit succeeds.

### 7. Append `log.md`, commit, push, fast-forward

```markdown
## [YYYY-MM-DD] ingest | "<source title>" (raw/sessions/<file>.md)
- Created [[<New Page>]] (<type>)
- Updated [[<Existing Page>]]
- Notable: <colour that needs no action>
- ⚠️ REVIEW: <one per item needing the user's attention; omit if none>
- 🔧 SKILL-CANDIDATE: <one per repeatable process worth a skill; omit if none>
```

Stage only what this ingest touched — never `git add -A`. Commit with an imperative subject naming the source, then:

```bash
git push origin HEAD:main || { git pull --rebase && git push origin HEAD:main; }
git -C "$REPO" merge --ff-only "$(git rev-parse HEAD)"
```

**The fast-forward of `$REPO` is required, not tidy-up.** The canonical checkout is what the session-start hook reads `index.md` from and what `querying-notes` searches. Skip it and every session on the machine reads a wiki missing everything you just filed. It is a sanctioned write to `~/repos` — the same one `tearing-down-a-workspace` performs when work lands — and it is `--ff-only`, so it refuses rather than inventing a merge if that checkout has diverged. If it refuses, say so; do not force it.

### 8. Report

Per source: pages created and updated, the commit, whether it was a re-ingestion. Then, once at the end, the review banner — **last, with nothing after it**, because a leading banner scrolls off the top of an unattended run:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  REVIEW NEEDED — <N> item(s) (also in log.md):
   1. <item>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

With none, end with exactly `✓ No review items flagged.` and nothing after it.

## Examples of when this skill fires

- "ingest the queue" / "drain the backlog"
- "ingest raw/articles/2026-05-30-pg-tuning.md"
- "file this article: https://example.com/foo"

## Examples of when this skill does NOT fire

- "capture this conversation" → `capturing-sessions`
- "what does the wiki say about Postgres?" → `querying-notes`
- "hand this off" → `handing-off`
