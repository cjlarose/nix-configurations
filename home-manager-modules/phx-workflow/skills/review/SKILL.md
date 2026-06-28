---
name: phx-review
description: "Review the current diff with parallel subagents across multiple dimensions (correctness, security, tests, performance, conventions) and produce a consolidated verdict. Read-only — finds and explains, never fixes. Language-agnostic."
argument-hint: "[all|correctness|security|tests|performance|conventions]"
---

# Review — Multi-Dimension Diff Review

Spawns parallel subagents to review changed code, filters noise, and writes a
consolidated verdict. **Read-only**: it reports findings; it never edits code.

## Usage

```text
/phx-review                 # all dimensions on the current diff
/phx-review security        # focused single-dimension review
/phx-review tests
```

## Workflow

1. **Identify changed files & prep dirs.**
   - Pick the SLUG: Glob `.claude/plans/*/` for the active plan; default `"review"`.
   - `mkdir -p .claude/plans/{slug}/reviews`.
   - Determine the diff: `git diff --name-only` against the merge-base with the
     default branch (and/or recent `HEAD~N`). Save the diff base so reviewers
     can tell NEW code from pre-existing.
2. **Load context & prior reviews.** Read `.claude/plans/{slug}/scratchpad.md`
   for planning decisions. If `reviews/` has prior output, include it as
   "PRIOR FINDINGS" so reviewers don't repeat themselves.
3. **Detect requirements source (optional).** If a plan/interview/issue clearly
   defines what this change should do, capture it as the yardstick for a
   requirements-coverage check.
4. **Spawn review subagents (parallel, one message).** Use built-in
   `general-purpose` (or `Explore`) subagents — one per dimension. NEVER spawn
   the same dimension twice. Spawn with `run_in_background: true` and give each
   an explicit `output_file` under `reviews/{dimension}.md`. Scope EVERY
   reviewer to the diff:
   > "Review ONLY the new/changed code in this diff for {dimension}. For
   > pre-existing code, one line max. Do not deep-analyze unchanged files.
   > Write findings to {output_file}."
   - **all** (default) → spawn the relevant subset of:
     - **correctness** — bugs, logic errors, edge cases, error handling.
     - **security** — only if auth/session/secret/input-handling files changed.
     - **tests** — coverage of new behavior, missing/flaky cases.
     - **performance** — only if hot paths / queries / loops changed.
     - **conventions** — consistency with existing patterns in the repo.
   - A single-dimension arg spawns only that reviewer.
   - Create a Claude Code task per subagent; mark `completed` as each returns.
5. **Collect & verify.** Wait for ALL subagents. Confirm each `output_file`
   exists; if one is missing, extract findings from the agent's message and note
   a `WARN` in the scratchpad. If tests/build were never run this session, run
   the project's discovered test + build commands yourself as a fallback gate.
6. **Filter findings (anti-noise).** Drop or demote a finding if: a senior dev
   would wave it off; the fix adds more complexity than the problem; it
   duplicates another reworded; it targets unchanged code (mark `PRE-EXISTING`
   instead of raising).
7. **Write the consolidated verdict** to
   `.claude/plans/{slug}/reviews/{feature}-review.md`:
   - Verdict: **PASS | PASS WITH WARNINGS | REQUIRES CHANGES | BLOCKED**.
   - If requirements were detected: a `## Requirements Coverage` block (UNMET →
     REQUIRES CHANGES; PARTIAL → PASS WITH WARNINGS) before per-dimension findings.
   - Per-dimension findings with severity and `file:line`.
8. **Present & ask.** STOP — present the verdict. Do NOT create tasks or fix
   anything. On REQUIRES CHANGES / BLOCKED, offer BOTH paths:
   `/phx-plan {review-file-path}` (convert findings to a plan) **or** a direct
   fix. On PASS, offer to capture any reusable learning to `.claude/solutions/`.

## Iron Laws

1. **Review is READ-ONLY** — find and explain, never fix.
2. **NEVER auto-fix after review** — always ask the user first.
3. **Always offer both paths** — `/phx-plan {review-file}` and a direct fix.
4. **Scope to the diff** — findings on unchanged code are marked PRE-EXISTING,
   not raised as blockers.
5. **One subagent per dimension** — never duplicate a reviewer role.
6. **Research before claiming** — reviewers must verify before asserting things
   about CI/CD, external services, or runtime behavior.
7. **Filter noise** — a wall of low-value nits is a failed review; demote them.

## Integration

```
/phx-work --> /phx-review --> (REQUIRES CHANGES) --> /phx-plan {review-file} --> /phx-work
                         \--> (PASS) ------------> capture learning / commit
```
