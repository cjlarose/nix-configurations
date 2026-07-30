---
name: phx-full
description: "Autonomous end-to-end implementation of a large feature: runs discover → plan → work → verify → review as a state machine with cycle limits. Use for big multi-surface features. NOT for executing an existing plan file — use /phx-work for that. Language-agnostic."
argument-hint: <feature description>
---

# Full — Autonomous Plan → Work → Verify → Review Cycle

Drives the whole workflow spine as a state machine, looping back to fix review
findings until the work passes or a cycle/blocker limit is hit. This is the
"do the whole thing" skill; the individual stages are `/phx-plan`, `/phx-work`,
`/phx-review`.

## Usage

```text
/phx-full Add a notification system with email + in-app delivery
/phx-full Add OAuth login --max-cycles 5
```

Flags: `--max-cycles N` (default 10), `--max-retries N` (default 3, per task),
`--max-blockers N` (default 5, before stopping with INCOMPLETE).

## State machine

```
INITIALIZING -> DISCOVERING -> PLANNING -> WORKING -> VERIFYING -> REVIEWING -> COMPLETED
                                              ^                          |
                                              +------ (findings) --------+
                                                                         -> BLOCKED (limits hit)
```

1. **INITIALIZING** — *wrong-input guard*: if the argument is a path to an
   existing `.claude/plans/*/plan.md`, do NOT re-plan — run `/phx-work {path}`
   instead and stop. Otherwise create `.claude/plans/{slug}/` and a
   `progress.md` state file.
2. **DISCOVERING** — assess complexity; decide research depth (quick / standard
   / comprehensive). Scan the codebase; spawn `Explore` subagents to map
   relevant existing patterns. **Discover the project's build/test/lint/format
   commands** here (package.json scripts, Makefile/justfile, Cargo.toml,
   pyproject, go.mod, CI config, etc.) and record them in `progress.md`.
3. **PLANNING** — apply the `/phx-plan` logic: spawn selective research
   subagents, wait for ALL, generate `plan.md` with phased `[Pn-Tm]` checkboxes.
   (Autonomous mode: no approval gate here unless something is genuinely ambiguous.)
4. **WORKING** — apply the `/phx-work` logic: implement each task, verify with
   the discovered commands (narrow per task, scoped tests per phase). Checkboxes
   are the state. Max `--max-retries` per task → record BLOCKER.
5. **VERIFYING** — run the full discovered verification (build + full test
   suite + lint/format check) once the work phase completes.
6. **REVIEWING** — apply the `/phx-review` logic: spawn parallel dimension
   subagents, collect, filter. **Skip redundant reviewers**: skip the
   tests/build reviewer if VERIFYING just passed; for small diffs (<~200 lines
   changed) run only correctness + security (if auth files touched).
   - If findings require changes and limits remain: fix them in a WORKING pass,
     then loop back to VERIFYING. Increment the cycle counter.
   - If clean: → COMPLETED.
7. **COMPLETED** — summarize. Optionally capture non-trivial solved problems to
   `.claude/solutions/{category}/{fix}.md` (verify before recording — never
   document an unverified fix).
8. **BLOCKED / INCOMPLETE** — when `--max-cycles` or `--max-blockers` is hit,
   STOP with a clear status, the remaining `[ ]` tasks, and the blockers in
   `progress.md`.

## State tracking

- Persist state in `.claude/plans/{slug}/progress.md` (current state, cycle
  count, blocker count, discovered commands) AND via Claude Code tasks: one task
  per phase, `in_progress` on entry / `completed` on exit, with sequential
  `blockedBy` dependencies.

## Iron Laws

1. **NEVER skip verification** — every task passes the project's fast check
   before moving on; scoped tests per phase; full suite at the final gate.
2. **Respect cycle limits** — when `--max-cycles` is exhausted, STOP with
   INCOMPLETE; do not loop forever.
3. **One state transition at a time** — follow the machine strictly.
4. **Discover before deciding** — always run DISCOVERING (including command
   discovery) before PLANNING.
5. **Review reports, only WORKING fixes** — review subagents never edit; fixes
   happen in a WORKING pass.
6. **Skip redundant review** — don't re-run a check the VERIFY phase already proved.
7. **Verify before recording a solution** — unverified fixes poison the corpus.
8. **Lean narration** — this runs largely autonomously; narrate phase
   transitions, decisions that need explaining, and errors. Skip filler
   ("Now I'll…", "Let me…") — just act, then report what happened.

## Integration

`/phx-full` is the autonomous superset of `/phx-plan` + `/phx-work` +
`/phx-review`. For an existing plan file, use `/phx-work`. To gather fuzzy
requirements first, run `/phx-brainstorm` and feed its `interview.md` in.
