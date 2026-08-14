---
description: Generate or update this project's AGENTS.md (Forge's onboarding file, auto-loaded every session)
argument-hint: "[focus]"
---

Generate or update `AGENTS.md` for this project — the file `pi` auto-loads at the start of every session, Forge's equivalent of CLAUDE.md.

**Step 1 — Detect.**

Check whether `AGENTS.md` already exists at the repo root.

- **If it does not exist** (bootstrapping a fresh project onto the Forge methodology): go to Step 2, "Generate from scratch."
- **If it already exists**: do NOT generate new content or attempt a "refresh" from scratch, even if asked to run `/init` again. `AGENTS.md` is a hand-authored, carefully-considered file — Forge's own is documented decision-by-decision in `.pi/design.md`. Go to Step 3, "Propose additions only," instead.

**Step 2 — Generate from scratch (only when `AGENTS.md` is absent).**

0. **Scaffold first, if this is genuinely a new project.** If the repo has no
   real source structure yet (empty, or just a `README`/`LICENSE`/`.git`) —
   confirm the stack/kind of project if it isn't already obvious (ask via the
   `questionnaire` tool rather than guessing), then create the initial layout
   *before* writing `AGENTS.md`: standard root files and top-level
   directories from `.pi/skills/project-layout/SKILL.md`, plus the
   stack-specific idiom from the matching `.pi/skills/<lang>/SKILL.md`'s
   Layout section (`src/lib.rs` vs `src/main.rs` for Rust, `src/<package>/`
   for Python, `src/index.ts` for TypeScript, etc. — read the actual section,
   don't guess the convention from memory). Show the directory tree you're
   about to create and get confirmation before creating it. **Skip this
   sub-step entirely if the repo already has real source files** — describe
   what's there in Step 1 below, don't impose a different shape on top of an
   existing structure.

Inspect the repository before writing anything:

1. Stack and structure: language(s), package manager, build/test/lint commands actually present (`package.json` scripts, `justfile`, `Makefile`, `pyproject.toml`, `Cargo.toml`, etc.) — report only what's evidenced, never invent a command.
2. `.pi/` contents, if present: `.pi/agents/*.md` (dispatchable subagent roles), `.pi/extensions/*.ts` (hooks/commands), `.pi/skills/*/SKILL.md` (auto-loaded reference material), `.pi/prompts/*.md` (slash commands), `.pi/work/` (durable task-state convention).
3. `docs/` for any existing design-rationale or architecture document.
4. Existing `README.md` for a plain-language description of what the project is/does.

Write `AGENTS.md` covering, in this order, each section only if the repository actually supports it — don't describe a mechanism that isn't there:

- One-paragraph "what this is" — practical, not aspirational.
- Stack/toolchain summary and the real commands to build/test/lint.
- Session-start behavior, if `.pi/work/` exists: point at scanning it for incomplete `tasks.md`.
- A routing/process table only if there's a real reason for one — don't invent one for a project that's just flat, single-session work.
- Agents available for dispatch, if `.pi/agents/*.md` exists — one line each, pointing at the file rather than duplicating it.
- Extensions available, if `.pi/extensions/*.ts` exists — one line each: command/trigger + one-sentence purpose.
- Working style / code conventions actually evidenced by the repo (existing lint config, formatting, commit style from `git log`) — don't prescribe a style the repo doesn't already follow.
- A pointer to `.pi/design.md` (or wherever rationale lives) if one exists, or a note that there isn't one yet.

Keep it concise — this file loads every session, verbosity has an ongoing cost. Use Forge's own `AGENTS.md` (this repository, if visible) as a reference for *shape*, not content — a new project's file describes that project, not Forge.

Show the generated content and ask for confirmation before writing `AGENTS.md`.

**Step 3 — Propose additions only (when `AGENTS.md` already exists).**

1. Read the existing `AGENTS.md` in full.
2. Run the same inspection as Step 2 (stack, `.pi/` contents, `docs/`).
3. Identify concrete gaps only — something the repository actually has (an agent role, an extension, a `.pi/work/`-style convention, a build command) that the existing file doesn't mention at all. Do not flag wording or anything already covered in substance.
4. If there are no gaps, say so plainly and stop — don't invent an addition to justify running the command.
5. If there are gaps, propose each as a small, standalone insertion (exact text, exact location) and ask for confirmation before writing anything.
6. Never rewrite, reorder, or delete existing content, and never replace the whole file. If explicitly asked for a full rewrite instead, warn once that this discards a hand-authored file and require explicit confirmation before doing it.

Focus: ${1:-none given}
