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

- **No prefixes of any kind.** Not `feat:`/`fix:`/`chore:`, and not area scopes
  like `web-api:` or `llm-agents:` either. The subject is a plain imperative
  sentence with no leading qualifier.
- **Descriptive body** explaining what and why, wrapped at 72. Commit bodies stay
  hard-wrapped even where PR bodies do not.
- **Never list the commit's own author as co-author.** They are already on the
  `Author:` line. Trailers crediting someone else are fine.
- **End with the model co-author trailer**, one trailer, last thing in the
  message: `Co-Authored-By: <model> <noreply@anthropic.com>`. Required, not
  optional — and dropping it is not what the no-self-co-author rule asks for.
- **No plan-document references.** Don't anchor a subject or body on `Phase N`,
  `Step N`, `PR N.N` or similar. Planning docs are ephemeral and usually
  unshared, so the numbering outlives its referent. Use descriptive language
  instead — "after the producer flip", "once the new subscription is attached".

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
