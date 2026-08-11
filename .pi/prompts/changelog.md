---
description: Generate a CHANGELOG entry from git history in Keep a Changelog format
---

Generate a CHANGELOG entry following the [Keep a Changelog](https://keepachangelog.com) format for range: {{range}}

1. Run `git log --oneline --no-merges` over the given range (default: last 50 commits if none given), and `git tag --sort=-version:refname | head -5` for context.
2. Group commits by conventional commit type:
   - `feat` → **Added**
   - `fix` → **Fixed**
   - `refactor` / `perf` → **Changed**
   - `docs` → **Changed** — except `docs(work)` / commits scoped to `.pi/work/<slug>/` artifacts (spec/plan/tasks/build-log/validation): those are process bookkeeping for a feature already covered by its own `feat`/`fix` entry, omit them too
   - `chore` / `ci` → omit (internal, not user-facing)
   - `BREAKING CHANGE` / `feat!` → **Breaking Changes** (highlight prominently)
3. Format as:

   ## [version] - YYYY-MM-DD

   ### Breaking Changes
   ### Added
   ### Changed
   ### Fixed

4. Use `{{range}}` as the version header if it looks like a version tag; otherwise use `[Unreleased]`.
5. Ask whether to append to `CHANGELOG.md` or just print the entry.
