---
description: Full end-to-end exercise of every Forge mechanism in one session, self-reported pass/fail, for use before/after a real container run or a design change
argument-hint: "[focus]"
---

Run a full end-to-end smoke test of this Forge setup — every phase below, in order. This is a real test, not a dry run: parallel/chain/race dispatches spawn real subprocesses and cost real time/tokens, that's expected. Self-report pass/partial/fail per numbered step with one line of evidence as you go, and be honest about it — a step that half-worked is "partial," not "pass" (see `APPEND_SYSTEM.md`).

If there's no disposable toy code to act on yet, create a small one now in whatever stack you judge fits an empty repo — your call, that's part of what's being tested.

**Phase 0 — Environment**

1. Confirm this is running in a container (not bare metal) and say how you know.
2. Confirm `.pi/extensions/subagent/` loaded. The startup banner itself isn't visible from inside the same session that produced it — a passing dispatch (Phase 3) is the real evidence; for now, just confirm the `subagent` tool is registered and note which agents you'd expect it to discover.

**Phase 1 — Routing basics**

3. Confirm you already scanned `.pi/work/` at session start and reported status (this should have happened before this prompt).
4. Pure Q&A, no tool work expected: "what's the branch policy for a `race/*` branch?"
5. Single small task: build the toy file mentioned above directly in this session — confirm the relevant language skill auto-loaded and a lint/test step ran after.

**Phase 2 — Skill + git gate**

6. Before committing, confirm you check the current branch first — if this session started on `main`, refuse/redirect to a feature branch rather than committing directly.
7. On a feature branch, make one real conventional commit for the toy file, using your own judgment on when `/commit` is worth invoking versus just doing it.

**Phase 3 — Dispatch mechanics**

8. Dispatch 3 parallel `scout` tasks exploring this repo from 3 different angles, read-only. Use the `subagent` tool exactly as `AGENTS.md` documents — this checks whether the top-level (never nested-in-task) `agentScope`/`confirmProjectAgents` shape holds on a fresh run.
9. Chain-dispatch `planner` → `reviewer` on a real design question about the toy code — report literally what the second step received via `{previous}`, to confirm it's plain text substitution and not shared context.

**Phase 4 — Guard**

10. Make a small, public-API-shaped change to the toy code (e.g. a function signature change). Build and test it here, then chain-dispatch `reviewer` before calling it done. Report whether it actually gated completion on that step or you were tempted to skip it.

**Phase 5 — Spec-driven full lifecycle**

11. Take on a deliberately fuzzy, mid-size feature request for the toy app — one that should earn a `.pi/work/<slug>/` directory. Walk it through `spec.md` → `clarifications.md` → `plan.md` → `tasks.md` → `build-log.md` → `validation.md`. Leave exactly one task unchecked on purpose at the end of this phase — needed for the resume check below.

**Phase 6 — Race mode**

12. Pick one small, real design decision with two plausible implementations for the toy app. Run an actual race: `git worktree add` two variants, parallel-dispatch `builder` into each with its own `cwd`, compare real diffs and verification, pick a winner, merge it, `git worktree remove` both. This is the least-exercised path — report every step, including anything that didn't match `docs/design.md` §7.3 as written.

**Phase 7 — Prompt templates**

13. Run `/status` — should surface the unfinished task from Phase 5.
14. Run `/changelog` for this session's commits.
15. Run `/readme` if the toy app's own README needs updating given what got built.

**Phase 8 — Report**

16. Print one table: phase → pass/partial/fail → one-line evidence. Call out anything that contradicts `AGENTS.md` or `docs/design.md` as currently written — that's exactly the input `/retro` needs next.

After this session ends, `/export` it and run `/retro <path-to-export>` in a fresh session to turn any real findings into doc fixes.

Focus: ${1:-none given}
