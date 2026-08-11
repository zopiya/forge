---
description: Generate and execute a conventional commit from staged changes
---

Create a conventional commit from the currently staged diff.

1. Run `git diff --staged --stat` — if there's nothing staged, stop and tell the user to `git add` first instead of guessing what they meant.
2. Run `git log --oneline -5` to match the existing commit style in this repo.
3. Pick a type: `feat` `fix` `docs` `chore` `refactor` `test` `ci` `perf`.
4. Write `type(scope): description` — subject line ≤72 chars, imperative mood, lowercase, no trailing period.
5. Add a body only if the change isn't self-explanatory from the subject — explain why, not what.
6. Show the message and run `git commit -m "..."`.

{{scope}}
