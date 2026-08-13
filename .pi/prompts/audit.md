---
description: One rotating pass of the overnight audit loop — pick the least-recently-audited area, review it thoroughly, fix low-risk issues, report the rest
argument-hint: "[area]"
---

This is one round of the unattended overnight audit loop (`.pi/audit/run.sh`, midnight–4am, see `docs/design.md` §10.3). You are running headless (`pi -p`, no human attending) — work autonomously, make a clean decision at every step, and never leave the working tree in an ambiguous state.

**1. Pick an area.**

If an area was given explicitly ($1), audit that. Otherwise read `.pi/audit/log.md` and pick whichever real subsystem/framework in this repository has gone longest without an entry — or has never had one. "Subsystem" means something like a language/package boundary, a top-level directory with its own concerns, an extension family, a build/deploy path — infer this repo's actual boundaries from its structure, don't assume a fixed list. Don't repeat the most-recently-audited area unless it's genuinely the only one left.

**2. Audit that area thoroughly.**

Read the relevant code/config/tests end to end. Look for: dead code, obvious bugs, lint-level issues, missing/broken error handling, outdated or contradictory documentation, drift between docs (`AGENTS.md`, `docs/design.md`, skill files) and actual behavior, obvious inefficiencies. Don't rabbit-hole into a redesign — this is a maintenance pass.

**3. Classify every finding, then act.**

- **Clear and low-risk** (lint-level, dead code, an obviously-wrong value, a broken link, a trivial off-by-one, a doc that flatly contradicts the code it describes): fix it directly, run the relevant test/lint for that part of the stack if one exists, and commit it — one atomic, independently-revertable commit per fix, conventional commit format (`.pi/skills/git/SKILL.md`), on the current branch. Do not switch or create branches yourself, do not touch `main` — the wrapper already checked out the right branch.
- **Anything requiring judgment** — a behavior change, an API/interface change, a design trade-off, anything you are not fully confident is safe to change unattended: do NOT touch it. Only report it.

When genuinely unsure whether something is low-risk, treat it as judgment-required and only report it — under-fixing costs a longer morning review list; over-fixing risks a bad unattended commit.

**4. Leave the tree clean.**

Before finishing, `git status --porcelain` must be empty — every change committed, or reverted if you decided not to keep it. The wrapper script checks this and stops the whole night's run if it isn't true.

**5. Append to the log, and commit that too.**

Append one entry to `.pi/audit/log.md`, in this exact shape:

```markdown
## YYYY-MM-DD HH:MM — <area>

- Commits: <N> (or "none")
- Findings fixed: <one line each, or "none">
- Findings reported (not fixed): <one line each, with why it needed judgment, or "none">
```

Use the actual current date/time (`date`) — don't guess it. Fold this into your last fix commit if you made one, or as one small standalone `chore(audit): log round` commit if you made no code changes this round — Step 4's clean-tree requirement covers this file too.

**6. Final message.**

End your response with a one-line summary (area, commit count, whether anything needs human judgment) — the wrapper script's notification is built from this.

Area: $1
