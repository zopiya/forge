---
name: spec-driven
description: Spec-first workflow using .pi/work/ artifacts, phase gates, and dispatch handoffs
---

# Spec-Driven Skill

Use this skill when a task benefits from a durable intent -> plan -> task ->
implementation chain. The goal is better working context and fewer guessed
requirements, not ceremony.

## Core Principles

- Start with user outcomes before implementation details.
- Keep artifacts structured enough for a session (or a dispatched agent) to
  pick up cold and continue.
- Ask only for decisions that materially change scope, risk, or behavior.
- Treat `tasks.md` as the execution contract for the build phase.
- Validate implementation against the spec, not just against tests.
- Bypass the full flow for small, obvious work — see Bypass Rules below.

## Currentness Rule

If a spec or technical plan introduces a new dependency, framework, service,
runtime, or "latest" behavior, verify current official docs or a primary
source before locking the decision. Record in `clarifications.md` whether
that decision was verified or assumed.

## Artifact Shape

All working artifacts live in `.pi/work/<slug>/` (see `.pi/work/README.md`
for the naming rule and when a directory is warranted at all). Do not create
`.specify/`, `specs/`, or other parallel workspaces — this is the only
convention.

### spec.md

Include:

- Problem and user goal.
- In-scope and out-of-scope behavior.
- User scenarios and acceptance criteria.
- Functional requirements with stable IDs, such as `FR-001`.
- Non-functional requirements only when they affect the task.
- Assumptions and open clarifications (or point to `clarifications.md`).

Avoid:

- Framework, library, database, or file-level implementation choices.
- Vague success criteria that cannot be reviewed.

Quality bar:

- Someone (or something) implementing this doesn't have to guess intent.
- A reviewer can tell whether behavior is missing, extra, or contradictory.
- Open questions are separated from assumptions.

### quality_checklist (fold into spec.md or clarifications.md — no dedicated file)

Checklist items test the quality of the requirements, not the
implementation.

Good item patterns:

- `Are error states specified for each external dependency? [Completeness]`
- `Is "fast" quantified with a measurable user-facing threshold? [Clarity]`
- `Are acceptance criteria consistent with FR-003? [Consistency]`

Avoid items such as "verify the button works" or "test the API returns 200";
those belong to `validation.md`, not requirement quality.

### plan.md

Include:

- Technical context and constraints (grounded in the actual repo, not an
  imagined one — read before writing this).
- Architecture approach and alternatives rejected.
- Interface or data-shape changes.
- Risks and mitigations.
- Validation strategy.

The plan may mention files and technologies, but only after the requirements
in `spec.md` are stable.

Quality bar:

- The approach follows evidence from the actual codebase, not assumption.
- Alternatives are limited to realistic options.
- Risks include validation and rollback/mitigation when relevant.

### tasks.md

Tasks must be:

- Ordered by dependency.
- Independently checkable.
- Linked to requirement IDs or plan sections when possible.
- Marked with `[P]` only when parallel execution won't touch the same files.
- Updated as tasks complete — this file is the live progress tracker `/status`
  reads.

Quality bar:

- Each task has an observable done condition.
- Task order makes dependencies clear.
- Implementation doesn't need to invent scope or architecture beyond what's
  written here.

## Dispatch Responsibilities

Forge doesn't have a separate agent per phase — see `AGENTS.md` for the full
routing table. For spec-driven work specifically:

| Phase | Who does it |
|-------|-------------|
| Explore repo context | Main session, or `.pi/agents/scout.md` in parallel for multi-directional investigation |
| Write spec / plan / tasks | `.pi/agents/planner.md`, or main session for smaller cases |
| Implement | Main session |
| Validate | Main session (run the commands, write `validation.md`) |
| Review drift | `.pi/agents/reviewer.md` — checks spec/plan/tasks against what actually got built |

## Bypass Rules

Skip full spec-driven flow when:

- The request is pure Q&A.
- The change is a narrow one-file fix with obvious behavior.
- The user explicitly asks for direct execution and risk is low.

Prefer spec-driven flow when:

- The task spans multiple files or would benefit from a dispatched agent.
- Requirements are ambiguous but can be structured.
- User-facing behavior, public APIs, or workflow semantics change.
- The implementation should be recoverable across a session restart.
