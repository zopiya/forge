#!/usr/bin/env bash
# .pi/audit/run.sh — audit-domain wrapper around .pi/scripts/pi-loop.sh.
#
# This file owns everything specific to "unattended overnight code audit":
# checking out a dedicated branch, refusing to start (or continue) on a
# dirty working tree, and the human-facing summary notification. The
# generic loop mechanics (time window, round cap, per-round timeout, STOP
# sentinel, per-round ntfy) all live in the domain-agnostic
# .pi/scripts/pi-loop.sh engine — this script has no while loop of its
# own, it only sets up audit-specific state and hooks into pi-loop.sh via
# --precheck/--post-round-check. See docs/design.md §10.3/§10.5.
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
PI_LOOP="$REPO_ROOT/.pi/scripts/pi-loop.sh"

AUDIT_END_TIME="${AUDIT_END_TIME:-04:00}"
AUDIT_MAX_ROUNDS="${AUDIT_MAX_ROUNDS:-7}"
AUDIT_ROUND_TIMEOUT_SECONDS="${AUDIT_ROUND_TIMEOUT_SECONDS:-1500}"
AUDIT_MIN_GAP_SECONDS="${AUDIT_MIN_GAP_SECONDS:-30}"
AUDIT_BRANCH="${AUDIT_BRANCH:-chore/nightly-audit-$(date +%Y-%m-%d)}"

mkdir -p "$AUDIT_DIR"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$RUN_LOG"; }

ntfy() {
	# Same PI_NTFY_TOPIC/PI_NTFY_SERVER as .pi/extensions/notify.ts and
	# pi-loop.sh's own pushes, for consistency - notify.ts itself is NOT
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

current_branch="$(git branch --show-current)"
if [ "$current_branch" != "$AUDIT_BRANCH" ]; then
	if git show-ref --verify --quiet "refs/heads/$AUDIT_BRANCH"; then
		git checkout "$AUDIT_BRANCH" || { log "ERROR: could not check out $AUDIT_BRANCH"; exit 1; }
	else
		git checkout -b "$AUDIT_BRANCH" || { log "ERROR: could not create $AUDIT_BRANCH"; exit 1; }
	fi
fi

base_head="$(git rev-parse HEAD)"

log "=== audit loop starting via pi-loop.sh: branch=$AUDIT_BRANCH end=$AUDIT_END_TIME max_rounds=$AUDIT_MAX_ROUNDS timeout=${AUDIT_ROUND_TIMEOUT_SECONDS}s ==="

"$PI_LOOP" \
	--prompt "/audit" \
	--until "$AUDIT_END_TIME" \
	--max-rounds "$AUDIT_MAX_ROUNDS" \
	--round-timeout "$AUDIT_ROUND_TIMEOUT_SECONDS" \
	--interval "$AUDIT_MIN_GAP_SECONDS" \
	--label "audit" \
	--log "$RUN_LOG" \
	--stop-file "$STOP_FILE" \
	--cwd "$REPO_ROOT" \
	--precheck "cd '$REPO_ROOT' && [ -z \"\$(git status --porcelain)\" ]" \
	--post-round-check "cd '$REPO_ROOT' && [ -z \"\$(git status --porcelain)\" ]"
loop_exit=$?

commits_total="$(git rev-list --count "$base_head..HEAD" 2>/dev/null || echo 0)"

if [ -n "$(git status --porcelain)" ]; then
	log "=== audit loop finished dirty (see pi-loop's post-round-check failure above) - NOT clean, inspect $AUDIT_BRANCH by hand ==="
	ntfy "Audit loop finished DIRTY" "Working tree not clean on $AUDIT_BRANCH after the loop stopped. Inspect by hand before doing anything else."
	exit 1
fi

log "=== audit loop finished: $commits_total total commit(s) on $AUDIT_BRANCH (pi-loop exit $loop_exit) ==="
ntfy "Audit loop finished" "$commits_total commit(s) on $AUDIT_BRANCH. Review: git log $AUDIT_BRANCH"
