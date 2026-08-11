---
name: shell
description: Shell patterns — safety, quoting, portability, command validation, destructive operations, and review checks
---

# Shell

Use this skill for shell scripts, command review, CI snippets, and CLI
automation. Prefer the shell already used by the file.

## Safety Baseline

For Bash scripts:

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
```

For POSIX `sh`, do not use arrays, `[[ ... ]]`, process substitution, or Bash
string operators.

## Community Defaults

- `shellcheck` for lint.
- `shfmt` for formatting when the repo uses it.
- `mktemp` for temporary files/directories.
- `trap` for cleanup.
- `command -v` for dependency checks.

## Rules

- Quote variable references: `"$var"`.
- Use arrays for argument lists in Bash.
- Use `--` before user-controlled path arguments when supported.
- Validate paths before destructive operations.
- Prefer explicit loops over unsafe glob expansion for user-controlled files.
- Avoid `eval`, remote shell pipes, and unbounded globs.

## Destructive Command Checks

- Scope the target path and print/confirm what will be removed or overwritten.
- Reject empty variables used in paths.
- Avoid recursive delete unless explicitly required.
- Prefer dry-run or `git clean -n` style preview when available.

## Review Checklist

- Inputs are validated before use in paths or commands.
- Temporary resources are cleaned up.
- Exit codes are meaningful.
- Script behavior matches the declared shell.
