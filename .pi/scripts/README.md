# `.pi/scripts/` — standalone tooling, external to pi itself

Scripts here are plain OS-level tools that happen to shell out to the `pi`
binary or to `git` — they don't depend on pi's extension system, don't
require the project to be "in a pi session," and have no opinion about what
any particular goal/prompt does. Contrast with `.pi/extensions/` (loaded
inside a pi process) and `.pi/prompts/` (expanded inside a pi session) —
everything here runs *outside* pi and is meant to be reused by other scripts
or scheduler-driven wrappers, not just typed by hand.

## `loop.sh`

Generic external loop driver: repeatedly invokes `pi -p "<prompt>"` as
independent, one-shot, non-interactive processes until a time window, round
cap, or STOP-file condition is hit. Domain-agnostic on purpose — it has zero
knowledge of what the prompt does or what "done" means; goal-specific logic
(e.g. git branch/dirty-tree handling) plugs in via `--precheck` and
`--post-round-check` hooks (arbitrary shell commands, checked by exit code
only) rather than being special-cased inside the engine.

Run `.pi/scripts/loop.sh --help` for the full option list.

See `.pi/audit/run.sh` for a real example: it owns everything audit-specific
and calls this engine to do the actual looping. To make pi keep working
toward a *different* goal on a schedule, write a new prompt (or reuse an
existing one) and call `loop.sh` directly — no new while loop needed.

Rationale for why this lives outside pi entirely (not an extension/timer) is
in `docs/design.md` §10.3/§10.5.

## `worktree.sh`

Small, reusable wrapper around `git worktree add`/`remove`/`list`, encoding
the gotchas that come with them (single-path removal, leftover build
artifacts blocking a plain remove, merged-vs-unmerged branch deletion) so
callers don't each re-derive them. Meant for the same audience as `loop.sh`:
external wrappers that need an isolated workspace without a pi process
making the judgment calls — `.pi/audit/run.sh` uses it to give the nightly
audit branch its own worktree instead of switching branches in whatever
checkout happens to be current. Interactive pi sessions use it too, e.g. for
Race mode (see AGENTS.md's "Race mode mechanics").

Run `.pi/scripts/worktree.sh --help` for the full command list. See
`.pi/skills/worktree/SKILL.md` for when to reach for a worktree and the
reasoning behind the gotchas this script encodes, and `docs/design.md` §14
for why worktree handling lives here as a script rather than being
special-cased inside `loop.sh` or duplicated across every consumer.
