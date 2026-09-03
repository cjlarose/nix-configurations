---
name: writing-commit-messages
description: Use when writing any git commit message, amending one, rewording a branch's history, or squashing — and before the first commit on a branch rather than after, since existing history is not evidence of the convention.
---

# Writing commit messages

Anchored to Chris Beams' seven rules, plus house conventions that override the
habits picked up elsewhere.

## The seven rules

1. Separate subject from body with a blank line
2. Limit the subject to **50 characters**
3. Capitalize the subject
4. No period at the end of the subject
5. **Imperative mood** in the subject
6. Wrap the body at **72 characters**
7. Use the body to explain *what* and *why*, not *how*

Imperative test: the subject completes "If applied, this commit will ___".

## House conventions

- **The 50-character subject is a soft target; 72 is the hard limit.** Per Beams,
  "shoot for 50 characters, but consider 72 the hard limit" — anything under 72
  is acceptable when 50 cannot hold the subject without sacrificing clarity. Only
  a subject over 72 characters is a violation.
- **No prefixes of any kind.** Not `feat:`/`fix:`/`chore:`, and not area scopes
  like `web-api:` or `llm-agents:` either. The subject is a plain imperative
  sentence with no leading qualifier.
- **Descriptive body** explaining what and why, wrapped at 72. Commit bodies stay
  hard-wrapped even where PR bodies do not.
- **Never list the commit's own author as co-author.** They are already on the
  `Author:` line. Trailers crediting someone else are fine.
- **Disclose every model, one `Assisted-by:` trailer per model**, in the trailer
  block at the end. Required, not optional.
- **No plan-document references.** Don't anchor a subject or body on `Phase N`,
  `Step N`, `PR N.N` or similar. Planning docs are ephemeral and usually
  unshared, so the numbering outlives its referent. Use descriptive language
  instead — "after the producer flip", "once the new subscription is attached".

## Referencing another commit

**In this repo:** write the full 40-character SHA, bare — no backticks, no
markdown link, and no abbreviating it yourself:

```
Reverts 9c1f3ae4b2d80a7e6f5c14b93d2e8a0f7c6b5d43, which assumed the
producer still owned the offset.
```

GitHub shortens the hash to its display form and links it to the commit when it
renders the message. That happens on its own, after the fact — so every hand-made
version of it is worse than doing nothing. Backticks make it a code span, which
suppresses the autolink and leaves a 40-character hash sitting raw in the prose.
A hand-written link is a URL to maintain, and a hand-abbreviated hash is the one
form that can go ambiguous later as the repo grows.

The full hash is also what makes the reference resolvable outside GitHub, where
nothing is expanding anything: `git show <sha>` works from the message text as
written.

### A commit in another repo is the exception

**Autolinking is repo-scoped.** GitHub expands a bare hash only when the commit
is in the repo rendering the text. A SHA from anywhere else — an upstream
project, a sibling repo in the same fleet — matches nothing, so it renders as 40
characters of raw hex that lead nowhere. There nothing is doing the work for
you, and doing it yourself is the only way the reference resolves at all.

So for a **foreign commit**, shorten to 7 characters and link it explicitly:

```
Picks up the upstream fix in
[165dca4](https://github.com/herdrdev/herdr/commit/165dca453d12a93b91b490cd58362e7dbd36c46d).
```

The URL carries the full hash, so nothing is lost to the abbreviation and the
ambiguity objection doesn't apply — the link resolves one exact commit no matter
how the upstream repo grows.

The test is **which repo will render this text**, not which repo you are sitting
in. A commit message written here and read on GitHub renders in this repo, so
this repo's own commits stay bare.

## Disclosing the models

One trailer per model, repeated:

```
Assisted-by: Claude Opus 5
Assisted-by: Claude Haiku 4.5
```

- **List every model that materially contributed** to *this commit*, not every
  model that ran during the session. A subagent on a different model that wrote
  or reviewed part of the change earns a line; one that searched and found
  nothing used does not.
- One line each, deduplicated. A single model is a list of one — that is the
  normal case, not a reason to drop the trailer.
- Use the display name (`Claude Opus 5`), and **no email address**.

This is a **commit-message** convention. Do not carry the trailer form into a PR
description — see **writing-pull-request-descriptions**.

## Check the convention before the first commit, not after

The rule most often broken, and the reason this is a gate: **agents mimic recent
history**. A branch whose existing commits carry `llm-agents:` prefixes will
produce another one, and prefixed commits are therefore self-perpetuating — a
clean log is what keeps it clean. Recent history on the branch is not evidence
of what the convention is. Read this first, then write.

## House style is repo-scoped

These rules govern the user's own repos. Work intended to be **upstreamed to a
third-party repo follows that repo's style** — conventional-commits prefixes
included, if that is what upstream uses. Not a contradiction: different repo,
different convention.

## Rewording history

`git rebase -i` is unavailable in a non-interactive shell. Reword a branch with
`git filter-branch --msg-filter`, keying the `case` on the **message text**, not
on `$GIT_COMMIT` — text survives the SHA churn a prior rebase introduced, while
hard-coded hashes go stale. Verify it was message-only by comparing
`rev-parse HEAD^{tree}` before and after; an identical tree proves no drift.

When the change is large, rebuild the branch from the base instead — it lets the
work be re-split along better lines rather than inheriting the old boundaries.

## Amending a pushed commit has downstream costs

Rewording a pushed commit changes its SHA even though the tree is identical. If
another repo pins that commit as a flake input, the amend orphans the pinned rev
and forces a lock re-bump plus a downstream commit. Get the message right before
the first push when a downstream flake tracks the branch.
