#!/usr/bin/env bash
# .pi/scripts/loop.sh — generic external loop driver for pi.
#
# Repeatedly invokes `pi -p "<prompt>"` as independent, one-shot,
# non-interactive processes until a stop condition is hit (time window,
# round cap, or a STOP sentinel file). Domain-agnostic on purpose: this
# script has zero opinion about what the prompt does, what state it
# touches, or what "done" means for the goal — it only owns the loop, the
# boundary conditions, and the log/notify plumbing around each round.
#
# Any goal-specific logic (git branches, dirty-tree checks, deciding
# whether a round's result was good) does NOT belong in here — plug it in
# via --precheck/--post-round-check instead, or drive the loop from a
# thin wrapper script that does its own setup and then calls this one.
# See .pi/audit/run.sh for exactly that pattern: a real wrapper built on
# top of this engine, entirely in the audit domain.
#
# Deliberately outside pi itself: extension factories must not start
# background resources/timers (see pi's extensions.md); this mirrors the
# existing subagent-dispatch subprocess model instead — a real separate
# `pi` process per round, scheduled by something outside pi. See
# docs/design.md §10.3/§10.5 for the full rationale.
#
# Usage:
#   loop.sh --prompt "<text>" --until 04:00 --max-rounds 7
#   loop.sh --prompt-file goal.txt --duration 3600 --interval 60
#
# At least one of --until / --duration / --max-rounds is required — an
# unbounded loop is refused by design, not a supported mode.
#
# Options:
#   --prompt TEXT              Prompt text passed to `pi -p` each round.
#   --prompt-file PATH         Read prompt text from a file instead of --prompt.
#   --until HH:MM               Stop once local clock time reaches this.
#   --duration SECONDS          Stop this many seconds after the loop starts.
#   --max-rounds N               Stop after this many rounds.
#   --round-timeout SECONDS     Per-round timeout (default 1500 = 25min).
#   --interval SECONDS          Sleep between rounds (default 30).
#   --label NAME                 Prefix for `pi --name` per round (default "loop").
#   --stop-file PATH             Kill-switch file (default: derived from --log).
#   --log FILE                   Operational log path (default: ./loop.log).
#   --cwd PATH                    Run `pi` from this directory (default: current dir).
#   --no-approve                  Don't pass --approve to pi (default: pass it — see
#                                  docs/security.md, headless modes otherwise silently
#                                  ignore .pi/ resources without a saved trust decision).
#   --pi-arg ARG                  Extra arg to pass through to `pi` (repeatable).
#   --precheck CMD                Run once before round 1 (via `bash -c`); non-zero exit
#                                  aborts before starting anything.
#   --post-round-check CMD        Run after every round (via `bash -c`); non-zero exit
#                                  stops the loop (fail closed) — the loop does not
#                                  interpret the command, it only checks its exit code.
#   --no-ntfy                     Suppress this script's own ntfy pushes even if
#                                  PI_NTFY_TOPIC is set (use when a wrapper wants to
#                                  own all notification content itself).
#
# Notifications: if PI_NTFY_TOPIC is set (and --no-ntfy wasn't passed), pushes a
# one-line ntfy.sh summary after every round and when the loop stops. Same env
# vars .pi/extensions/notify.ts uses: PI_NTFY_TOPIC / PI_NTFY_SERVER.
#
# Stop early: create the stop-file (any content) — checked before every round.

set -uo pipefail

PROMPT=""
PROMPT_FILE=""
UNTIL=""
DURATION=""
MAX_ROUNDS=""
ROUND_TIMEOUT=1500
INTERVAL=30
LABEL="loop"
STOP_FILE=""
LOG_FILE="./loop.log"
RUN_CWD="."
APPROVE=1
NTFY_ENABLED=1
PRECHECK=""
POST_ROUND_CHECK=""
PI_EXTRA_ARGS=()

usage() {
	sed -n '2,60p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
	case "$1" in
	--prompt) PROMPT="$2"; shift 2 ;;
	--prompt-file) PROMPT_FILE="$2"; shift 2 ;;
	--until) UNTIL="$2"; shift 2 ;;
	--duration) DURATION="$2"; shift 2 ;;
	--max-rounds) MAX_ROUNDS="$2"; shift 2 ;;
	--round-timeout) ROUND_TIMEOUT="$2"; shift 2 ;;
	--interval) INTERVAL="$2"; shift 2 ;;
	--label) LABEL="$2"; shift 2 ;;
	--stop-file) STOP_FILE="$2"; shift 2 ;;
	--log) LOG_FILE="$2"; shift 2 ;;
	--cwd) RUN_CWD="$2"; shift 2 ;;
	--no-approve) APPROVE=0; shift ;;
	--pi-arg) PI_EXTRA_ARGS+=("$2"); shift 2 ;;
	--precheck) PRECHECK="$2"; shift 2 ;;
	--post-round-check) POST_ROUND_CHECK="$2"; shift 2 ;;
	--no-ntfy) NTFY_ENABLED=0; shift ;;
	-h | --help) usage; exit 0 ;;
	*) echo "loop.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
	esac
done

if [ -n "$PROMPT" ] && [ -n "$PROMPT_FILE" ]; then
	echo "loop.sh: pass --prompt or --prompt-file, not both." >&2
	exit 2
fi
if [ -z "$PROMPT" ] && [ -z "$PROMPT_FILE" ]; then
	echo "loop.sh: --prompt or --prompt-file is required." >&2
	exit 2
fi
if [ -n "$PROMPT_FILE" ]; then
	[ -r "$PROMPT_FILE" ] || { echo "loop.sh: cannot read --prompt-file $PROMPT_FILE" >&2; exit 2; }
	PROMPT="$(cat "$PROMPT_FILE")"
fi
if [ -z "$UNTIL" ] && [ -z "$DURATION" ] && [ -z "$MAX_ROUNDS" ]; then
	echo "loop.sh: refusing to run unbounded — pass at least one of --until/--duration/--max-rounds." >&2
	exit 2
fi

[ -n "$STOP_FILE" ] || STOP_FILE="${LOG_FILE%.*}.stop"
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$STOP_FILE")"
touch "$LOG_FILE"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE"; }

ntfy() {
	[ "$NTFY_ENABLED" = "1" ] || return 0
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

past_until() {
	[ -n "$UNTIL" ] || return 1
	local now_epoch end_epoch
	now_epoch="$(date +%s)"
	end_epoch="$(date -j -f '%H:%M' "$UNTIL" +%s 2>/dev/null)"
	[ -z "$end_epoch" ] && end_epoch="$(date -d "$UNTIL" +%s 2>/dev/null)"  # GNU date fallback
	[ -n "$end_epoch" ] && [ "$now_epoch" -ge "$end_epoch" ]
}

past_duration() {
	[ -n "$DURATION" ] || return 1
	local elapsed=$(( $(date +%s) - LOOP_START_EPOCH ))
	[ "$elapsed" -ge "$DURATION" ]
}

past_max_rounds() {
	[ -n "$MAX_ROUNDS" ] || return 1
	[ "$round" -gt "$MAX_ROUNDS" ]
}

LOOP_START_EPOCH="$(date +%s)"

duration_display="none"
[ -n "$DURATION" ] && duration_display="${DURATION}s"

log "=== loop starting: label=$LABEL until=${UNTIL:-none} duration=$duration_display max_rounds=${MAX_ROUNDS:-none} round_timeout=${ROUND_TIMEOUT}s cwd=$RUN_CWD ==="

if [ -f "$STOP_FILE" ]; then
	log "STOP file present at start ($STOP_FILE) - exiting without running anything."
	exit 0
fi

if [ -n "$PRECHECK" ]; then
	if ! bash -c "$PRECHECK"; then
		log "ERROR: --precheck failed, refusing to start."
		ntfy "loop ($LABEL) aborted" "precheck failed before round 1."
		exit 1
	fi
fi

round=0
rounds_completed=0
while :; do
	round=$((round + 1))

	if [ -f "$STOP_FILE" ]; then log "STOP file appeared - stopping after $rounds_completed round(s)."; break; fi
	if past_max_rounds; then log "Reached max-rounds=$MAX_ROUNDS - stopping."; break; fi
	if past_until; then log "Reached until=$UNTIL - stopping before round $round."; break; fi
	if past_duration; then log "Reached duration=${DURATION}s - stopping before round $round."; break; fi

	log "--- round $round starting ---"
	round_start_epoch="$(date +%s)"
	output_file="$(mktemp "${TMPDIR:-/tmp}/loop-round-XXXXXX.txt")"

	pi_args=(--name "${LABEL}-r${round}-$(date +%Y%m%d-%H%M%S)")
	[ "$APPROVE" = "1" ] && pi_args+=(--approve)
	[ "${#PI_EXTRA_ARGS[@]}" -gt 0 ] && pi_args+=("${PI_EXTRA_ARGS[@]}")
	pi_args+=(-p "$PROMPT")

	( cd "$RUN_CWD" && run_with_timeout "$ROUND_TIMEOUT" pi "${pi_args[@]}" ) >"$output_file" 2>&1
	round_exit=$?
	round_seconds=$(( $(date +%s) - round_start_epoch ))
	tail_preview="$(tail -c 400 "$output_file" | tr '\n' ' ')"
	rounds_completed=$((rounds_completed + 1))

	log "round $round done: exit=$round_exit duration=${round_seconds}s"

	if [ -n "$POST_ROUND_CHECK" ]; then
		if ! bash -c "$POST_ROUND_CHECK"; then
			log "ERROR: --post-round-check failed after round $round - stopping (fail closed)."
			ntfy "loop ($LABEL) round $round: post-round-check failed, loop stopped" "$tail_preview"
			rm -f "$output_file"
			break
		fi
	fi

	if [ "$round_exit" -ne 0 ]; then
		ntfy "loop ($LABEL) round $round failed (exit $round_exit)" "$tail_preview"
	else
		ntfy "loop ($LABEL) round $round done" "$tail_preview"
	fi

	rm -f "$output_file"
	sleep "$INTERVAL"
done

log "=== loop finished: label=$LABEL rounds=$rounds_completed ==="
ntfy "loop ($LABEL) finished" "$rounds_completed round(s). See $LOG_FILE."
