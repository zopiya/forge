#!/usr/bin/env bash
# .pi/audit/run.sh — external driver for the overnight audit loop.
#
# Repeatedly invokes `pi -p "/audit"` as independent, one-shot, non-interactive
# processes across a bounded time window (default 00:00-04:00), each round
# picking up wherever `.pi/audit/log.md` left off. Deliberately outside pi:
# extension factories must not start their own background timers (see
# extensions.md); this mirrors the existing subagent-dispatch model instead —
# a real separate `pi` process per unit of work. See docs/design.md §10.3.
#
# Usage:
#   .pi/audit/run.sh
#   AUDIT_END_TIME=$(date -v+2M +%H:%M) AUDIT_MAX_ROUNDS=2 \
#     AUDIT_ROUND_TIMEOUT_SECONDS=90 .pi/audit/run.sh   # compressed dry run
#
# Stop early by creating .pi/audit/STOP (any content) - checked every round.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

AUDIT_DIR="$REPO_ROOT/.pi/audit"
LOG_MD="$AUDIT_DIR/log.md"
RUN_LOG="$AUDIT_DIR/run.log"
STOP_FILE="$AUDIT_DIR/STOP"

AUDIT_END_TIME="${AUDIT_END_TIME:-04:00}"
AUDIT_MAX_ROUNDS="${AUDIT_MAX_ROUNDS:-7}"
AUDIT_ROUND_TIMEOUT_SECONDS="${AUDIT_ROUND_TIMEOUT_SECONDS:-1500}"
AUDIT_MIN_GAP_SECONDS="${AUDIT_MIN_GAP_SECONDS:-30}"
AUDIT_BRANCH="${AUDIT_BRANCH:-chore/nightly-audit-$(date +%Y-%m-%d)}"

mkdir -p "$AUDIT_DIR"
touch "$LOG_MD" "$RUN_LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$RUN_LOG"; }

ntfy() {
	# Same PI_NTFY_TOPIC/PI_NTFY_SERVER as .pi/extensions/notify.ts, for
	# consistency - notify.ts itself is NOT modified (docs/design.md §10.3).
	local title="$1" body="$2"
	[ -n "${PI_NTFY_TOPIC:-}" ] || return 0
	local server="${PI_NTFY_SERVER:-https://ntfy.sh}"; server="${server%/}"
	local url
	if [[ "$PI_NTFY_TOPIC" == http* ]]; then url="$PI_NTFY_TOPIC"; else url="$server/$PI_NTFY_TOPIC"; fi
	curl -fsS -X POST "$url" -H "Title: $title" -H "Tags: robot_face" -d "$body" >/dev/null 2>&1 || true
}

# Portable timeout: macOS ships neither GNU `timeout` nor `gtimeout` by default.
run_with_timeout() {
	local seconds="$1"; shift
	"$@" & local cmd_pid=$!
	( sleep "$seconds" && kill -TERM "$cmd_pid" 2>/dev/null ) & local watcher_pid=$!
	local exit_code=0
	wait "$cmd_pid" 2>/dev/null || exit_code=$?
	kill "$watcher_pid" 2>/dev/null; wait "$watcher_pid" 2>/dev/null
	return "$exit_code"
}

past_end_time() {
	local now_epoch end_epoch
	now_epoch="$(date +%s)"
	end_epoch="$(date -j -f '%H:%M' "$AUDIT_END_TIME" +%s 2>/dev/null)"
	[ -z "$end_epoch" ] && end_epoch="$(date -d "$AUDIT_END_TIME" +%s 2>/dev/null)"  # GNU date fallback
	[ -n "$end_epoch" ] && [ "$now_epoch" -ge "$end_epoch" ]
}

log "=== audit loop starting: branch=$AUDIT_BRANCH end=$AUDIT_END_TIME max_rounds=$AUDIT_MAX_ROUNDS timeout=${AUDIT_ROUND_TIMEOUT_SECONDS}s ==="

if [ -f "$STOP_FILE" ]; then
	log "STOP file present at start - exiting without running anything."
	exit 0
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
	log "ERROR: not a git repository, aborting."
	exit 1
fi

current_branch="$(git branch --show-current)"
if [ "$current_branch" != "$AUDIT_BRANCH" ]; then
	if git show-ref --verify --quiet "refs/heads/$AUDIT_BRANCH"; then
		git checkout "$AUDIT_BRANCH" || { log "ERROR: could not check out $AUDIT_BRANCH"; exit 1; }
	else
		git checkout -b "$AUDIT_BRANCH" || { log "ERROR: could not create $AUDIT_BRANCH"; exit 1; }
	fi
fi

if [ -n "$(git status --porcelain)" ]; then
	log "ERROR: working tree dirty before round 1 - refusing to start."
	ntfy "Audit loop aborted" "Dirty working tree before round 1 on $AUDIT_BRANCH. Not started."
	exit 1
fi

round=0
commits_total=0
while :; do
	round=$((round + 1))

	if [ -f "$STOP_FILE" ]; then log "STOP file appeared - stopping after $((round - 1)) round(s)."; break; fi
	if [ "$round" -gt "$AUDIT_MAX_ROUNDS" ]; then log "Reached AUDIT_MAX_ROUNDS=$AUDIT_MAX_ROUNDS - stopping."; break; fi
	if past_end_time; then log "Reached AUDIT_END_TIME=$AUDIT_END_TIME - stopping before round $round."; break; fi

	log "--- round $round starting ---"
	head_before="$(git rev-parse HEAD)"
	round_start_epoch="$(date +%s)"
	output_file="$(mktemp "${TMPDIR:-/tmp}/audit-round-XXXXXX.txt")"

	# --approve: non-interactive modes skip the trust prompt and, without a
	# saved "always" decision, IGNORE .pi/prompts, .pi/extensions, etc under
	# defaultProjectTrust "ask"/"never" (docs/security.md). Explicit -a makes
	# this robust to trust.json ever being absent/cleared. See design.md §10.3.
	run_with_timeout "$AUDIT_ROUND_TIMEOUT_SECONDS" \
		pi --approve --name "audit-$(date +%Y%m%d-%H%M%S)-r$round" -p "/audit" \
		>"$output_file" 2>&1
	round_exit=$?

	round_seconds=$(( $(date +%s) - round_start_epoch ))
	head_after="$(git rev-parse HEAD)"
	new_commits=0
	[ "$head_before" != "$head_after" ] && new_commits="$(git rev-list --count "$head_before..$head_after")"
	commits_total=$((commits_total + new_commits))

	tail_preview="$(tail -c 400 "$output_file" | tr '\n' ' ')"
	log "round $round done: exit=$round_exit duration=${round_seconds}s commits=$new_commits"

	if [ -n "$(git status --porcelain)" ]; then
		log "ERROR: working tree dirty after round $round - stopping the loop (fail closed)."
		ntfy "Audit round $round left tree dirty - loop stopped" "$tail_preview"
		break
	fi

	if [ "$round_exit" -ne 0 ]; then
		ntfy "Audit round $round failed (exit $round_exit)" "$tail_preview"
	else
		ntfy "Audit round $round done - $new_commits commit(s)" "$tail_preview"
	fi

	rm -f "$output_file"
	sleep "$AUDIT_MIN_GAP_SECONDS"
done

log "=== audit loop finished: $((round - 1)) round(s), $commits_total total commit(s) on $AUDIT_BRANCH ==="
ntfy "Audit loop finished" "$((round - 1)) round(s), $commits_total commit(s) on $AUDIT_BRANCH. Review: git log $AUDIT_BRANCH"
