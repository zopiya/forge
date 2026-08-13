---
name: github
description: GitHub workflow via gh CLI — PRs, issues, Actions/CI, reviews, and releases
---

# GitHub

Use this skill for anything that goes through GitHub itself, not just the
local git repo — PRs, issues, Actions runs, releases. Prefer `gh` over the
web UI or raw REST calls; it's already authenticated in most environments.

## Auth Check

```bash
gh auth status
```

Run this before anything else if a `gh` command fails with an auth error —
don't assume the token is missing, confirm it.

## Pull Requests

```bash
gh pr create --title "..." --body "..." --base <branch> [--draft]
gh pr view [<number>] --json state,statusCheckRollup,reviewDecision
gh pr checks [<number>] --watch
gh pr diff [<number>]
gh pr review <number> --approve|--request-changes|--comment -b "..."
gh pr merge <number> --squash|--merge|--rebase [--auto]
```

- Prefer `--draft` for work that still needs CI/review before it's ready.
- Check `statusCheckRollup` before merging — don't merge on top of failing or
  pending checks unless explicitly told to.
- `--auto` (auto-merge) still requires branch protection to allow it; if it's
  not enabled, merge manually once checks pass.
- Match the target repo's branch policy from `.pi/skills/git/SKILL.md` — this
  skill covers the GitHub-side mechanics, not which branch to build on.

## Issues

```bash
gh issue create --title "..." --body "..." [--label ... --assignee ...]
gh issue list --state open --label bug
gh issue comment <number> -b "..."
gh issue close <number> -c "closed by <sha>"
```

Reference issues from commits/PRs with `Closes #123` / `Fixes #123` (auto-closes
on merge) rather than closing manually when the fix is already in the PR.

## Actions / CI

```bash
gh run list --branch <branch> --limit 5
gh run view <run-id> --log-failed
gh run watch <run-id>
gh run rerun <run-id> [--failed]
gh workflow run <workflow> [-f key=value]
```

Triage a failing run:

1. `gh run view <run-id> --log-failed` — read the actual failure, don't guess from the job name.
2. Reproduce locally if the failure is in a step that maps to a local command (test/lint/build).
3. Only `gh run rerun --failed` when the failure is known-flaky (network blip, rate limit) — rerunning to paper over a real failure hides the bug.

## Reviews

```bash
gh pr review <number> --comment -b "..."
gh api repos/{owner}/{repo}/pulls/{number}/comments -f body="..." -f path="..." -f line=<n>
```

Use `gh pr review` for a top-level review; drop to `gh api` only for inline
comments on a specific line, since `gh pr review` doesn't support that directly.

## Releases

```bash
gh release create <tag> --title "..." --notes "..." [--draft] [--prerelease]
gh release upload <tag> <file>
```

Tag first (`git tag`) or let `gh release create` create the tag from the
current ref — confirm which one before running, they behave differently.

## Safety Rules

- Never force-merge past required checks or branch protection — if a check
  is blocking and shouldn't be, that's a policy question for the user, not
  something to route around.
- Don't close issues/PRs the user didn't ask to close.
- Don't push secrets into workflow files or logs — `gh secret set` for
  anything sensitive, never a plain env var in the workflow YAML.
- Confirm before merging anything that isn't yours end-to-end (a PR you
  didn't author or fully review this session).
- Draft PRs and `gh pr comment` are cheap and reversible — prefer them over
  actions that rewrite history or notify a wide audience.
