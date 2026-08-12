---
name: handing-off
description: Use at the end of a long session to hand off to another agent — phrases like "hand off", "write a handoff", "compact this for a fresh session", "I'm running low on context, hand this off". Writes the session's durable knowledge and its in-flight work into Basic Memory as notes, one task note per thread, so the next session resumes from the knowledge graph rather than from a summary that is lost when the window closes.
---

# handing-off

Hand a long session off to a fresh agent by **promoting its context into Basic
Memory**, not into a throwaway summary. A summary dies with the conversation; a
task note is queryable next week from any session.

The unit of handoff is the **task note** — one per distinct in-flight thread,
carrying `## Next steps`. There is no separate handoff document. Whoever picks
the work up finds it with `search_notes` or the **memory-continue** skill.

## Why capture now

At a handoff the session is long and the context is rich, which is exactly what
is about to be lost to compaction or a fresh start. Capturing *while context is
still full* is the entire point: after compaction the specifics — the paths, the
SHAs, the thing that was tried and did not work — are already gone.

## What to do

### 1. Separate durable knowledge from in-flight state

They go to different places, and conflating them is the common failure.

**Durable knowledge** is what stays true after the work ships: a decision and
its rationale, a gotcha, how a system actually behaves, a corrected belief.
That belongs on a **concept, entity or reference note** — not on the task, which
will be closed and stop being read.

**In-flight state** is what a successor needs to resume: what is done and
*verified* versus assumed, what is next, what is blocking. That belongs on the
**task note**.

A useful test: if the task were finished tomorrow, would this still be worth
reading? If yes, it is knowledge and belongs on a durable note.

### 2. Write the durable knowledge first

For each thing worth keeping, **search before writing** —
`search_notes(query=...)` — and prefer updating the note that already covers the
topic. Fragmenting knowledge across near-duplicate notes is the failure this
knowledge base is most prone to, because writing a new note is always easier
than finding the one that already exists.

Use `edit_note` to extend an existing note; `write_note` only when nothing
covers it. Follow the **memory-notes** skill for the note format, and the
knowledge base's own conventions note for its categories and traps.

### 3. Write or refresh one task note per in-flight thread

Find the existing task first — it usually exists:

```
search_notes("", note_types=["task"], status="in-progress")
search_notes("<topic>", note_types=["task"])
```

Match on the `workspace` field, which is stable across retitling. Update in
place rather than creating a second note for the same work.

A task note looks like this:

```markdown
---
title: Reconcile AdGuard and unbound Internal-Zone Forwarding
type: task
permalink: tasks/reconcile-ad-guard-and-unbound-internal-zone-forwarding
tags: [dns, networking, homelab]
status: in-progress
workspace: adguard-unbound-zones
---

# Reconcile AdGuard and unbound Internal-Zone Forwarding

**Mission:** what this work is trying to achieve, in a sentence or two.

## Current state

What is done and **verified**, versus what is assumed. Name the difference
explicitly — an unverified assumption presented as done is how a successor
wastes an afternoon.

## Next steps

1. The concrete pick-up-here actions, in order. Paths, commands and exact
   arguments, not gestures at them.

## Observations
- [status] in-progress
- [blockers] waiting on the pfSense config export

## Relations
- part_of [[Some Epic]]
```

Rules that matter:

- **`workspace` is the workspace directory name**, `~/workspaces/<workspace>/`.
  One task, one workspace, one name. If the work has a workspace, this field is
  its directory; if it does not yet, choose the name the directory *would* take.
- **Write `permalink` explicitly**, as `tasks/<kebab-title>`. Left out, the sync
  generates one with the project name baked in, which a later project rename
  invalidates.
- **`status` goes in frontmatter *and* as a `[status]` observation.** The
  frontmatter answers `search_notes` metadata filters; the observation answers
  `schema_validate`. One without the other loses half the tooling.
- The status vocabulary is `not-started`, `in-progress`, `blocked`, `done`,
  `canceled`. Drop `## Next steps` once a task reaches `done` or `canceled` —
  it is a resume aid, and a stale one is worse than none.
- A long, multi-session piece of work stays **one** task note, updated in place
  across handoffs. Never a new note per handoff.

### 4. Report what you wrote

End by listing the task notes touched, with their permalinks, so the next agent
has an exact starting point:

```
Handed off to 2 task notes:
  memory://tasks/reconcile-ad-guard-and-unbound-internal-zone-forwarding
  memory://tasks/persist-restic-cache-directories-on-ns1010301
Resume with the memory-continue skill, or build_context on either URL.
```

## Common mistakes

- **Writing one giant note for the whole session.** A session is not a unit of
  work. Split by thread, because that is how they will be resumed.
- **Putting durable knowledge on the task note.** It gets closed and stops
  being read, taking the knowledge with it.
- **Recording intent as achievement.** "Fixed the resolver" when what happened
  was "changed the config, did not restart the service" is the single most
  expensive kind of handoff error.
- **Creating a second task note** because the existing one was not found.
  Search by `workspace` first.
- **Omitting the boring specifics.** The path, the flag, the exact command. The
  successor cannot see this conversation.
