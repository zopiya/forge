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

Example — wrapping some recurring goal (say, a nightly cleanup pass) in its
own isolated worktree instead of running unattended against whatever
checkout is currently open:

```bash
WT="../$(basename "$PWD")-nightly-$(date +%Y-%m-%d)"
BRANCH="chore/nightly-$(date +%Y-%m-%d)"
.pi/scripts/worktree.sh add "$WT" "$BRANCH"

.pi/scripts/loop.sh \
  --prompt "/some-recurring-task" \
  --until 04:00 --max-rounds 7 \
  --cwd "$WT" \
  --precheck "cd '$WT' && [ -z \"\$(git status --porcelain)\" ]" \
  --post-round-check "cd '$WT' && [ -z \"\$(git status --porcelain)\" ]"

[ -z "$(git -C "$WT" status --porcelain)" ] && .pi/scripts/worktree.sh remove "$WT"
```

That's the whole pattern: a wrapper owns the domain-specific setup (branch,
worktree, dirty-tree gating), `loop.sh` owns the bounded repetition. Write a
new prompt, adjust the `--precheck`/`--post-round-check` commands, and this
same handful of lines covers any other unattended goal — no new `while` loop
needed.

Rationale for why this lives outside pi entirely (not an extension/timer) is
in `docs/design.md` §10.3/§10.5.

## `worktree.sh`

Small, reusable wrapper around `git worktree add`/`remove`/`list`, encoding
the gotchas that come with them (single-path removal, leftover build
artifacts blocking a plain remove, merged-vs-unmerged branch deletion) so
callers don't each re-derive them. Meant for the same audience as `loop.sh`:
external wrappers that need an isolated workspace without a pi process
making the judgment calls (see the example above). Interactive pi sessions
use it too, e.g. for Race mode (see AGENTS.md's "Race mode mechanics").

Run `.pi/scripts/worktree.sh --help` for the full command list. See
`.pi/skills/worktree/SKILL.md` for when to reach for a worktree and the
reasoning behind the gotchas this script encodes, and `docs/design.md` §14
for why worktree handling lives here as a script rather than being
special-cased inside `loop.sh` or duplicated across every consumer.
