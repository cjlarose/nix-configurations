---
name: querying-notes
description: Use when looking something up in the user's LLM wiki — both on explicit request ("what does my wiki say about X", "check my wiki for Y", "look up Z in my wiki", "does the wiki cover ...") AND proactively, before reading files, running commands, or answering, whenever a question plausibly matches a page in the injected wiki index even with no explicit wiki reference. Reads index.md and relevant pages and synthesizes an answer with explicit citations. Strictly read-only — never writes to the wiki.
---

# querying-notes

Answer a question by reading the user's LLM wikis. Read-only by design: no edits, no log appends, no side effects on the wiki.

## Setup contract

Resolve wikis from the registry at `${XDG_CONFIG_HOME:-$HOME/.config}/llm-wiki/wikis.json`, which lists every installed wiki with its `repoPath` and a `routingHint` describing what belongs in it. `LLM_WIKI_PATH` is a compatibility export that exists only when a single wiki is installed — do not depend on it.

**Search every wiki whose `routingHint` plausibly covers the question**, not just the first. Unlike capture, a query is read-only: the cost of looking in the wrong wiki is a wasted read, while the cost of *not* looking is answering "the wiki has nothing on this" when the other one has a page. Where several have something, say which said what — and if they disagree, surface the disagreement rather than picking a winner.

```bash
REG="${XDG_CONFIG_HOME:-$HOME/.config}/llm-wiki/wikis.json"
jq -r '.wikis | to_entries[] | "\(.key)\t\(.value.repoPath)\t\(.value.routingHint)"' "$REG"
```

## Hard constraints

- **The registry must exist and name at least one wiki.** If not, abort with a setup hint; do NOT guess a path.
- **The catalog injected at session start is truncated.** Each wiki's index is cut to a byte budget, and the injection says so where it happens. Absence from the injected catalog is *not* evidence a page does not exist — read the full `index.md` from `repoPath` before concluding the wiki is silent on a topic.
- **Strictly read-only.** Never use Write, Edit, or any tool that mutates the wiki. No `log.md` append. No new pages. Filing answers back as wiki pages happens later via `ingesting-sources`, inside the wiki, at the user's discretion.
- **Don't follow wikilinks into `raw/`.** That's the immutable source layer. Stay in `pages/` and the navigation files (`index.md`).
- **Don't bluff.** If the wiki appears to have nothing on the topic, say so directly and stop. Do not fall back to your training knowledge unless the user explicitly redirects.

## Workflow

### 1. Resolve which wikis to search

Read the registry, and pick every wiki whose `routingHint` plausibly covers the question. For each chosen `$ID`:

```bash
REPO=$(jq -r --arg i "$ID" '.wikis[$i].repoPath' "$REG")
test -d "$REPO/pages" && test -f "$REPO/index.md"
```

If the registry is missing or names no wiki, tell the user their LLM wiki integration is not configured (`cjlarose.llmAgents.wiki` in home-manager) and abort. Do not guess a path.

### 2. Survey each wiki

Read `$REPO/index.md` — the curated catalog, organized `domain → topic group → page`, one line each. Use it to pick candidates.

Read it from disk even when a catalog was injected at session start: that injection is **budget-truncated**, so it is a sample rather than the catalog.

### 3. Pick candidate pages

From the index entries, identify 1-5 pages most likely to contain material relevant to the user's question. If the question is broad ("what does my wiki say about Postgres?"), include all pages in the relevant topic group. If narrow ("does my wiki cover wal_level?"), pick the 1-2 most specific.

If the index doesn't show an obvious match for the user's query term, also check page `aliases:` — a page may have been filed under a canonical title that differs from the user's phrasing (e.g., a query for ".gitkeep" resolves to `Empty Directory Placeholder Pattern.md`, whose frontmatter aliases `.gitkeep`). Grep the `aliases:` blocks under `$REPO/pages/` when the index alone is inconclusive.

### 4. Read the candidates

Read each candidate page in full. Pages contain frontmatter (`tags`, `sources`, `created`, `updated`, `aliases`) and a body with `[[wikilinks]]` to other pages. If a page references another page that is directly relevant to the question, read that too — but cap at one extra hop unless the user's question explicitly demands deeper traversal.

### 5. Synthesize the answer

Compose an answer that:

- **Directly addresses the user's question.** Don't pad with summaries of the entire page.
- **Cites pages by title with path:** `[[Page Title]] (pages/Page Title.md)`. Cite every nontrivial claim.
- **Quotes sparingly.** Paraphrase with citation; quote only when the original wording matters.
- **Surfaces contradictions explicitly.** If two pages disagree, say so and quote each. Do not silently resolve them.
- **Flags gaps.** If the wiki only partially covers the question, say what's missing and propose what to ingest next.

### 6. If the wiki has nothing on the topic

Be direct:

> Your wiki has nothing on `<topic>`. The closest pages are: `[[X]]`, `[[Y]]`. Want me to suggest sources to ingest next?

Do not invent answers from your own training data when the user explicitly asked the wiki. If they want a general-knowledge answer instead, they can ask again without invoking the wiki.

## Examples of when this skill fires

- "what does my wiki say about Postgres tuning?"
- "check my wiki for anything on tax-loss harvesting"
- "look up Caddy in my wiki"
- "does the wiki cover SSH key management?"

## Examples of when this skill does NOT fire

- "capture this to the wiki" → capturing-sessions
- "ingest this article" → ingesting-sources (only in the standing ingest worktree)
- "what's the best way to tune Postgres?" → if the injected wiki index shows a page on Postgres (tuning, config, etc.), query it first, then answer; only fall through to training knowledge if the index clearly has nothing relevant
- "explain CAP theorem" → if a relevant page exists in the index, query it first; otherwise answer from training knowledge
