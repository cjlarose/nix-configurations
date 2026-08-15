---
name: writing-pull-request-descriptions
description: Use when opening a pull request, writing or editing a PR body, or updating one after a branch has been rewritten or new commits pushed. Also use before replying to review feedback, which follows different rules again.
---

# Writing pull request descriptions

A PR description states the **problem and the proposed solution**. It is not a
tour of the branch.

## Never hard-wrap the body

**Every paragraph is one long line.** No newline until the paragraph ends — not
at 72 characters, not at 80, not at any column.

GitHub renders the body as markdown and soft-wraps it to the reader's viewport,
so hard wraps are not a neutral formatting choice: they are line breaks the
renderer honors as authored. A body wrapped at 72 reads as a narrow ragged
column on a wide screen, and re-flows into a jagged mess on a phone. Editing one
is worse — a sentence added mid-paragraph pushes every following line out of
alignment, so a one-word change means re-wrapping the whole paragraph and a diff
that touches lines nobody edited.

Lists, tables, code blocks and quotes keep their own line structure. This rule
governs prose lines only: within a bullet or a paragraph, do not break.

This is the **opposite** of the commit-message rule, where bodies stay wrapped
at 72 because git tooling does no wrapping of its own. Do not carry the habit
across — see the asymmetry section below.

## Do not restate the commits

The reviewer reads the commits. A description that walks through them commit by
commit is length without information — summarize the intent instead, and let each
commit carry its own reasoning.

Same instinct, same fix, in three other places:

- **No evidence dumps.** State the conclusion, not the table you derived it from.
- **No past-state narration.** Drop "used to", "previously", "no longer", "now
  that". The diff is the record of what changed.
- **No testing-plan section** unless the consumer rules below ask for one.

## Referencing a commit

When a SHA is the right reference and the commit is **in the repo the PR is
against**, write the full 40-character hash, bare — no backticks, no markdown
link, and no abbreviating it yourself:

```
Reverted in 9c1f3ae4b2d80a7e6f5c14b93d2e8a0f7c6b5d43 once the offset moved.
```

GitHub shortens it to the display form and links it to the commit when it
renders the body — automatically, after the fact. Every hand-made version of
that is worse than leaving it alone. Backticks make a code span, which
suppresses the autolink and strands a 40-character hash in the prose; a written
link is a URL to keep current; a hand-abbreviated hash can go ambiguous as the
repo grows.

### A commit in another repo is the exception

**Autolinking is repo-scoped.** GitHub expands a bare hash only when the commit
lives in the repo rendering the body — the repo the PR is against. An upstream
project's SHA, or one from a sibling repo in the same fleet, matches nothing and
renders as 40 characters of raw hex that lead nowhere. Nothing is doing the work
for you there, so doing it by hand is what makes the reference resolve at all.

For a **foreign commit**, shorten to 7 characters and link it explicitly:

```
Fixed upstream in [165dca4](https://github.com/herdrdev/herdr/commit/165dca453d12a93b91b490cd58362e7dbd36c46d) and released in v0.8.0.
```

The URL still carries the full hash, so the abbreviation loses nothing and the
ambiguity objection doesn't apply — the link resolves one exact commit however
much the upstream repo grows.

The test is **which repo renders the text**, not which repo you are working in.
A cross-repo lock bump is the case that catches people out: the PR is against
this repo, so this repo's SHAs stay bare while the upstream ones it cites get
shortened and linked.

This is *how* to write a SHA, not *when*. The rule below on citing subjects
rather than SHAs while a stack is live still decides whether a SHA belongs there
at all.

## Model disclosure: included by default

**End the description with a plain sentence naming the models**, unless the
rules for this repo below say otherwise:

```
Written with Claude Opus 5 and Claude Haiku 4.5.
```

Machine-written prose says so. The default is to disclose, and silence is not a
licence to omit — a repo that wants it gone says so explicitly, and one of the
two consumers of this skill does exactly that.

**Prose, not a trailer.** Trailers are defined as the block at the end of a
*commit message*; a PR description is not one, nothing parses it there, and
`Assisted-by:` lines in a web-rendered body are syntax borrowed from a context
that gives it meaning. List the same models the commits disclose, in a sentence.

Whatever the rule here, it governs **every** form of the disclosure — a
generated-with footer, a trailer, an italic signature. They are one disclosure
in different clothing, so swapping one for another is not a way to satisfy a ban
or to dodge a requirement.

## The rules invert between artifacts — do not generalize

A commit message and a PR description are deliberately asymmetric, and each may
*require* what the other *forbids* — hard wrapping, issue keys and model
attribution are the three that bite. A **comment** posted on the user's behalf
is a third artifact with a third rule, and it is the *opposite* of the
description's: see **writing-pull-request-comments**.

Never carry a rule across artifacts by analogy. Where the rules for this repo
below speak, they are the authority.

## Say what feedback you want

End with a line naming the review you are asking for, and what is already
settled:

```
Worth a close look at the landed-detection logic. The naming rule is settled —
please don't relitigate it here.
```

"Any feedback welcome" says nothing. Naming what is closed is the half that
saves time, by keeping a settled decision from being re-opened.

## Accuracy is a separate pass

Prose errors survive code review, because a code review does not read the
description. A dedicated pass over the wording has caught wrong counts, renamed
identifiers that no longer exist, and rationales for decisions since reversed.

- **Recompute every number** you state — commits, files, tests — rather than
  carrying it forward from an earlier draft.
- **A branch rewrite invalidates the description.** After a rebase, re-split or
  force-push, re-read the body against the branch as it now stands.
- Don't claim a check passes because a pipeline exited 0; confirm what actually
  ran.

## After the PR is published

- **Never force-push.** Changes arrive as **new commits** on top.
- **One narrowly-scoped commit per review comment**, so each reply cites a
  focused SHA. Don't bundle fixes into a catch-all and don't squash.
- Cite commit **subjects** rather than SHAs while a stack is live — a SHA below a
  live base is orphaned by any merge, sync or authorized fixup.

## Common mistakes

- Writing the body from the branch's history instead of from the reader's
  question, "what problem is this solving?"
- Hard-wrapping the prose, usually by carrying the commit-message habit across.
- Leaving a stale description after rewriting the branch.
- Copying the previous PR's structure without checking whether its conventions
  are the ones that apply here.
