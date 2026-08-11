---
name: git
description: Git workflow checks — branch safety, commits, history inspection, recovery, and publishing
---

# Git

Use this skill for git operations beyond read-only inspection. `rules/git.md`
is the policy source of truth.

## Safety Rules

- Check current branch before commit, merge, or push.
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

## Commit Judgment

- Commit one complete logical unit.
- Use conventional commit format from `rules/git.md`.
- Include tests with the fix when the test is part of the same behavior.
- Explain why in the body when the change is non-obvious.
- Do not include debug code, commented-out code, WIP markers, secrets, or broad
  unrelated refactors.

## Recovery Notes

- Use `git reflog` to find lost commits or branch tips.
- Use `git stash push -m "<message>"` only when the user wants to park local
  changes.
- Use `git worktree` for parallel branch inspection when switching would disturb
  local changes.
- Use `git cherry-pick` for specific known commits rather than broad merging
  when only one fix is needed.

## Publishing Checks

- Confirm branch policy from `rules/git.md`.
- Check `git status --short` before pushing.
- Prefer draft PRs for work that needs review or CI confirmation.
- Do not hide failing checks; report them with the relevant command or run link.
