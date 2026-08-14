---
name: git
description: Git workflow checks — branch safety, commits, history inspection, recovery, and publishing
---

# Git

Use this skill for git operations beyond read-only inspection.

## Branch Protocol

Check current branch before any commit, merge, or push:

| Branch | commit | merge | push |
|--------|--------|-------|------|
| `main` | ❌ | ❌ | ❌ |
| `dev` | ❌ | ✅ | ❌ |
| `feat/*` | ✅ | ✅ | ✅ |
| `fix/*` | ✅ | ✅ | ✅ |
| `docs/*` | ✅ | ✅ | ✅ |
| `chore/*` | ✅ | ✅ | ✅ |
| `race/*` | ✅ | ✅ | ❌ |

1. Run `git branch --show-current`.
2. On `main` → stop, switch to `dev` or create a feature branch.
3. On `dev` → create a feature branch: `git checkout -b feat/<name> dev`.
4. On a feature branch → proceed normally.
5. After work: suggest `git checkout dev && git merge --no-ff <branch>`.

Branch naming: `feat/<short-description>`, `fix/<short-description>`, `docs/<short-description>`, `chore/<short-description>`. `race/<slug>-<variant>` is a special case created per-variant inside a dedicated `git worktree` for Race mode (see `.pi/FORGE.md`'s "Race mode mechanics") — never pushed, deleted along with its worktree once the race is judged and the winner merged.

This table is a default, not a hard gate — a solo repo with no `dev` branch at all doesn't need to invent one just to satisfy this table; adapt to what the repo actually does.

## Commit Format (Conventional Commits)

```
<type>(<scope>): <description>

[optional body — explain WHY, not WHAT]
[optional footer — Closes #123]
```

Types: `feat` `fix` `docs` `chore` `refactor` `test` `ci` `perf`. Subject ≤72 chars, imperative mood, lowercase, no trailing period. Breaking changes: `feat!: drop Node 16` or a `BREAKING CHANGE:` footer. See `.pi/prompts/commit.md` for the interactive flow.

## Commit Granularity

| Task type | Granularity |
|-----------|-------------|
| Multi-file feature | per architecture unit |
| Interface + impl | interface first |
| Refactor | per independent action |
| Bug fix | fix + test together |
| Documentation | per topic |

Each commit must be independently revertable. When in doubt, smaller.

## Forbidden in Commits

Debug code / stray `console.log`, placeholder TODO comments, commented-out code blocks, WIP or temp markers, secrets.

## When to Commit

Commit after completing a logical unit, before switching focus, before destructive operations, after tests pass. Don't commit code that fails compilation/lint, incomplete logical changes, or debug/WIP code — use `git stash` instead.

## Safety Rules

- Never force-push shared branches.
- Never reset or discard user changes unless explicitly requested.
- Keep commits independently revertable.
- Prefer non-interactive commands.

## Inspection Commands

```bash
git status --short
git branch --show-current
git diff --stat
git diff --check
git log --oneline -5
```

## Recovery Notes

- Use `git reflog` to find lost commits or branch tips.
- Use `git stash push -m "<message>"` only when the user wants to park local changes.
- Use `git worktree` for parallel branch inspection when switching would disturb local changes — see `.pi/skills/worktree/SKILL.md` for setup/cleanup and the gotchas around removing one safely.
- Use `git cherry-pick` for specific known commits rather than broad merging when only one fix is needed.

## Publishing Checks

- Confirm branch policy above before pushing.
- Check `git status --short` before pushing.
- Prefer draft PRs for work that needs review or CI confirmation.
- Do not hide failing checks; report them with the relevant command or run link.
