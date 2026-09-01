---
name: soliciting-pr-feedback
description: Use when you are about to open a GitHub pull request, or about to push new commits to an already-open PR, and want the user to review the exact change first — its title, body, commits (each with its own diff), and the unified per-file diff — as a GitHub-styled page before it becomes public. Triggers on "let me review the PR before opening it", "show me the PR first", "mock PR", "review before pushing".
---

# Soliciting PR feedback

## Overview

Before a pull request goes public — opened, or pushed to with new commits — show the human the *exact* change as a GitHub-styled page in lavish and act on their annotations. They review the real title, body, and diff, not a prose summary. The page has three tabs, one shown at a time: Conversation (the title and body), Commits (each commit with its own diff — the changes that commit alone introduced), and Files changed (the unified diff of the whole range). Nothing leaves the machine until they approve.

**Core rule: never hand-write the HTML.** Building the page by hand is where the bugs live (broken diff loading, wrong file lists, drift). `mock-pr-html` produces it deterministically from git + your title and body. Use it.

**Core rule: never truncate the poll output.** The human's annotations are delivered exactly once. `poll` empties the session's `prompts` as it hands them over, and what remains afterwards is the freeform chat only — never the annotations. There is no second copy to fall back on: the session in `~/.lavish-axi/state.json` is left holding `prompts: []`, `server.log` records no payloads, and polling again cannot recover it — with nothing queued the next poll blocks waiting for the *next* batch, it never reports what you lost. So an annotation your command filtered away is *destroyed*, and the only remedy left is making the human type it again. And the payload is small and dense — often just one line per annotation — so a filter does not trim noise off something verbose, it deletes notes outright: five notes make an eleven-line response, and `tail -5` deletes the first of them whole; six notes and it deletes two. Never put `tail`, `head`, `grep`, `sed`, `awk`, or any other line-dropping filter after `lavish-axi poll`. Read every byte it gives you.

## When to use

- You finished a change on a branch and are about to `gh pr create` — review it first.
- You are about to push follow-up commits to an already-open PR — pass `--pr-number N`.
- The user says "show me the PR", "mock PR", "let me review before you open/push it".

Not for: changes already pushed and being reviewed on GitHub itself.

## Workflow

1. **Commit** your work locally (the page renders committed history, not the worktree).
2. **Write the PR body** to a markdown file, following `writing-pull-request-descriptions`. Put it OUTSIDE the repo (a temp path), so it can't be swept into the PR. Title: the PR subject from that same skill, not just the first commit.
3. **Create a review artifact.** Run this exactly once when beginning a new
   human review. Lavish keys its session and conversation to the canonical
   absolute artifact path, so a fixed name would reopen an unrelated review.
   Keep `artifact` unchanged for every feedback iteration in this review:
   ```
   mkdir -p .lavish
   review_dir="$(mktemp -d .lavish/review-XXXXXXXX)"
   artifact="$review_dir/mock-pr.html"
   ```
4. **Generate** the page:
   ```
   mock-pr-html --title "<subject>" --body-file /tmp/body.md \
     --base origin/main --head HEAD --out "$artifact"
   ```
   Range is `origin/main..HEAD` (what the PR would contain). Add `--pr-number N` when soliciting feedback on commits headed for open PR #N. `--repo`/`--branch` auto-derive from git. `mock-pr-html --help` for all flags.
5. **Open** in lavish (a bare invocation opens; see the `lavish` skill for loop mechanics):
   ```
   lavish-axi "$artifact"
   ```
6. **Surface the URL — required, every time.** The open command prints `url: "http://…/session/<id>"`. Put that link at the TOP of your very next message to the user, on its own line — "Review it here: <url>" — before any summary. The user cannot open a page whose URL they never see; do NOT make them ask for it or dig it out of tool output. Re-surface it whenever it changes (e.g. after `--reopen`, or if you backgrounded the open and the link scrolled off).
   - **Print the REACHABLE host, not loopback.** If the host serves lavish over the network — `LAVISH_AXI_HOST`/`LAVISH_AXI_LINK_HOST` set to a hostname, e.g. a tailscale name — lavish prints that host and you surface it as-is. But if your shell doesn't have those set (e.g. it started before the config was deployed), lavish prints `127.0.0.1`, which the user cannot open from another device. Set `LAVISH_AXI_LINK_HOST` (and matching `LAVISH_AXI_HOST`/`LAVISH_AXI_PORT`) on the open so the printed URL is the reachable hostname. Check with the host's config / `env | grep LAVISH_AXI` if unsure.
7. **Poll and act on the result** (`poll` is a blocking single-shot that returns when the user acts). Keep a durable copy of what it returns:
   ```
   lavish-axi poll "$artifact" --agent-reply "<what to review>" \
     | tee "$review_dir/feedback-$(date +%s).txt"
   ```
   **Nothing that can drop a line may go after `poll`** — no `tail`, `head`, `grep`, `sed`, `awk`. The ban is on discarding output, not on pipes as such, and `tee` discards nothing: it keeps the feedback in front of you *and* leaves the whole of it on disk, so if your own view was capped somewhere you can still recover it. Give every poll its own filename, as above — this step is a loop, and a fixed name is emptied the moment the next poll opens it, taking the previous round's copy with it. If a payload is too big to take in at once, narrow the *saved file*, never the live stream: the file is the copy that cannot be destroyed, so grepping or slicing it costs nothing, and reaching for a filter under that pressure — with no sanctioned way to shrink anything — is what produced `| tail -5` in the first place. Narrow it knowing the shape, though. The payload is TOON, and when every annotation carries the same fields it is tabular — one physical line each, newlines escaped inside — so line tools cut cleanly between notes. When one of them carries an extra field the array expands into multi-line `- key: value` blocks instead, and a line-oriented cut *can* split a note in half. So the safe reduction is the same either way: drop `dom_snapshot`, never more than a single line and the thing bloating the response, and never slice inside the `prompts` block itself. What is always one line is the *prompt text* — newlines stay escaped inside it in both shapes — but the annotation record around it is not.
   A human reviewing a real PR will outlast any foreground command timeout, so expect the poll to be killed and just run it again — queued feedback survives that. Lavish's own banner says it never gets lost; that holds for a kill while waiting, which is almost always. It does not hold for a kill landing during delivery, because the server empties `prompts` before the response reaches you. You will not observe that as an empty result — `poll` long-polls indefinitely, so a session with nothing queued hangs rather than returning. It reaches you as the human saying, in the chat panel, that they already sent something; that message is itself a queued prompt, so it is what unblocks your poll. Believe them and ask them to send it again, rather than assuming you merely have not waited long enough. If you background it instead, use only a harness facility that tracks the job and hands you its completion output; the truncation ban applies there exactly as it does here, and a background job is where it was violated before.
   Then **account for every item in the batch before you edit anything.** Enumerate them by `prompt` — always populated, and the most distinguishing field you have — adding the `selector`/`tag`/`text` anchor for the ones that have it. Not everything does: an element annotation carries a real anchor, but a freeform chat message arrives as `tag: "message"` with an empty `selector` and the constant `text: "Freeform message"`, so anchors alone would collapse three of them into one indistinguishable row. One row per item, in the order they arrived, and never merge two that read alike — a reviewer who writes "typo" against three separate lines has sent three notes, not one. You have an exact check before that, so use it: the array header names its own length. `prompts[3]` means three annotations arrived, whatever shape follows it — one line each when they all carry the same fields, an indented `- key: value` block each when one of them carries an extra. That is not exotic: anything annotated inside a mermaid diagram brings a `target`, and one such annotation expands the whole array. Count the annotations you actually have against that N before you start. If they disagree you are looking at a truncated view, and the rest is still in the saved file. Then echo the list back in your next `--agent-reply`, because the count cannot catch everything — a batch destroyed in delivery never reaches you to be counted, and only the human knows it existed. An omission they spot costs one more loop iteration, against discovering it once the PR is already open. Do **not** try to infer completeness from `uid`. It numbers DOM elements within a single page load, gets minted for elements you merely inspect and for annotation cards opened and abandoned, and restarts from 1 every time the page is regenerated — so gaps in it are the norm and mean nothing.
   - Annotations / change requests → apply them. **If the code changed what the PR does, update the body file to match before regenerating** — the body must describe the change as it now stands, not as first drafted. Then re-run `mock-pr-html` (same `--out`) and poll again. Loop.
   - An explicit go-ahead ("lgtm", "open it", "ship it") → approval; stop looping.
   - A clear "no" / "don't" → stop; do not open or push.
8. **Only on approval** do you `gh pr create` (or push the new commits). Never before.

## Driving lavish — gotchas

- **The port comes from the environment.** A host may pin `LAVISH_AXI_PORT`; then you set nothing and open/poll agree automatically. The only trap is overriding it for one call and not the other — `LAVISH_AXI_PORT=X lavish-axi ...` on the open but not the `poll` makes the browser show "agent not listening" (two different servers). Set it on both or neither.
- **Re-opening.** If the user ended the session earlier, `lavish-axi <file>` refuses; pass `--reopen`.
- **Never revert to a fetch.** The diff data is inlined into the page by `mock-pr-html`; there is no sibling file. lavish serves the page at `/session/<id>`, where a relative `fetch` would 404. An empty "Files changed" means an empty range or you generated before committing — not that inlining is wrong.

## Common mistakes

- **Truncating the poll** — `lavish-axi poll … | tail -5` reads back as a harmless way to keep the output short. It is the one mistake in this skill that cannot be undone: the annotations it dropped were consumed on delivery and exist nowhere afterwards, so the human has to reconstruct their own review from memory. It has already happened twice. Nothing that drops a line goes after `poll`, ever.
- **Applying a partial batch quietly** — having lost part of the feedback, applying the notes you *did* get and reporting success. The human then has no way to tell which annotations you never saw. Name what is missing first, ask for it, and apply the batch as a whole.
- **Letting the body drift from the code** — after changing the code in response to feedback, the PR body still describes the first draft. Re-write the body to match, then regenerate.
- **Not surfacing the session URL** — burying it in tool output (or in a backgrounded command) so the user has to ask for it. Paste the link as the first line of your reply, every open and re-open.
- **Reusing a generic artifact name** — Lavish hashes the canonical absolute path into the session key and retains its chat. Create one `mktemp` review directory for each new review; reuse its `artifact` only while iterating on that review.
- **Hand-rolling the HTML** instead of running `mock-pr-html` — reintroduces the diff-load and file-list bugs the command exists to prevent.
- **Generating before committing** — the range renders committed history; uncommitted work won't show.
- **Opening/pushing before approval** — the whole point is the gate. Wait for an explicit go-ahead.
- **Committing `.lavish/`** — it's a scratch artifact; keep it out of the PR (gitignore or don't `git add` it).
