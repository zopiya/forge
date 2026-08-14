#!/usr/bin/env bash
# .github/scripts/check-frontmatter.sh — cheap structural checks for
# .pi/prompts/*.md and .pi/skills/*/SKILL.md, run from CI (see
# .github/workflows/lint.yml). Not a full YAML parser — these files use a
# simple flat key: value frontmatter block, a handful of grep checks is
# enough to catch the mistakes that actually happen (missing frontmatter,
# missing required key, or the {{arg}} placeholder bug from
# .pi/design.md §10 regressing).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

fail=0

check_frontmatter() {
	local file="$1"; shift
	local required_keys=("$@")

	if [ "$(sed -n '1p' "$file")" != "---" ]; then
		echo "FAIL: $file does not start with a --- frontmatter block"
		fail=1
		return
	fi

	local closing_line
	closing_line="$(awk 'NR>1 && /^---$/ {print NR; exit}' "$file")"
	if [ -z "$closing_line" ]; then
		echo "FAIL: $file has an opening --- but no closing --- for frontmatter"
		fail=1
		return
	fi

	local frontmatter
	frontmatter="$(sed -n "2,$((closing_line - 1))p" "$file")"

	for key in "${required_keys[@]}"; do
		if ! grep -qE "^${key}:" <<<"$frontmatter"; then
			echo "FAIL: $file frontmatter is missing required key '$key:'"
			fail=1
		fi
	done
}

# Prompt templates: require `description`. `argument-hint` is optional (only
# templates that take an argument need it) so not checked here.
if compgen -G ".pi/prompts/*.md" >/dev/null; then
	for f in .pi/prompts/*.md; do
		check_frontmatter "$f" description
	done
fi

# Skills: require both `name` and `description` per pi's skills.md spec.
if compgen -G ".pi/skills/*/SKILL.md" >/dev/null; then
	for f in .pi/skills/*/SKILL.md; do
		check_frontmatter "$f" name description
	done
fi

# Regression guard for .pi/design.md §10: {{arg}}-style placeholders are
# never substituted by pi's real $1/${1:-default}/$ARGUMENTS engine — they
# silently reach the model as literal text. Fail loudly instead of quietly
# reintroducing that bug in a new or edited prompt template.
if compgen -G ".pi/prompts/*.md" >/dev/null; then
	hits="$(grep -ln '{{[a-zA-Z_]*}}' .pi/prompts/*.md || true)"
	if [ -n "$hits" ]; then
		echo "FAIL: non-functional {{arg}} placeholder(s) found (pi does not substitute these, use \$1/\${1:-default}/\$ARGUMENTS instead — see .pi/design.md §10):"
		echo "$hits"
		fail=1
	fi
fi

if [ "$fail" -eq 0 ]; then
	echo "All prompt/skill frontmatter checks passed."
fi

exit "$fail"
