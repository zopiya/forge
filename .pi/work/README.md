# `.pi/work/` — durable task state

This replaces what used to be a Synapse room. No service, no protocol — just files, read and written with the normal `read`/`write`/`edit` tools.

## When to create a directory here

Not every task earns one. Rule of thumb: **will this work continue past this session, or does the output need to stay around?** If yes, create `.pi/work/<slug>/`. If the task resolves within this conversation, don't — keep a plain in-conversation TODO instead.

| Task shape | Create a directory? |
|---|---|
| Direct answer / small obvious change | No |
| Single responsibility, done in one session | No — conversation TODO at most |
| Parallel exploration / comparing approaches (Race) | Yes |
| Build protected by test/review (Guard) | Depends on size — large or public-API changes, yes |
| Multi-phase or needs to survive a restart (PM / Spec-driven) | Yes |

## Naming

`<kebab-case-short-name>-<4-6 char random suffix>`, e.g. `payment-retry-a3f9`. Generate once, when the directory is first created; the suffix exists so two worktrees that both start a feature with the same short name don't collide.

## Files

| File | Written by | Purpose |
|---|---|---|
| `spec.md` | planner / main session | Requirements + acceptance criteria |
| `clarifications.md` | planner / main session | Open and resolved ambiguities |
| `plan.md` | planner | Architecture, interfaces, risks, validation strategy |
| `tasks.md` | planner / main session | Ordered task list with completion state |
| `build-log.md` | main session | Implementation summary + files touched |
| `validation.md` | main session / reviewer | Commands run + results |
| `drift-review.md` | reviewer | Whether spec/plan/tasks still match what got built |

Not every feature needs all seven — write the ones that carry real information, skip the rest.

## Git

These files are committed, on purpose — see `docs/design.md` §3.6. When a feature branch merges, its `.pi/work/<slug>/` becomes part of the historical record for that change.
