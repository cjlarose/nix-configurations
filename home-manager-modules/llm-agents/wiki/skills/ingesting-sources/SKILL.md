---
name: ingesting-sources
description: Use when the user wants to ingest a source from raw/ into the LLM wiki — phrases like "ingest raw/articles/foo.md", "process this new article", "file this", "add this to the wiki". Also runs as a subagent spawned by the handing-off skill. Synthesizes the source into a summary page, updates 5-15 related entity/concept pages, refreshes index.md, and appends log.md.
---

# ingesting-sources

Ingest one source from `raw/` into the wiki. End state: a summary page exists in `pages/`, related entity/concept pages have been created or updated, `index.md` reflects every new page, and `log.md` has a new entry describing what changed.

This skill is **location-independent**: it operates on the wiki at `$LLM_WIKI_PATH` regardless of the current working directory. It works the same whether invoked directly from a session inside the wiki repo or spawned as a subagent from an unrelated project (e.g., by the `handing-off` skill).

## Setup contract

This skill requires the `LLM_WIKI_PATH` environment variable to point at the user's LLM wiki repository. The user wires this up via home-manager.

Verify before doing anything else:

```bash
test -n "$LLM_WIKI_PATH" \
  && test -d "$LLM_WIKI_PATH/.git" \
  && test -d "$LLM_WIKI_PATH/pages"
```

If any check fails, tell the user `LLM_WIKI_PATH` must be set to their LLM wiki git repository and that they should add the export to their home-manager config. Then abort — do not write anything.

**All paths below are resolved against `$LLM_WIKI_PATH`.** Never assume the current working directory is the wiki root. Use `git -C "$LLM_WIKI_PATH"` for every git operation and `$LLM_WIKI_PATH/<...>` for every Read/Write/Edit.

## Inputs

One of:
- A path to a file in `raw/` — either absolute, or relative to the wiki root (e.g., `raw/articles/2026-05-30-foo.md`, `raw/sessions/2026-06-25-bar.md`).
- A URL. Fetch its content, save to `$LLM_WIKI_PATH/raw/articles/YYYY-MM-DD-<kebab-slug>.md`, then proceed with that path.

Resolve the source to both an absolute path (for reading/writing) and a wiki-relative path (for frontmatter `sources:` and `git add`):

```bash
case "$SRC" in
  /*) ABS="$SRC" ;;
  *)  ABS="$LLM_WIKI_PATH/$SRC" ;;
esac
REL="${ABS#"$LLM_WIKI_PATH"/}"   # wiki-relative, e.g. raw/sessions/2026-06-25-bar.md
```

Frontmatter `sources:` and `log.md` entries always use the **wiki-relative** path (`$REL`), never the absolute one.

## Hard constraints

- **Run autonomously — do not pause for confirmation.** Rely on your own assessment of what the source says and which pages to create or update. Make the changes, commit them, and report what you did afterward. Never stop mid-workflow to ask "anything to add/correct/emphasize before I proceed?" The only things that stop the workflow before it completes are genuine blockers: a missing/invalid wiki repo (`LLM_WIKI_PATH` unset or not a wiki), a locked git index, or an unredactable secret. Surface judgment calls, assumptions, and contradictions in the final report (step 10), not before.
- **Flag review items with a literal `⚠️ REVIEW:` marker.** A *review item* is anything the user may need to act on or override: a contradiction with an existing page (surface it — never silently resolve, per hard rule 5 in `CLAUDE.md`), an unresolved open question, a material judgment call that shaped what you wrote (e.g. touching far fewer pages than the usual 5-15, or picking one reading of an ambiguous source), or a change to an existing page's framing or claims. Routine created/updated/cross-linked work is **not** a review item. Review items appear in exactly two places and must match (parity): one `- ⚠️ REVIEW: …` bullet per item in `log.md` (step 8), and the same items in the end-of-report banner (step 10). If nothing qualifies, emit no markers — and say so via the calm no-items line in step 10. The whole point: the user runs this flow unattended, so a flag must survive in the durable log *and* be the last jarring thing they see in the session output.
- **One source per invocation.** If asked to ingest a batch, do them one at a time — run the full workflow (including the commit) end to end for each source before moving to the next. Do not pause for user review between sources.
- **Evolve the wiki's skills when warranted (self-improvement).** You may — and when the source clearly calls for it, should — **add, modify, or remove** the wiki's user-scoped skills under `$LLM_WIKI_PATH/skills/<name>/SKILL.md`:
  - **Add** a skill when the source describes a repeatable *executable* procedure worth running on demand. Author it thin: frontmatter (`name`, `description`) + a body that keeps the operational steps/commands and references the wiki pages you wrote for the criteria/reference (the pattern the wiki-coupled skills `transcoding-media` / `rebuilding-nixos` use).
  - **Modify** an existing skill — e.g. slim it to cite a page you just created, or correct it against the source.
  - **Remove** a skill the source renders obsolete or superseded.
  Operate on `skills/` **only** — the user-scoped skills the home-manager module deploys — never `.claude/skills/` (project-scoped, e.g. `linting-the-wiki`). The module auto-discovers `skills/*/SKILL.md`, so writing or deleting a `skills/<name>/SKILL.md` is sufficient: **never edit nix.**
  **Skill changes are not live.** Deployed skills are store copies from the pinned flake rev (unlike pages, which are live via the worktree), so a skill change is committed but inert until the user bumps the flake input and runs HM activation. Therefore emit one `🛠️ SKILL-CHANGE:` bullet in `log.md` per change (step 8) — format `🛠️ SKILL-CHANGE: <add|modify|remove> <name> — needs redeploy (flake bump + HM activation)` — and surface the set in the step-10 report so the user knows a redeploy is pending and can review the diff first.
  **Guardrail — your own tooling.** Managing a *domain* skill (`transcoding-media`, `rebuilding-nixos`, or a new one) is routine. Modifying or removing the wiki's own maintenance skills (`capturing-sessions`, `querying-notes`, `ingesting-sources`) is high-stakes — a bad edit breaks this very pipeline — so additionally emit a `⚠️ REVIEW:` flag when you touch one.
  When you spot a candidate but aren't confident enough to author it, fall back to flagging only: add a `🔧 SKILL-CANDIDATE:` bullet to `log.md` (parallel to `⚠️ REVIEW:`) so the shortlist stays greppable. Candidates are non-blocking — log only, not the report banner.
- **Track work items with `type/task` and `type/epic` pages.** Create a `type/task` page for each substantial piece of work the source represents — whether **completed** this session (`status/done`), **in flight** (`status/in-progress`/`status/blocked`), or **named as future work** (`status/not-started`) — with exactly one `status/*` tag, an optional stable `slug:`, and an `epic:` link if it belongs to a larger effort. The task page is the work item; a separate summary page still captures the *knowledge*. Don't manufacture tasks for trivial one-off edits. When a task already has a page, **match it by `slug:` first, then by title**, and update its `status/*` (→ `status/in-progress`, `status/blocked`, `status/done`, or `status/cancelled`) and bump `updated:` in place rather than duplicating it. Cluster related tasks under a `type/epic` page when the work is large — the epic lists its tasks via `[[wikilinks]]`, and tasks link back via `epic:`. Assign a `slug:` (kebab-case, `^[a-z0-9]+(-[a-z0-9]+)*$`, unique across pages) when you create a work item so later sessions have a stable matcher; omit it only for throwaway tasks.
- **Handoff captures carry continuation onto `type/task` pages.** When the source's frontmatter has `handoff: true`, it is a handoff capture (written for a handoff — the `handing-off` skill directs `capturing-sessions` to include this) with a `## Handoff guidance` section holding one subsection per in-flight piece of work. The `type/task` page **is** the handoff doc — there is no separate handoff page type. For **each** item: **match** an existing task by its `slug:`, else by title, else **create** one (assigning a fresh unique `slug:` on creation). Set/refresh a **`## Next steps`** section from the item's next steps (ordered, concrete), refresh the current-state summary, set `status/in-progress` (or `status/blocked`), and bump `updated:`. A `type/task` carries `## Next steps` **only while open** — if an item reports the work finished, set `status/done` and drop the `## Next steps` section instead of leaving a stale one. The durable knowledge in the same capture still fans out to its own concept/entity/decision/etc. pages as usual — the task page is the work item + handoff, not the knowledge store. List every task page you touched in the step-10 report so the `handing-off` skill can point the next agent at them.
- **Never modify, rename, or delete files in `raw/`.**
- **Every page in `pages/` must have valid frontmatter** — exactly one `domain/*` tag, exactly one `type/*` tag, and (for `type/task`/`type/epic` pages) exactly one `status/*` tag. Include the `epic:` field on task pages that belong to a parent epic.
- **End the workflow with a `log.md` append.** No exceptions.
- **Dates are America/Los_Angeles.** Derive today with `TZ='America/Los_Angeles' date +%Y-%m-%d`. Use that date in any filename prefix (URL fetches into `raw/articles/`), frontmatter `created`/`updated`/`clipped` fields, and log entry prefix.

## Workflow

### 1. Read the source

Read the full source file at `$ABS`. If it has frontmatter (e.g., from Obsidian Web Clipper with title/URL/date, or a `capturing-sessions` extract with `captured`/`topic`), treat that as ground truth.

### 2. Check for prior ingestion

```bash
grep -l "$(basename "$ABS")" "$LLM_WIKI_PATH"/pages/*.md 2>/dev/null
```

If any page already lists this source in its `sources:` frontmatter, this is a re-ingestion. Don't ask — proceed by **integrating in place**: update the existing pages rather than duplicating them, and never delete prior content wholesale. Note in the final report (step 10) that this source had already been ingested and which pages you re-touched.

### 3. Assess the source

Form your own 3-5 key takeaways of what this source says and what's worth preserving. This is your working assessment — do not present it for approval or wait for a response. Carry it straight into the summary page and the related-pages plan below.

### 4. Draft the summary page

Create `$LLM_WIKI_PATH/pages/<Title>.md` where `<Title>` is `Title Case With Spaces` derived from the source. Frontmatter:

```yaml
---
tags: [domain/<software|finance>, type/summary, <topic-tags>]
created: <today's date, YYYY-MM-DD>
updated: <today's date, YYYY-MM-DD>
sources:
  - <$REL — the wiki-relative source path>
---
```

Body: condensed takeaways + key facts worth preserving + any directly-quoted material with citations.

### 5. Identify related pages

Read `$LLM_WIKI_PATH/index.md`. Identify 5-15 pages this source touches:

- **Existing entities/concepts** to enrich with new information.
- **New entities/concepts** worth a dedicated page.
- **New comparisons or syntheses** worth drafting if material warrants.
- **`type/task` or `type/epic` pages** if the source mentions future/in-flight/completed work (see the work-item hard constraint above for `status/*`, `slug:`, and `epic:` rules).

Decide the plan yourself — group it mentally under `Update:` and `Create:` and proceed directly to applying it. Do not present it for approval or wait. You'll list what you actually created and updated in the final report (step 10).

### 6. Apply updates

For each item in your plan (all under `$LLM_WIKI_PATH/pages/`):

- **Existing page:** read it, integrate new information, add cross-references via `[[wikilinks]]`, bump `updated:` to today, append `$REL` to `sources:` if not already listed.
- **New page:** create with valid frontmatter (one `domain/*`, one `type/*`, topic tags — plus exactly one `status/*` and an optional `slug:`/`epic:` on `type/task`/`type/epic` work items), body synthesized from the source, cross-references to related pages via `[[wikilinks]]`.

A `[[wikilink]]` to a not-yet-existing page is fine — leave it; lint will surface it later.

### 7. Update `index.md`

In `$LLM_WIKI_PATH/index.md`, for every new page add an entry under the right `## <Domain>` / `### <Topic>` heading with a one-line summary. Create new topic groups if needed; keep them alphabetized within a domain.

### 8. Append `log.md`

Append a new entry at the bottom of `$LLM_WIKI_PATH/log.md`:

```markdown
## [YYYY-MM-DD] ingest | "<source title>" (<$REL>)
- Created [[<New Page>]] (<type>)
- Updated [[<Existing Page>]]
- Cross-linked from [[<Other Page>]]
- Notable: <optional plain-text color or surprises that do NOT need user action>
- ⚠️ REVIEW: <one bullet per review item the user should act on or override — omit these entirely if there are none>
- 🔧 SKILL-CANDIDATE: <one bullet per repeatable process worth turning into a Claude skill — omit if none>
- 🛠️ SKILL-CHANGE: <add|modify|remove> <name> — needs redeploy (flake bump + HM activation) — one bullet per skill you added/modified/removed; omit if none
```

Use the literal prefix `⚠️ REVIEW:` (with the warning sign) so the user's standing review queue is just `grep '⚠️ REVIEW:' "$LLM_WIKI_PATH/log.md"`. Add one such bullet per review item, as defined in the hard constraints, or none at all. Keep non-actionable color in a plain `- Notable:` bullet — never under `⚠️ REVIEW:`, or you dilute the marker. The `🛠️ SKILL-CHANGE:` prefix is likewise greppable (`grep '🛠️ SKILL-CHANGE:' "$LLM_WIKI_PATH/log.md"`) — the standing queue of skill changes awaiting a redeploy; `🔧 SKILL-CANDIDATE:` is the parallel shortlist of skills worth authoring later.

### 9. Commit

Commit the work without asking. Stage **only** the files this ingest touched — never `git add -A`, since the working tree may hold unrelated changes:

- the new/updated pages under `pages/`
- `index.md`
- `log.md`
- the associated raw source: if you fetched a URL into `raw/articles/` this run, include that file (`$REL`); if the source was an already-tracked `raw/` file, there's nothing new to stage for it. **If the source is an untracked file (e.g., a `capturing-sessions` extract that has not been committed yet), include `$REL` so the capture and its ingest land in one commit.**

```bash
git -C "$LLM_WIKI_PATH" add \
  pages/<...touched pages...> index.md log.md <$REL if untracked or newly fetched>
```

Then commit with an imperative subject naming the ingested source, e.g.:

```
Ingest <source title>
```

End the commit message with the trailer:

```
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```

Commit directly to the current branch (this repo's convention is to commit ingests straight to `main`). If `git commit` fails (e.g., locked index, pre-commit hook rejection), stop and report the failure rather than retrying blindly.

### 10. Report

Summarize for the user: pages created, pages updated, the commit SHA, whether this was a re-ingestion, and any optional follow-up sources worth ingesting.

If you added/modified/removed any skills, state it plainly and prominently — list each `🛠️ SKILL-CHANGE` and say a **redeploy (flake bump + HM activation) is required to activate them**, since deployed skills are store copies, not live. This is the user's signal to bump the wiki flake input and run HM activation (and review the committed skill diff first).

When this skill was spawned as a subagent (e.g., by the `handing-off` skill), this report is your return value — the parent relays it to the originating session, so keep it explicit and self-contained.

**End the report with the review banner, and put it dead last — nothing may come after it.** This is the part the user is most likely to actually see (a leading banner can scroll off the top), so it must be the final thing in your output. The banner restates exactly the `⚠️ REVIEW:` items you wrote to `log.md` in step 8 — same items, same count (parity).

If there are one or more review items:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  REVIEW NEEDED — <N> item(s) (also in log.md):
   1. <item>
   2. <item>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If there are none, end with exactly this calm line instead — no banner, and still nothing after it:

```
✓ No review items flagged.
```

## Examples of when this skill fires

- "ingest raw/articles/2026-05-30-pg-tuning.md"
- "file this article: https://example.com/foo"
- "add raw/notes/2026-05-29-asset-allocation.md to the wiki"
- "process the new article I just clipped"
- spawned by the `handing-off` skill to ingest a freshly-written `raw/sessions/` handoff extract

## Examples of when this skill does NOT fire

- "what does the wiki say about Postgres?" → querying-notes
- "lint the wiki" → linting-the-wiki (Milestone 3)
- "capture this conversation" → capturing-sessions (capture-only; ingest later in a fresh session, or use `handing-off` which ingests for you)
