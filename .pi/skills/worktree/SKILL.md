---
name: worktree
description: When and how to use git worktrees for isolated workspaces — Race mode, branch inspection, scripted/scheduled runs — and the gotchas around removing them safely
---

# Worktree

A `git worktree` gives a task its own working directory and index, checked
out to its own branch, without disturbing the current checkout. Use one
whenever two pieces of work need to write to the filesystem at the same
time, or when a scripted/scheduled process (no human attention) shouldn't
be able to leave the caller's own checkout on the wrong branch.

## When to use one

- **Race mode** — comparing two or more real parallel implementations; see
  `.pi/FORGE.md`'s "Race mode mechanics". This is the one case dispatch `cwd`
  exists for (`.pi/agents/builder.md` is only ever dispatched into a
  worktree).
- **Inspecting another branch without disturbing local changes** — instead
  of `git stash` + `git checkout` + `git checkout -` + `git stash pop`.
- **A scripted or scheduled process that writes to the repo** — e.g. an
  external loop driven by `.pi/scripts/loop.sh` (see `.pi/scripts/README.md`
  for a worked example): give it its own worktree so it never touches the
  branch the human is actively on, and a bad run can't corrupt anything
  outside its own directory.

## How

Prefer `.pi/scripts/worktree.sh` over raw `git worktree` commands — it
encodes the gotchas below so callers don't have to re-derive them:

```
worktree.sh add <path> <branch> [<start-point>]
worktree.sh remove <path> [--force] [--delete-branch]
worktree.sh list
```

Naming convention: `../<repo>-<purpose>-<label>`, e.g. `../forge-race-a`,
`../forge-nightly-2026-08-14` — sibling of the main checkout, not nested
inside it.

## Gotchas

- **`git worktree remove` takes exactly one path per call** — no globbing,
  no batch removal. Remove each worktree individually.
- **A worktree that ran a build or test suite usually has untracked
  leftovers** (`__pycache__/`, `.pytest_cache/`, compiled artifacts) that
  make a plain `remove` refuse. Check `git status` in the worktree first —
  `worktree.sh remove` does this automatically and refuses without
  `--force`. Only pass `--force` after confirming the listed files are
  genuinely just build/test byproducts, not real uncommitted work; if the
  byproducts are expected and recurring, add them to `.gitignore` instead
  of routinely force-removing past them.
- **Branch deletion needs the right flag**: a merged branch (the Race
  winner, or any branch whose work already landed) deletes with
  `git branch -d`; an unmerged branch (a Race loser, or an abandoned
  attempt) needs `git branch -D`. `worktree.sh remove --delete-branch`
  picks the right one automatically by checking `git branch --merged`.
- **No extra trust step needed** — pi's `trust.json` is keyed by folder
  path with parent-directory inheritance, so trusting the container root
  already covers every worktree under it.

## Cleanup discipline

Don't leave worktrees lying around after the work they were created for is
judged/merged/abandoned — `worktree.sh remove` (with `--delete-branch` when
the branch is done too) as the last step, not a manual follow-up. If a
`.pi/work/<slug>/` directory exists for the task, record the outcome there
before cleanup.
