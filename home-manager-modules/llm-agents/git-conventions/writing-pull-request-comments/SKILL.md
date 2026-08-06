---
name: writing-pull-request-comments
description: Use when posting any GitHub comment on the user's behalf — a PR review comment, a reply to review feedback, an issue comment — including replies posted automatically by a review loop.
---

# Writing pull request comments

A comment posted on the user's behalf is machine-authored prose appearing under
a human's name. It says so, every time.

## Sign every comment

Append, as the last line:

```
*Generated-By: Claude Opus 5*
```

- Use the **actual** running model name, not the example above.
- **No email address** — this is not the commit trailer.
- One signature, at the bottom, on comments posted on the user's behalf.

## This is the opposite of the PR description rule

Three artifacts, three rules. The instinct that a comment inherits its PR's
convention is wrong — a description and a comment on that same description take
opposite treatment:

| Artifact | Model attribution |
|---|---|
| Commit message | **Required** — `Co-Authored-By: <model> <noreply@anthropic.com>` |
| PR description | Per repo — see **writing-pull-request-descriptions** |
| GitHub comment | **Required** — visible `*Generated-By: <model>*`, no email |

The email is the tell for which one you are writing: the trailer carries one, the
signature never does.

## Replying to review feedback

- Cite a **focused SHA** — the one commit that addresses that comment — rather
  than a range or a catch-all. This is why the fix discipline is one narrowly
  scoped commit per review comment.
- While a stack is live, cite commit **subjects** instead of SHAs. A SHA below a
  live base is orphaned by any merge, `stack sync --prune`, or authorized fixup
  force-push; replies citing them have been left pointing at nothing.
- Answer the comment that was written. If you disagree, say so with the reason
  rather than implementing something you believe is wrong.

## Automated loops need a dedup marker too

A review loop usually posts as the **same GitHub identity** as the human
reviewer, so it cannot tell its own replies apart by author — and will answer
itself forever. Append an invisible marker alongside the visible signature:

```
<!-- cc-auto-reply -->
```

Skip any comment carrying **either** marker. The visible signature does the
disclosure; the HTML comment survives editing that might reword the signature.

## Common mistakes

- Dropping the signature because the PR description bans attribution. Different
  artifact, opposite rule.
- Using the `Co-Authored-By` form, with its email, on a comment.
- Citing a SHA on a stacked PR that later gets rebased out from under the reply.
