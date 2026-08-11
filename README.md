# Forge

A pure-dev coding agent setup for [pi](https://pi.dev). Clone this as a template to start a new project — it comes with the skills, agent profiles, routing defaults, and `.pi/work/` convention already wired up.

## What's here

- `AGENTS.md` — loaded automatically by pi; the routing logic, dev defaults, and startup behavior live here.
- `APPEND_SYSTEM.md` — the non-negotiable hard constraints, appended to pi's default system prompt.
- `.pi/skills/` — language and methodology references (Python, Rust, TypeScript, shell, architecture, testing, git, API design, spec-driven work, brainstorming/design thinking).
- `.pi/agents/` — `scout`, `planner`, `reviewer`: read-only profiles dispatched only when isolation or parallelism is actually worth it. There's no `build`/`debug`/`general` file — that's just the main session.
- `.pi/prompts/` — `/commit`, `/changelog`, `/readme`, `/status`: prompt templates for the repetitive stuff.
- `.pi/work/` — durable state for tasks that need to survive a session restart (see `.pi/work/README.md`). Empty by default here; each project derived from this template accumulates its own as it goes.
- `docs/design.md` — the full design rationale: what this replaced, why, and what got deliberately left out.

## Assumptions baked in

- Runs inside a container (GitHub Codespaces, a devcontainer, or equivalent) — there's no destructive-action confirmation layer because the container boundary already provides real isolation. See `docs/design.md` §3.1/§3.4 if that assumption doesn't hold for where you're actually running this.
- Pure dev scope — coding, debugging, testing, deploying. Not a general assistant.
- Model/provider per agent profile is left unconfigured on purpose (commented out in each `.pi/agents/*.md`) — pick one when you actually set this up for a project.

## Status

Early. `docs/design.md` §5/§6 tracks what's built (P1: skills/AGENTS.md/prompts/`.pi/work/`; P2: agent profiles) versus deliberately deferred (P3: guardrail extension, only if ever running outside a container; P4: CLI-wrapping tools, only as actually needed).
