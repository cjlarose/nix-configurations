---
name: handing-off
description: Use at the end of a long session to hand work to another agent — phrases like "hand off", "write a handoff", "compact this for a fresh session", "I'm running low on context, hand this off". Writes a handoff document under XDG_STATE_HOME, composes the prompt for the next agent, and fires a wiki capture that nobody waits on. Does not run or wait for an ingest.
---

# handing-off

End a session so another agent can pick the work up cold.

Three outputs, and **only the first two are on the critical path**:

1. A **handoff document** under `$XDG_STATE_HOME`, written immediately.
2. A **prompt for the next agent**, referencing existing wiki pages, the relevant skills, and that document.
3. A **wiki capture**, fired and forgotten.

## Nothing here waits for an ingest

This skill used to write a capture and then run `ingesting-sources` synchronously, so the next agent could not start until 5-15 wiki pages had been rewritten. That is backwards: ingest is the slowest, most failure-prone step, and it now runs serially in a standing worktree that may be busy with a queue. Waiting on it could mean waiting a long time, at the exact moment the handing-off agent is running out of context.

So the handoff document is authoritative and immediate, the capture is asynchronous, and the wiki becomes eventually consistent with the work. **Never run `ingesting-sources` from here, and never wait on one.**

## Where the document goes

```
${XDG_STATE_HOME:-$HOME/.local/state}/llm-handoffs/<task>/<YYYY-MM-DD-HHMM>-<slug>.md
```

`<task>` is the workspace directory's basename, so the mapping from a workspace to its handoffs is derivable in both directions without a registry.

**Outside the workspace, deliberately.** A handoff doc inside `~/workspaces/<task>/` is destroyed by teardown — `git worktree remove` guards the worktrees, but a file at the workspace root sits outside every repo and nothing guards it at all. State rather than data under XDG because these are strictly local: they name local paths, local branches and uncommitted work in a specific worktree, and mean nothing on another machine.

Timestamped rather than overwritten, so a series of handoffs on one task keeps its history.

## Hard constraints

- **Never run or wait for `ingesting-sources`.**
- **The document must stand alone.** The next agent has none of this conversation.
- **Same secret-redaction rules as `capturing-sessions`** — and they apply to the handoff document too, even though it is not committed. It is a file on disk that will be pasted into another session.
- **Do not invent progress.** A handoff describing work as further along than it is costs the next agent more than an honest "this is half-built and I am not sure the approach holds".

## Workflow

### 1. Write the handoff document

```markdown
---
task: <workspace basename>
written: <YYYY-MM-DD HH:MM America/Los_Angeles>
workspace: <absolute path>
---

# Handoff: <what this work is>

## Where things stand
<Honest current state. What works, what does not, what is untested.>

## In flight
<Uncommitted or unpushed work, by worktree and branch. Anything half-done,
named precisely enough to find: paths, branches, commit SHAs.>

## Next steps
<Ordered, concrete, pick-up-here actions. THIS is the live list — the wiki's
task pages deliberately carry no ## Next steps, because a page written by
whoever last ingested is stale by the time someone picks the work up.>

## Deviations from the wiki
<Where the wiki is now wrong, incomplete, or not yet updated: decisions taken
this session that no page reflects, and anything a page asserts that this
session disproved. The next agent will consult the wiki and needs to know
where not to trust it.>

## Relevant wiki pages
<Page titles worth reading first, by name. Pages that exist NOW — do not cite
pages the pending capture might create.>
```

### 2. Compose the prompt for the next agent

Name the workspace, the handoff document's absolute path, the wiki pages worth reading, and the skills the work needs. Self-contained enough to paste into a fresh session.

**Discovery is via this prompt and nothing else.** No hook looks for handoff documents, and they live outside the workspace where an `ls` will not trip over them. If the prompt is lost, so is the pointer — which is the intended trade: a handoff nobody acted on is a handoff that was abandoned.

### 3. Fire a capture

Invoke `capturing-sessions` for the durable knowledge — decisions, gotchas, anything worth a page. It queues, commits and pushes, and returns.

Do not wait for the ingest, do not check whether the standing agent woke, and do not report the capture as "filed": it is *queued*. The wiki learns from it whenever the standing agent next drains the queue.

Keep the split clean: durable knowledge goes to the capture, live pick-up-here state goes to the handoff document. Where they overlap, the document wins, because it is written now and the pages are written later.

### 4. Report

The handoff document's path, the prompt (ready to paste), and one line confirming the capture was queued rather than filed.

## Examples of when this skill fires

- "hand this off"
- "I'm running low on context, write a handoff"
- "compact this for a fresh session"

## Examples of when this skill does NOT fire

- "capture this to the wiki" → `capturing-sessions`
- "ingest the queue" → `ingesting-sources`, in the standing worktree
- "what does the wiki say about X" → `querying-notes`
