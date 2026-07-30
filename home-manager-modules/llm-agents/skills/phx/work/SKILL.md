---
name: phx-work
description: "Execute a plan's tasks one at a time with verification after each, tracking progress in the plan's checkboxes. Use after /phx-plan to implement, or --continue to resume interrupted work. Language-agnostic."
argument-hint: <path to plan file> [--continue]
---

# Work — Execute Plan Tasks with Verification

Reads `.claude/plans/{slug}/plan.md`, implements each unchecked task, verifies
by discovering and running the project's own build/test/lint commands, and
records progress directly in the plan's checkboxes.

## Usage

```text
/phx-work .claude/plans/webhooks/plan.md
/phx-work .claude/plans/webhooks/plan.md --continue   # resume after interruption
```

## Workflow

1. **Research decision** — for plans with >3 tasks, briefly ask the user how
   much per-task research to do; skip for ≤3 simple tasks.
2. **Check context (MANDATORY).** Read `.claude/plans/{slug}/scratchpad.md` for
   prior decisions and dead-ends. Grep `.claude/solutions/` for already-solved
   patterns relevant to this work.
3. **Load plan, build task list, resume.**
   - Read `plan.md`; count `[x]` (done) vs `[ ]` (remaining).
   - Find the first unchecked task by `[Pn-Tm]` ID.
   - Create Claude Code tasks (`TaskCreate`) for ALL unchecked items; set
     `blockedBy` dependencies between phases (a phase blocks the next).
   - **Stale-plan check:** if the plan predates this session, spot-check 2–3
     referenced files still exist / match before trusting it.
4. **Discover the project's verification commands** (do this once, up front):
   inspect the repo to find how it builds, tests, lints, and formats — e.g.
   `package.json` scripts, a `Makefile`/`justfile`, `Cargo.toml`,
   `pyproject.toml`/`tox.ini`, `go.mod`, a CI config, or a `CONTRIBUTING` doc.
   Prefer a project-defined composite command (a `check`/`ci`/`precommit`
   script or make target) when one exists. Note what you found; if you can't
   find a command for a step, say so rather than guessing.
5. **Execute tasks** — for each `- [ ] [Pn-Tm][tag] Description`:
   - `TaskUpdate({taskId, status: "in_progress"})`.
   - If `[tag]` calls for it, spawn a focused subagent; otherwise implement directly.
   - **Verify (tiered, narrowest scope that proves the change):**
     - *Per task:* the fast feedback loop — typecheck/compile and/or format the
       changed files (whatever the project's quick check is).
     - *Per phase:* run the lint + the tests **scoped to the affected
       files/area** (not the whole suite), plus the build.
     - *Final gate:* run the **full test suite once** at the very end.
   - On success: mark the checkbox `[x]`, append a one-line implementation note
     inline after the task, `TaskUpdate({taskId, status: "completed"})`.
   - On failure: retry up to **3 times**, then stop and write a `BLOCKER` +
     `DEAD-END` entry to `scratchpad.md` and a `HANDOFF` note; do not thrash.
   - **Auto-continue between phases:** when Phase N finishes, immediately start
     Phase N+1 (no need to ask). Do NOT auto-proceed to review.
   - Tasks under `### Parallel:` may be dispatched as concurrent subagents.
6. **Completion** — summarize what shipped, then `AskUserQuestion`: Run
   `/phx-review`? Commit? Continue manually? STOP for the choice.
7. **Check for additional plans** — Glob `.claude/plans/*/plan.md`; mention any
   with remaining `[ ]` tasks, but do NOT auto-start them.

## Iron Laws

1. **NEVER auto-proceed to `/phx-review`** or the next plan — always ask.
2. **AUTO-CONTINUE between phases of the current plan** — don't stop mid-plan to ask.
3. **Plan checkboxes ARE the state** — `[x]` done, `[ ]` pending; no separate
   state file.
4. **Verify after EVERY task** — never skip verification; never claim done
   without running the project's checks.
5. **Max 3 retries, then BLOCKER** — record the dead-end; stop retrying.
6. **Stage specific files** — `git add <paths>`; NEVER `git add -A` / `git add .`.
7. **Read the scratchpad BEFORE implementing** — it holds dead-ends and decisions.
8. **Clarify ambiguous tasks** — ask the user rather than guessing.

## Resume (--continue)

Re-read the plan, skip `[x]` tasks, resume at the first `[ ]`. The plan's
checkboxes + the scratchpad HANDOFF note are the entire resume contract — no
hidden state.

## Integration

```
/phx-plan plan.md --> /phx-work --> (ask) --> /phx-review
```
