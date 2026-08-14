---
name: brainstorm
description: Design thinking reference — architectural trade-offs, decomposition, and spec writing
---

# Brainstorm

Reference knowledge for structured design thinking. On exploratory or ideation-driven requests, apply this in-session (no code until the design is settled) — there's no separate "plan mode" to switch into; this skill loads on demand per `.pi/FORGE.md`'s routing table.

## Evaluating Approaches

When comparing 2-3 design options, assess each on:

| Dimension | Questions |
|-----------|-----------|
| **Simplicity** | How many concepts must a new engineer learn? |
| **Correctness** | What classes of bugs does this approach prevent or introduce? |
| **Evolvability** | How hard is it to change later? What's locked in? |
| **Testability** | Can each unit be tested in isolation? |
| **Performance** | What are the bottlenecks? Are they acceptable? |

**Default priority:** Simplicity > Correctness > Evolvability > Performance

## When to Brainstorm

Use brainstorm mode when:

- The user is exploring a direction, not asking for a concrete patch.
- Multiple plausible architectures or product shapes exist.
- The trade-off depends on future workflow, audience, team preference, or risk
  tolerance.
- A wrong early decision would be expensive to unwind.

Do not use brainstorm mode for obvious local fixes, small docs edits, or tasks
where the repository already has one clear pattern.

## Decomposition Heuristics

- Split along **change rate**: things that change together belong together
- Split along **team ownership**: avoid cross-team dependencies in a single unit
- Split when a function/module has **more than one reason to change** (SRP)
- Stop splitting when the interface between parts is more complex than the parts themselves (over-engineering signal)

## Spec Structure

A good spec covers:

1. **Problem** — what user pain or business need is addressed?
2. **Non-goals** — what are we explicitly NOT solving?
3. **Proposed design** — the recommended approach with rationale
4. **Alternatives considered** — why they were rejected
5. **Open questions** — unresolved decisions that block implementation
6. **Success criteria** — how do we know this is done and working?

For spec-driven work, write specs into `.pi/work/<slug>/spec.md` (see
`.pi/work/README.md`) — that is the default now, not an optional export.

## YAGNI Checklist

Before adding complexity, ask:

- Is this needed by the current task?
- Do we have a concrete use case for it today?
- Would removing it make the code simpler?

If all three answers are "no / yes / yes" — remove it.

## Output Shape

- Lead with a recommendation, not a menu dump.
- Compare only viable options.
- Name the trade-off that would change the recommendation.
- End with the smallest next decision needed from the user.
