---
name: phx-plan
description: "Turn a feature idea, brainstorm, or review findings into a phased, checkbox-tracked implementation plan. Use to design interconnected work before building, or to convert review/investigation findings into tasks. Language-agnostic."
argument-hint: <feature description OR path to interview/review/plan file>
---

# Plan — Phased Implementation Planning

Produces `.claude/plans/{slug}/plan.md` (phased `[ ]` task checkboxes that ARE
the execution state) plus a `scratchpad.md` for decisions and dead-ends.
`/phx-work` consumes the plan; `/phx-review` findings can be replanned here.

## Usage

```text
/phx-plan Add webhook delivery with retries
/phx-plan .claude/plans/notifications/interview.md     # from a brainstorm
/phx-plan .claude/plans/auth/reviews/auth-review.md    # from review findings
/phx-plan --existing .claude/plans/auth/plan.md        # deepen a thin plan
```

## Workflow

1. **Gather context.** The argument is one of: a path to an `interview.md`
   (brainstorm), a path to a review/investigation file, a clear description,
   or a vague description.
2. **Clarify if vague** — ONE question at a time. **Skip clarification** if an
   `interview.md` with `Status: COMPLETE` exists for this slug. If the input is
   a review/investigation file, **skip research** — the findings ARE the
   research; convert them straight into tasks.
3. **Detect depth** — quick (≤3 tasks, one surface), standard, or deep
   (multi-surface, unfamiliar tech). Scale research and detail accordingly.
4. **Scan the codebase first.** Read relevant files / recent history to ground
   the plan in existing patterns and conventions. Follow what already exists.
5. **Spawn research subagents selectively and in parallel** (only for genuinely
   thin/unfamiliar areas — never "all of them"). Use built-in types:
   - `Explore` subagent → "Map how this codebase handles {area}; conventions,
     entry points, modules." Writes to `.claude/plans/{slug}/research/{area}.md`.
   - `general-purpose` subagent → unfamiliar external tech/library research.
     Returns ≤500-word summary; writes to `research/{topic}.md`.
   Create a Claude Code task per subagent; mark `in_progress` on spawn,
   `completed` as each returns. **Wait for ALL to finish before writing the
   plan.**
6. **Completeness check (MANDATORY when planning from review/investigation):**
   every finding becomes a task OR is explicitly deferred with a reason. Never
   silently drop a finding.
7. **Split decision** — if the work spans independent subsystems, propose
   decomposing into multiple plans (each its own slug → plan → work cycle)
   rather than one mega-plan.
8. **Generate the plan** — phased tasks with checkboxes (format below). Capture
   key decisions and any spikes in `.claude/plans/{slug}/scratchpad.md`.
9. **Self-check (deep only)** — ask three risk questions: What's most likely to
   break? What's unverified? What assumption, if wrong, invalidates the plan?
   Fold answers into a Risks section.
10. **Present and STOP** — show a summary and let the user decide. Never start
    implementing.

## --existing mode (deepening)

- Load the existing plan. Search `.claude/solutions/` for known risks/patterns.
- Spawn specialist subagents ONLY for thin sections; each writes to
  `research/` and returns ≤500 words.
- Add implementation detail, resolve spikes, add verification steps.
- Present a diff summary. **NEVER delete existing tasks** — only add/refine.

## plan.md format

```markdown
# {Feature} Plan

## Phase 1: {Name}
- [ ] [P1-T1] Description
- [ ] [P1-T2][research] Description that needs a subagent during work
- [ ] [P1-T3] Description

## Phase 2: {Name}
### Parallel:
- [ ] [P2-T1] Independent task A
- [ ] [P2-T2] Independent task B

## Verification
- How to prove the feature works end to end (commands to discover & run,
  behaviors to observe).

## Risks
- Risk 1 ...
- Risk 2 ... (deep only)
```

- Task IDs are `[Pn-Tm]` (phase n, task m) — `/phx-work` resumes by ID.
- An optional `[tag]` after the ID hints how to execute (e.g. `[research]`).
- Tasks under a `### Parallel:` header have no inter-dependencies and may run
  as concurrent subagents during work.

## scratchpad.md format

```markdown
## Decisions
- Decision: reasoning

## Dead-Ends
- Path tried: why it failed

## HANDOFF: {plan name}
Status: {done}/{total} tasks. Blockers: {list}. Next: {first unchecked ID}.
```

## Iron Laws

1. **NEVER auto-start `/phx-work`** — always present the plan and ask.
2. **NEVER write the plan while research subagents are still running.**
3. **Every finding becomes a task or an explicit deferral** — when planning
   from review/investigation, skip none.
4. **Spawn subagents selectively** — only relevant areas, never a blanket fan-out.
5. **Research before assuming** — web-search genuinely unfamiliar tech; don't
   research things already established in the codebase.
6. **Skip research when planning from review/investigation** — findings ARE the
   research; convert directly to tasks.
7. **Follow existing patterns** — scan before proposing; don't invent new
   structure where the codebase already has a convention.
8. **Present and STOP** — the terminal action is asking the user.

## Integration

```
/phx-brainstorm interview.md --> /phx-plan --> plan.md --> /phx-work
/phx-review review.md ----------> /phx-plan (convert findings) --> /phx-work
```
