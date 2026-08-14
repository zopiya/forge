#!/usr/bin/env bash
# .pi/audit/run.sh — audit-domain wrapper around .pi/scripts/loop.sh.
#
# This file owns everything specific to "unattended overnight code audit":
# setting up a dedicated worktree+branch, refusing to start (or continue)
# on a dirty working tree, and the human-facing summary notification. The
# generic loop mechanics (time window, round cap, per-round timeout, STOP
# sentinel, per-round ntfy) all live in the domain-agnostic
# .pi/scripts/loop.sh engine — this script has no while loop of its own,
# it only sets up audit-specific state and hooks into loop.sh via
# --precheck/--post-round-check. See docs/design.md §10.3/§10.5/§14.
#
# The audit branch runs in its own git worktree (via .pi/scripts/worktree.sh,
# see .pi/skills/worktree/SKILL.md) rather than switching branches in
# whatever checkout happens to be current — an unattended midnight process
# must never leave the human's own working directory on a different branch.
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
STOP_FILE="$AUDIT_DIR/STOP"
RUN_LOG="$AUDIT_DIR/run.log"
WORKTREE_SH="$REPO_ROOT/.pi/scripts/worktree.sh"
LOOP_ENGINE="$REPO_ROOT/.pi/scripts/loop.sh"

AUDIT_END_TIME="${AUDIT_END_TIME:-04:00}"
AUDIT_MAX_ROUNDS="${AUDIT_MAX_ROUNDS:-7}"
AUDIT_ROUND_TIMEOUT_SECONDS="${AUDIT_ROUND_TIMEOUT_SECONDS:-1500}"
AUDIT_MIN_GAP_SECONDS="${AUDIT_MIN_GAP_SECONDS:-30}"
AUDIT_BRANCH="${AUDIT_BRANCH:-chore/nightly-audit-$(date +%Y-%m-%d)}"
AUDIT_WORKTREE="${AUDIT_WORKTREE:-$REPO_ROOT/../$(basename "$REPO_ROOT")-audit-$(date +%Y-%m-%d)}"

mkdir -p "$AUDIT_DIR"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$RUN_LOG"; }

ntfy() {
	# Same PI_NTFY_TOPIC/PI_NTFY_SERVER as .pi/extensions/notify.ts and
	# loop.sh's own pushes, for consistency - notify.ts itself is NOT
	# modified (docs/design.md §10.3).
	local title="$1" body="$2"
	[ -n "${PI_NTFY_TOPIC:-}" ] || return 0
	local server="${PI_NTFY_SERVER:-https://ntfy.sh}"; server="${server%/}"
	local url
	if [[ "$PI_NTFY_TOPIC" == http* ]]; then url="$PI_NTFY_TOPIC"; else url="$server/$PI_NTFY_TOPIC"; fi
	curl -fsS -X POST "$url" -H "Title: $title" -H "Tags: robot_face" -d "$body" >/dev/null 2>&1 || true
}

if ! git rev-parse --git-dir >/dev/null 2>&1; then
	log "ERROR: not a git repository, aborting."
	exit 1
fi

if [ -e "$AUDIT_WORKTREE" ]; then
	log "Reusing existing worktree at $AUDIT_WORKTREE (same-day rerun)."
else
	"$WORKTREE_SH" add "$AUDIT_WORKTREE" "$AUDIT_BRANCH" \
		|| { log "ERROR: could not set up worktree $AUDIT_WORKTREE for $AUDIT_BRANCH"; exit 1; }
fi

base_head="$(git -C "$AUDIT_WORKTREE" rev-parse HEAD)"

log "=== audit loop starting via loop.sh: branch=$AUDIT_BRANCH worktree=$AUDIT_WORKTREE end=$AUDIT_END_TIME max_rounds=$AUDIT_MAX_ROUNDS timeout=${AUDIT_ROUND_TIMEOUT_SECONDS}s ==="

"$LOOP_ENGINE" \
	--prompt "/audit" \
	--until "$AUDIT_END_TIME" \
	--max-rounds "$AUDIT_MAX_ROUNDS" \
	--round-timeout "$AUDIT_ROUND_TIMEOUT_SECONDS" \
	--interval "$AUDIT_MIN_GAP_SECONDS" \
	--label "audit" \
	--log "$RUN_LOG" \
	--stop-file "$STOP_FILE" \
	--cwd "$AUDIT_WORKTREE" \
	--precheck "cd '$AUDIT_WORKTREE' && [ -z \"\$(git status --porcelain)\" ]" \
	--post-round-check "cd '$AUDIT_WORKTREE' && [ -z \"\$(git status --porcelain)\" ]"
loop_exit=$?

commits_total="$(git -C "$REPO_ROOT" rev-list --count "$base_head..$AUDIT_BRANCH" 2>/dev/null || echo 0)"

if [ -n "$(git -C "$AUDIT_WORKTREE" status --porcelain)" ]; then
	log "=== audit loop finished dirty (see loop's post-round-check failure above) - NOT clean, inspect $AUDIT_WORKTREE by hand ==="
	ntfy "Audit loop finished DIRTY" "Working tree not clean in $AUDIT_WORKTREE on $AUDIT_BRANCH after the loop stopped. Inspect by hand before doing anything else — the worktree was deliberately left in place."
	exit 1
fi

"$WORKTREE_SH" remove "$AUDIT_WORKTREE" \
	|| log "WARNING: could not remove worktree $AUDIT_WORKTREE after a clean finish - remove it by hand."

log "=== audit loop finished: $commits_total total commit(s) on $AUDIT_BRANCH (loop exit $loop_exit) ==="
ntfy "Audit loop finished" "$commits_total commit(s) on $AUDIT_BRANCH. Review: git log $AUDIT_BRANCH"
