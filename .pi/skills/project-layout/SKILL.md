---
name: project-layout
description: Repository directory conventions — where things go, standard root files, and disciplined restructuring
---

# Project Layout

Use this skill when creating a new project, adding a new top-level
directory/file, or reorganizing an existing one. Goal: match what an
experienced contributor from that ecosystem expects on first `ls`, not a
bespoke layout invented per-project. This is the cross-cutting discipline —
`.pi/skills/architecture/SKILL.md` covers code-level design decisions,
this one covers where files physically live.

## Before Adding Anything at the Root

- Does this belong inside an existing directory instead of a new top-level
  one? Prefer nesting over root sprawl.
- Is there already a community-standard location for this in the project's
  ecosystem? Use it — see per-language conventions below, don't invent one.
- A repo root should be scannable in a few seconds: source, tests, docs,
  config, and a small set of standard project files. Nothing loose.

## Standard Root Files

| File | Add when |
|---|---|
| `README.md` | Always — first thing a new contributor reads. |
| `.gitignore` | From commit 1, not added reactively after build output gets committed. |
| `LICENSE` | Before this is ever shared or open-sourced. |
| `CHANGELOG.md` | Once there's a real release history — see `/changelog`. |
| `CONTRIBUTING.md` | Once there's an actual external-contributor workflow to document. |
| `.editorconfig` | Cheap, cross-editor formatting baseline — add early. |

Don't create `CHANGELOG.md`/`CONTRIBUTING.md` speculatively for a solo or
early-stage repo — empty ceremony files are their own kind of clutter, the
same failure mode as sprawl in the other direction.

## Common Top-Level Directories

| Directory | Holds |
|---|---|
| `src/` (or the ecosystem's idiomatic equivalent) | Application/library source. |
| `tests/` or `test/` | Test suite — match whatever the language ecosystem conventionally uses, don't introduce a third name. |
| `docs/` | Design docs, ADRs, architecture rationale. |
| `scripts/` | One-off or repeatable ops scripts, not part of the shipped product. |
| `.github/workflows/` | CI. |
| `examples/` | Runnable usage examples, kept separate from the library itself. |
| Root-level dotfiles/manifests | Most tools expect their own config at repo root by convention (`tsconfig.json`, `pyproject.toml`, `Cargo.toml`, `.eslintrc`) — don't relocate these for tidiness, that breaks tool auto-discovery. |

## Per-Language Conventions

Defer to the stack-specific skill for the actual idiom — this skill only
sets the cross-cutting discipline, not per-language specifics:

- TypeScript/Node: `.pi/skills/typescript/SKILL.md`
- Python: `.pi/skills/python/SKILL.md`
- Rust: `.pi/skills/rust/SKILL.md`

## Monorepo vs Single Package

Default to a single package/module until there's a real reason not to —
same principle as `.pi/skills/architecture/SKILL.md`'s "modular monolith
before service extraction," applied to repo shape instead of code
boundaries. Split into `packages/`/`apps/` only for genuinely independent
deployables or publishable units, not for organizational tidiness alone —
a monorepo tool (workspaces, Nx, Turborepo, a Cargo workspace) is real
infrastructure with real cost, don't add it speculatively.

## Restructuring an Existing Messy Repo

- Don't fold a big reorg into the same change as unrelated work — a pure
  move/rename commit is reviewable on its own, and git tracks renames
  cleanly when content stays similar enough.
- Confirm before moving anything a build/CI/import path depends on — a
  directory move is easy to script and easy to silently break whatever
  referenced the old path.
- One commit per logical move (`.pi/skills/git/SKILL.md`'s commit
  granularity), not one giant "reorganize everything" commit.
- State the target layout before moving files, not after — if it's not
  obvious what goes where, that's a sign the plan isn't finished yet.

## Review Checklist

- Every top-level entry's purpose is obvious from its name alone.
- No loose scratch/temp files committed at root.
- Config lives where its own tool expects it, never relocated for tidiness.
- A new contributor could guess where to add a new file without asking.
