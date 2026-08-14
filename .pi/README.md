# Forge

A pure-dev coding agent setup for [pi](https://pi.dev). Clone this as a template to start a new project — it comes with the skills, agent profiles, routing defaults, and `.pi/work/` convention already wired up.

## What's here

- `AGENTS.md` — loaded automatically by pi; the non-negotiable hard constraints, routing logic, dev defaults, and startup behavior all live here (see `.pi/design.md` §16 for why this isn't a separate `APPEND_SYSTEM.md` anymore).
- `.pi/skills/` — language and methodology references (Python, Rust, TypeScript, shell, architecture, testing, git, API design, spec-driven work, brainstorming/design thinking).
- `.pi/agents/` — `scout`, `planner`, `reviewer` (read-only, dispatched only when isolation or parallelism is actually worth it) and `builder` (the one profile with write access, dispatched only for Race mode into its own `git worktree`). There's no `debug`/`general` file — that's just the main session.
- `.pi/extensions/subagent/` — pi's own reference `subagent` tool implementation, vendored (not pi-core). `.pi/agents/*.md` is inert markdown without this — it's the thing that actually discovers and dispatches to those files. See AGENTS.md's "How to actually dispatch" for the call shape.
- `.pi/extensions/{plan-mode,custom-footer,session-name,notify,handoff,trigger-compact,questionnaire.ts,protected-paths.ts,dirty-repo-guard.ts}` — nine more of pi's own example extensions, vendored the same way as `subagent`. Mostly feature/UX additions, not guardrails — see `.pi/design.md` §9 for what each does and why, and AGENTS.md for the commands they add. `questionnaire.ts`, `protected-paths.ts`, and `dirty-repo-guard.ts` add no command of their own — see AGENTS.md's "Extensions available" for what each hooks and why it doesn't reopen the "confirmation popup" question `.pi/design.md` §3.4 already closed.
- `.pi/extensions/doom-loop-guard.ts` — the one extension here that isn't vendored. Written for Forge from scratch (see `.pi/design.md` §9.12): blocks a tool call once it repeats identically three times in a row, a minimal circuit breaker for the agent getting stuck in a loop.
- `.pi/prompts/` — `/commit`, `/changelog`, `/readme`, `/status`, `/retro`, `/smoke-test`: prompt templates for the repetitive stuff. `/retro` mines an exported session log for real friction points and turns them into doc fixes; `/smoke-test` exercises every mechanism (routing, dispatch, Race, spec-driven, prompt templates) in one session, for use before/after a real container run — see `.pi/design.md` §8.
- `.pi/work/` — durable state for tasks that need to survive a session restart (see `.pi/work/README.md`). Empty by default here; each project derived from this template accumulates its own as it goes.
- `.pi/package.json`/`.pi/tsconfig.json`/`.pi/bun.lock` — Forge's own CI tooling, just for typechecking `.pi/extensions/*.ts`. Deliberately scoped inside `.pi/`, not the repo root, so they never collide with whatever `package.json`/`tsconfig.json` the project you build here ends up needing at the top level — see `.pi/design.md` §18.
- `.pi/design.md` — the full design rationale: what this replaced, why, and what got deliberately left out.

## Assumptions baked in

- Runs inside a container (GitHub Codespaces, a devcontainer, or equivalent) — there's no destructive-action confirmation layer because the container boundary already provides real isolation. See `.pi/design.md` §3.1/§3.4 if that assumption doesn't hold for where you're actually running this.
- Pure dev scope — coding, debugging, testing, deploying. Not a general assistant.
- Model/provider per agent profile is left unconfigured on purpose (commented out in each `.pi/agents/*.md`) — pick one when you actually set this up for a project.
- The repo root is reserved for the project you build here, not for Forge's own tooling — everything Forge owns lives under `.pi/`, including this file and the design rationale (`.pi/design.md`). Only `AGENTS.md` stays at the repo root (pi only discovers it there or in an ancestor directory) plus the two things GitHub/git themselves require at root (`.github/workflows/`, `.gitignore`). Cloning this template and immediately scaffolding your actual app at the root doesn't fight with anything already there.

## Status

Early. `.pi/design.md` §5/§6 tracks what's built (P1: skills/AGENTS.md/prompts/`.pi/work/`; P2: agent profiles + the vendored `subagent` extension) versus deliberately deferred (P3: guardrail extension, only if ever running outside a container; P4: CLI-wrapping tools, only as actually needed).

**Correction**: the design doc originally claimed v1 needs zero extension code. That was wrong — `.pi/agents/*.md` dispatch is not a pi-core feature, it's defined entirely by an example extension pi ships, which had to be vendored in `.pi/extensions/subagent/` for scout/planner/reviewer to do anything at all. The "no guardrail extension" conclusion still holds; "no extension code at all" didn't.
