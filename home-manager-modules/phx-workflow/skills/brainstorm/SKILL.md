---
name: phx-brainstorm
description: "Brainstorm a feature or change — explore ideas, compare approaches, gather requirements. Use when the idea is vague, the approach is unclear, or you want to discuss before planning. Language-agnostic."
argument-hint: <topic or feature idea>
---

# Brainstorm — Adaptive Requirements Gathering

Interactive interview → research → synthesis loop. Produces a structured
`interview.md` that `/phx-plan` detects and consumes (skipping re-clarification).

## Usage

```text
/phx-brainstorm Add some kind of notification system
/phx-brainstorm Improve authentication security
/phx-brainstorm                    # starts with an open question
```

## Workflow

```
/phx-brainstorm {topic}
    |
    v
[INTERVIEW] <-----------------+
    |                         |
    v (sufficient OR exit)    |
[DECISION POINT]              |
    |- Research --> [RESEARCH]+
    |- Continue interview ----+
    |- Make a plan --> STOP (suggest /phx-plan {slug})
    |- Store & exit --> STOP (artifacts saved)
    +- Discuss --> freeform --> [DECISION POINT]
```

## Phase 1: Adaptive Interview

Create `.claude/plans/{slug}/` (slug = short kebab-case topic name). Ask ONE
question at a time.

### Coverage dimensions

Track coverage across 6 dimensions (0 = uncovered, 1 = partial, 2 = sufficient).
**Ask Scope early** — for "optimize X" / "improve X" topics, pin boundaries
(in/out, local-only, which environments) before research, not during.

| Dim   | Target                     | Sufficient signal                          |
|-------|----------------------------|--------------------------------------------|
| What  | Specific behavior/features | Concrete verbs, not "some kind of"         |
| Why   | Problem solved, user need  | Clear benefit stated                       |
| Scope | In/out boundaries          | Explicit exclusions stated                 |
| Where | Modules, files, surfaces   | File paths or component names mentioned    |
| How   | Approach, constraints      | At least one concrete constraint           |
| Edge  | Errors, scale, auth        | 2+ edge cases identified                   |

Interview is **"sufficient" when total score ≥ 8 / 12**.

### Context-aware questioning

**Before each question**, run a brief codebase scan on topics the user mentioned:

1. User mentions a topic (e.g., "notifications") → Grep/Glob for related code.
2. Use scan results to ground the next question in what actually exists.
3. Unknown/niche topic → suggest a research pause before continuing.

### Signal detection

- **Vague answer** ("maybe", "not sure") → probe deeper on the same dimension.
- **Niche topic** mentioned → "This involves {X}. Want me to research it first?"
- **Detailed answer** covering 3+ dimensions → mark all covered, advance.
- **No new coverage** for 2 consecutive questions → suggest the Decision Point.

## Phase 2: Decision Point

**MANDATORY**: write `interview.md` FIRST, then use `AskUserQuestion`.
Never let the conversation flow past this point without a formal choice.

1. Write current state to `.claude/plans/{slug}/interview.md` (format below).
2. Show coverage summary: "Coverage: What 2/2 | Why 2/2 | Scope 1/2 | …".
3. Use `AskUserQuestion` with EXACTLY these options (4 max — "Other" covers
   freeform discussion):
   - **Research** — search codebase + web for approaches (≤2 subagents).
   - **Continue interview** — ask more questions.
   - **Make a plan** — suggest: `/phx-plan .claude/plans/{slug}/interview.md`.
   - **Store & exit** — save everything, come back later.
4. Wait for the response. Do NOT proceed without an explicit choice.

**AskUserQuestion discipline**: decisions only, never narration or rhetorical
check-ins. Every option states concrete impact so the user can pick without a
follow-up question.

### interview.md format

```markdown
# {Topic} — Brainstorm Interview

Status: IN_PROGRESS | COMPLETE
Coverage: What x/2 | Why x/2 | Scope x/2 | Where x/2 | How x/2 | Edge x/2 (total/12)

## What
...
## Why
...
## Scope (in / out)
...
## Where (modules, files, surfaces)
...
## How (approach, constraints)
...
## Edge cases
...

## Open questions
- ...

## Approaches considered (if research ran)
- Approach A — thesis / antithesis
- Approach B — thesis / antithesis
```

Set `Status: COMPLETE` once coverage ≥ 8/12 and the user chooses "Make a plan"
or "Store & exit" — `/phx-plan` keys off this to skip re-clarification.

## Phase 3: Research (Diverge → Evaluate → Converge)

**First cycle: MAX 2 subagents** — keep it fast. Spawn both in ONE message,
`run_in_background: true`. Use built-in subagent types (no custom agents):

- An **`Explore` subagent** — "How does this codebase already handle {topics}?
  Map existing patterns, conventions, and the modules involved." Have it write
  to `.claude/plans/{slug}/research/codebase-patterns.md`.
- A **`general-purpose` subagent** — "Research established approaches to
  {topics} (web + general knowledge). Return a ~500-word summary of options
  with trade-offs." (It may use WebSearch/WebFetch.)

Do NOT spawn more agents in the first cycle. If the user wants a deeper dive,
they pick "Research" again at the next Decision Point — then spawn focused
agents for specific questions.

**Evaluate** — for each approach found:
- *Thesis*: why it works for THIS codebase.
- *Antithesis*: why it might NOT (scale, complexity, conflicts with existing patterns).

**Converge** — present 2–3 approaches with honest trade-offs. **Do NOT pick
one** — the decision belongs to the user / to `/phx-plan`. Return to the
Decision Point (`AskUserQuestion`).

## Iron Laws

1. **NEVER auto-transition** to `/phx-plan` — always present it as an option.
2. **ONE question at a time** — never dump a question list.
3. **Always write artifacts** — `interview.md` is the contract with `/phx-plan`.
4. **Scan the codebase between questions** — every question is context-aware.
5. **AskUserQuestion at EVERY decision point** — never flow past a checkpoint
   without a formal choice. Most critical law.
6. **STOP after presenting options** — do not proceed without user input.
7. **MAX 2 subagents in the first research cycle** — deeper dives are later cycles.
8. **Stay neutral in research** — surface trade-offs, don't recommend.

## Integration

```
/phx-brainstorm --> interview.md --> /phx-plan (skips clarification)
                                 --> /phx-plan --existing (deepens)
                                 --> stored for a later session
```

Position: optional upstream of `/phx-plan`.
