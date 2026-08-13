# `.pi/audit/` — overnight audit loop state

Drives the unattended midnight–4am code-audit loop. No service, no daemon —
`run.sh` is invoked by an external OS-level scheduler (launchd/cron) and
spawns one independent, non-interactive `pi -p "/audit"` process per round.
See `docs/design.md` §10.3/§10.5 for the full rationale (why external scheduler
and not an extension timer, the `notify.ts` decision, the rotation mechanism,
the auto-fix reviewability stance, why the loop mechanics live in a separate
generic engine).

`run.sh` itself has no while loop — it's a thin audit-domain wrapper around
the generic, goal-agnostic loop engine at `.pi/scripts/pi-loop.sh`. It sets up
the audit-specific state (branch checkout, dirty-tree fail-closed checks via
`--precheck`/`--post-round-check`) and delegates the actual bounded loop
(time window, round cap, per-round timeout, STOP file, per-round ntfy) to that
engine. If you want pi to keep working toward some *other* goal on a
schedule — not an audit — call `.pi/scripts/pi-loop.sh` directly with a
different `--prompt`; see that file's header for the full option list.

## Files

| File | Committed? | Purpose |
|---|---|---|
| `run.sh` | Yes | Audit-domain wrapper: branch setup, dirty-tree hooks, final summary notification. Delegates the loop itself to `.pi/scripts/pi-loop.sh`. |
| `log.md` | Yes | Durable rotation log, one entry per round, appended and committed by `.pi/prompts/audit.md` itself. Read at the start of each round to pick the least-recently-audited area. |
| `README.md` | Yes | This file. |
| `launchd.example.plist` | Yes | Template for installing `run.sh` as a launchd agent (see below). |
| `run.log` | No (gitignored, `*.log`) | Plain timestamped operational log — written by `.pi/scripts/pi-loop.sh` (round starts/stops, exit codes, durations) and by `run.sh`'s own branch/dirty-check lines. |
| `launchd.out.log` / `launchd.err.log` / `cron.log` | No (gitignored, `*.log`) | stdout/stderr capture from whichever scheduler is installed. |
| `STOP` | No (gitignored explicitly) | Kill-switch — create this file to stop the loop after the current round. Never commit it: a committed `STOP` would permanently disable the loop for anyone who clones the repo. |

## Installing for real

**launchd (primary, macOS):**

```
cp .pi/audit/launchd.example.plist ~/Library/LaunchAgents/works.forge.nightly-audit.plist
# edit PI_NTFY_TOPIC in the copy first if you want push notifications
launchctl load ~/Library/LaunchAgents/works.forge.nightly-audit.plist
# newer macOS: launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/works.forge.nightly-audit.plist
```

Fires once at 00:00 daily; `run.sh` itself enforces the 04:00 cutoff and round cap, so there's nothing else to schedule.

**crontab (alternative):**

```
0 0 * * * PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin PI_NTFY_TOPIC=replace-with-a-private-topic /Users/zopiya/workspace/forge/.pi/audit/run.sh >> /Users/zopiya/workspace/forge/.pi/audit/cron.log 2>&1
```

Not installed by default — add manually with `crontab -e` if you prefer cron over launchd (note modern macOS gates `cron` behind Full Disk Access for the terminal/cron itself; launchd doesn't have this issue).

## Before installing for real: dry-run it

Do not point this at a real midnight window on the first try. Run a compressed
dry run first, in a throwaway git worktree so a bug can't touch real work:

```
git worktree add ../forge-audit-dryrun -b test/audit-dryrun
cd ../forge-audit-dryrun
AUDIT_END_TIME=$(date -v+2M +%H:%M) AUDIT_MAX_ROUNDS=2 AUDIT_ROUND_TIMEOUT_SECONDS=90 \
  PI_NTFY_TOPIC=<your-personal-test-topic> .pi/audit/run.sh
```

Use a *relative* end time (`date -v+2M`, two minutes from now) rather than a
fixed clock string — a fixed past-looking time exits with zero rounds
immediately. Confirm: a `chore/nightly-audit-<date>` branch gets created,
`log.md` gets a real entry, `run.log` has round-by-round timestamps, a push
notification arrives, and the loop stops at 2 rounds or ~2 minutes, whichever
comes first. Also test the `STOP` file (`touch .pi/audit/STOP` mid-round,
confirm it stops after that round) and the dirty-tree fail-safe (leave an
uncommitted change before starting, confirm `run.sh` refuses to run at all)
before ever trusting a real overnight run. Remove the worktree afterward:
`git worktree remove ../forge-audit-dryrun`.

Every real overnight run lands its commits on its own
`chore/nightly-audit-<date>` branch — review `git log chore/nightly-audit-<date>`
and `.pi/audit/log.md` in the morning before merging anything. Nothing here
auto-merges or auto-pushes.
