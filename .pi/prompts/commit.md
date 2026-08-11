---
description: Generate and execute a conventional commit from staged changes
---

Create a conventional commit from the currently staged diff.

1. Run `git branch --show-current` — on `main`, stop and tell the user to switch to `dev` or a feature branch first (see `.pi/skills/git/SKILL.md`).
2. Run `git diff --staged --stat` — if there's nothing staged, stop and tell the user to `git add` first instead of guessing what they meant.
3. Run `git log --oneline -5` to match the existing commit style in this repo.
4. Pick a type: `feat` `fix` `docs` `chore` `refactor` `test` `ci` `perf`.
5. Write `type(scope): description` — subject line ≤72 chars, imperative mood, lowercase, no trailing period.
6. Add a body only if the change isn't self-explanatory from the subject — explain why, not what.
7. Check the diff doesn't contain debug code, commented-out blocks, WIP markers, or secrets — see `.pi/skills/git/SKILL.md`'s Forbidden in Commits.
8. Show the message and run `git commit -m "..."`.

{{scope}}
