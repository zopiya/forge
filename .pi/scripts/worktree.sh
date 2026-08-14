#!/usr/bin/env bash
# .pi/scripts/worktree.sh — small, reusable git-worktree mechanism.
#
# git worktree is a core, repeatedly-used concept in Forge (Race mode,
# isolated audit/loop runs, general "inspect a branch without disturbing
# local changes"), but the raw `git worktree` commands carry real gotchas
# (remove takes exactly one path per call, leftover build artifacts make
# plain remove refuse, merged vs unmerged branches need -d vs -D). This
# script is the one place those gotchas are encoded so every consumer —
# an interactive pi session running Race mode, or an external wrapper like
# .pi/audit/run.sh driving .pi/scripts/loop.sh — calls the same thing
# instead of each re-deriving the commands by hand. See
# .pi/skills/worktree/SKILL.md for the reference knowledge (when to use a
# worktree, naming convention) and docs/design.md §14 for the rationale.
#
# This deliberately does NOT judge whether a dirty worktree is safe to
# force-remove (e.g. "just __pycache__" vs real uncommitted work) — that
# judgment stays with the caller, consistent with Forge's container-first,
# no-silent-guardrails stance (docs/design.md §3.1/§3.4). It only reports
# the dirty state clearly and requires an explicit --force to proceed.
#
# Usage:
#   worktree.sh add <path> <branch> [<start-point>]
#   worktree.sh remove <path> [--force] [--delete-branch]
#   worktree.sh list

set -uo pipefail

usage() {
	sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

cmd="${1:-}"
[ -n "$cmd" ] && shift || true

case "$cmd" in
add)
	path="${1:-}"; branch="${2:-}"; start_point="${3:-}"
	if [ -z "$path" ] || [ -z "$branch" ]; then
		echo "worktree.sh add: usage: worktree.sh add <path> <branch> [<start-point>]" >&2
		exit 2
	fi
	if [ -e "$path" ]; then
		echo "worktree.sh add: path already exists: $path (refusing to overwrite)" >&2
		exit 1
	fi
	if git show-ref --verify --quiet "refs/heads/$branch"; then
		# Branch already exists (e.g. a same-day rerun resuming yesterday's
		# work) — attach the worktree to it instead of trying to recreate it.
		git worktree add "$path" "$branch"
	elif [ -n "$start_point" ]; then
		git worktree add "$path" -b "$branch" "$start_point"
	else
		git worktree add "$path" -b "$branch"
	fi
	;;

remove)
	path="${1:-}"; shift || true
	force=0
	delete_branch=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--force) force=1; shift ;;
		--delete-branch) delete_branch=1; shift ;;
		*) echo "worktree.sh remove: unknown argument: $1" >&2; exit 2 ;;
		esac
	done
	if [ -z "$path" ]; then
		echo "worktree.sh remove: usage: worktree.sh remove <path> [--force] [--delete-branch]" >&2
		exit 2
	fi
	if [ ! -e "$path" ]; then
		echo "worktree.sh remove: no such path: $path" >&2
		exit 1
	fi

	branch=""
	[ "$delete_branch" = "1" ] && branch="$(git -C "$path" branch --show-current)"

	if [ "$force" != "1" ]; then
		status="$(git -C "$path" status --porcelain)"
		if [ -n "$status" ]; then
			echo "worktree.sh remove: $path is not clean, refusing without --force:" >&2
			echo "$status" >&2
			echo "Confirm any listed files are just build/test byproducts before re-running with --force — see .pi/skills/worktree/SKILL.md." >&2
			exit 1
		fi
		git worktree remove "$path"
	else
		git worktree remove --force "$path"
	fi

	if [ "$delete_branch" = "1" ] && [ -n "$branch" ]; then
		if git branch --merged | grep -qx "  $branch\|\* $branch"; then
			git branch -d "$branch"
		else
			git branch -D "$branch"
		fi
	fi
	;;

list)
	git worktree list
	;;

-h | --help | "")
	usage
	exit 0
	;;

*)
	echo "worktree.sh: unknown command: $cmd" >&2
	usage >&2
	exit 2
	;;
esac
