---
description: Mine an exported pi session log for real friction points and propose concrete Forge fixes
---

Read the session export at `{{session}}` — JSONL, one event per line. `message` events carry `role` and `content`; tool calls show up as `tool_use`/`tool_result` blocks inside assistant messages, and `thinking` blocks often narrate the reasoning behind a mistake in the model's own words.

1. Scan for friction signals only — don't speculate beyond what's actually in the log:
   - Failed or erroring tool calls (dispatch failures, rejected commits, schema errors)
   - Places the agent backtracked, guessed wrong, or had to ask the user to intervene
   - The same mistake corrected more than once in the session
   - Anywhere the agent's own reasoning names a documentation gap or "should have known this"
2. For each friction point, trace it to a root cause using the actual evidence in the log (raw tool_use params, tool_result text, thinking blocks) — read the real parameters and outputs, don't pattern-match to a plausible-sounding story.
3. Classify each one:
   - **Forge bug** — code/config in this repo is actually wrong.
   - **Doc gap** — `AGENTS.md` / a skill / an agent file didn't say the thing that would have prevented this.
   - **One-off model mistake** — correct information was available, the model just didn't use it; not worth encoding structurally.
   - **pi sharp edge** — upstream `pi` behavior worth knowing but not Forge's to fix.
4. Only propose edits for the first two categories. Note pi sharp edges as a "watch for," not a diff. Drop one-off mistakes entirely — a retro that pads its list with noise stops getting read.
5. Output a punch list: file → exact change → one-line justification citing the specific log evidence (quote the failing param or error, don't paraphrase from memory).
6. If asked to apply the list, make the edits directly and stage them — don't commit without confirmation (see `.pi/skills/git/SKILL.md`).

Nothing speculative, nothing "would be nice while we're in here" — this is a targeted fix list grounded in one real run, not a redesign session.
