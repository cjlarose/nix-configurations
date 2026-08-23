---
name: soliciting-pr-feedback
description: Use when you are about to open a GitHub pull request, or about to push new commits to an already-open PR, and want the user to review the exact change first — its title, body, commits, and per-file diff — as a GitHub-styled page before it becomes public. Triggers on "let me review the PR before opening it", "show me the PR first", "mock PR", "review before pushing".
---

# Soliciting PR feedback

## Overview

Before a pull request goes public — opened, or pushed to with new commits — show the human the *exact* change as a GitHub-styled page in lavish and act on their annotations. They review the real title, body, commits, and diff, not a prose summary, and nothing leaves the machine until they approve.

**Core rule: never hand-write the HTML.** Building the page by hand is where the bugs live (broken diff loading, wrong file lists, drift). `mock-pr-html` produces it deterministically from git + your title and body. Use it.

## When to use

- You finished a change on a branch and are about to `gh pr create` — review it first.
- You are about to push follow-up commits to an already-open PR — pass `--pr-number N`.
- The user says "show me the PR", "mock PR", "let me review before you open/push it".

Not for: changes already pushed and being reviewed on GitHub itself.

## Workflow

1. **Commit** your work locally (the page renders committed history, not the worktree).
2. **Write the PR body** to a markdown file, following `writing-pull-request-descriptions`. Put it OUTSIDE the repo (a temp path), so it can't be swept into the PR. Title: the PR subject from that same skill, not just the first commit.
3. **Generate** the page:
   ```
   mock-pr-html --title "<subject>" --body-file /tmp/body.md \
     --base origin/main --head HEAD --out .lavish/mock-pr.html
   ```
   Range is `origin/main..HEAD` (what the PR would contain). Add `--pr-number N` when soliciting feedback on commits headed for open PR #N. `--repo`/`--branch` auto-derive from git. `mock-pr-html --help` for all flags.
4. **Open** in lavish (a bare invocation opens; see the `lavish` skill for loop mechanics):
   ```
   lavish-axi .lavish/mock-pr.html
   ```
5. **Surface the URL — required, every time.** The open command prints `url: "http://…/session/<id>"`. Put that link at the TOP of your very next message to the user, on its own line — "Review it here: <url>" — before any summary. The user cannot open a page whose URL they never see; do NOT make them ask for it or dig it out of tool output. Re-surface it whenever it changes (e.g. after `--reopen`, or if you backgrounded the open and the link scrolled off).
   - **Print the REACHABLE host, not loopback.** If the host serves lavish over the network — `LAVISH_AXI_HOST`/`LAVISH_AXI_LINK_HOST` set to a hostname, e.g. a tailscale name — lavish prints that host and you surface it as-is. But if your shell doesn't have those set (e.g. it started before the config was deployed), lavish prints `127.0.0.1`, which the user cannot open from another device. Set `LAVISH_AXI_LINK_HOST` (and matching `LAVISH_AXI_HOST`/`LAVISH_AXI_PORT`) on the open so the printed URL is the reachable hostname. Check with the host's config / `env | grep LAVISH_AXI` if unsure.
6. **Poll and act on the result** (`poll` is a blocking single-shot that returns when the user acts):
   ```
   lavish-axi poll .lavish/mock-pr.html --agent-reply "<what to review>"
   ```
   - Annotations / change requests → apply them. **If the code changed what the PR does, update the body file to match before regenerating** — the body must describe the change as it now stands, not as first drafted. Then re-run `mock-pr-html` (same `--out`) and poll again. Loop.
   - An explicit go-ahead ("lgtm", "open it", "ship it") → approval; stop looping.
   - A clear "no" / "don't" → stop; do not open or push.
7. **Only on approval** do you `gh pr create` (or push the new commits). Never before.

## Driving lavish — gotchas

- **The port comes from the environment.** A host may pin `LAVISH_AXI_PORT`; then you set nothing and open/poll agree automatically. The only trap is overriding it for one call and not the other — `LAVISH_AXI_PORT=X lavish-axi ...` on the open but not the `poll` makes the browser show "agent not listening" (two different servers). Set it on both or neither.
- **Re-opening.** If the user ended the session earlier, `lavish-axi <file>` refuses; pass `--reopen`.
- **Never revert to a fetch.** The diff data is inlined into the page by `mock-pr-html`; there is no sibling file. lavish serves the page at `/session/<id>`, where a relative `fetch` would 404. An empty "Files changed" means an empty range or you generated before committing — not that inlining is wrong.

## Common mistakes

- **Letting the body drift from the code** — after changing the code in response to feedback, the PR body still describes the first draft. Re-write the body to match, then regenerate.
- **Not surfacing the session URL** — burying it in tool output (or in a backgrounded command) so the user has to ask for it. Paste the link as the first line of your reply, every open and re-open.
- **Hand-rolling the HTML** instead of running `mock-pr-html` — reintroduces the diff-load and file-list bugs the command exists to prevent.
- **Generating before committing** — the range renders committed history; uncommitted work won't show.
- **Opening/pushing before approval** — the whole point is the gate. Wait for an explicit go-ahead.
- **Committing `.lavish/`** — it's a scratch artifact; keep it out of the PR (gitignore or don't `git add` it).
