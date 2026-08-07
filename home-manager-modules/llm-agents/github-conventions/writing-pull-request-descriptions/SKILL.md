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
*require* what the other *forbids* — issue keys and model attribution are the two
that bite. A **comment** posted on the user's behalf is a third artifact with a
third rule, and it is the *opposite* of the description's: see
**writing-pull-request-comments**.

Never carry a rule across artifacts by analogy. Where the rules for this repo
below speak, they are the authority.

## Say what feedback you want

End with a line naming the review you are asking for, and what is already
settled:

```
Worth a close look at the landed-detection logic. The naming rule is settled —
please don't relitigate it here.
```

Easy to leave out, because it is the one part of a PR body that is not about
the code. In a study of 80K pull requests across 156 projects, stating the
desired feedback type **predicted acceptance and reviewer engagement better
than any other element** — including the purpose and code explanations the same
study found developers *rate* as more important. Write for what moves a review,
not for what reviewers say they value.

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
- Leaving a stale description after rewriting the branch.
- Copying the previous PR's structure without checking whether its conventions
  are the ones that apply here.
