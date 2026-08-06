---
name: writing-pull-request-descriptions
description: Use when opening a pull request, writing or editing a PR body, or updating one after a branch has been rewritten or new commits pushed. Also use before replying to review feedback, which follows different rules again.
---

# Writing pull request descriptions

A PR description states the **problem and the proposed solution**. It is not a
tour of the branch.

## Do not restate the commits

The reviewer reads the commits. A description that walks through them commit by
commit is length without information — summarize the intent instead, and let each
commit carry its own reasoning.

Same instinct, same fix, in three other places:

- **No evidence dumps.** State the conclusion, not the table you derived it from.
- **No past-state narration.** Drop "used to", "previously", "no longer", "now
  that". The diff is the record of what changed.
- **No testing-plan section** unless the consumer rules below ask for one.

## The rules invert between artifacts — do not generalize

A commit message and a PR description are deliberately asymmetric, and each may
*require* what the other *forbids* — issue keys and model attribution are the two
that bite. A third artifact, a review comment posted on the user's behalf, takes
its own rule again, often the opposite of the PR's.

So: never carry a rule across artifacts by analogy. The per-repo rules appended
below are the authority; where they say nothing, follow the harness.

One trap worth naming: the `Co-Authored-By` trailer and the "🤖 Generated with
Claude Code" footer are **the same disclosure in different clothing**. Wherever
one is banned or required, so is the other — substituting one for the other is
not a fix.

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
- Leaving a stale description after rewriting the branch.
- Copying the previous PR's structure without checking whether its conventions
  are the ones that apply here.
