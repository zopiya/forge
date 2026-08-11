---
name: python
description: Python patterns — typing, validation, async boundaries, errors, toolchain defaults, and review checks
---

# Python

Use this skill when planning, building, reviewing, or testing Python code.
Project conventions win. If choosing a new framework, dependency, runtime, or
version, verify current official docs before deciding; this file is a fallback,
not a source of latest truth.

## Community Defaults

- Python 3.11+ when the project does not declare a lower target.
- `uv` for environment/package workflows only when the repo has no established
  toolchain.
- Ruff for lint/format when no formatter is configured.
- pytest for tests.
- Pydantic for structured boundary validation when the project already uses it
  or when the boundary is substantial enough to justify it.

## Decision Rules

- Web/API: follow the existing framework. For greenfield APIs, compare FastAPI
  against Django/Flask based on admin needs, async needs, ecosystem, and team
  familiarity.
- Data models: prefer typed dataclasses or Pydantic models at boundaries; avoid
  passing unstructured dicts through core logic.
- Async: use async for I/O-heavy paths; isolate blocking calls behind explicit
  adapters or executors.
- Errors: raise specific exceptions with actionable context; convert to user/API
  errors only at the boundary.
- Configuration: parse env/config once at startup or entrypoint, then pass typed
  config inward.

## Boundary Checks

- Validate user input, API payloads, CLI args, config, env vars, and file
  contents.
- Never use bare `except`; log or re-raise caught exceptions.
- Avoid mutable defaults; prefer `None` plus initialization or `default_factory`.
- Do not expose secrets, stack traces, SQL, or internal file paths in user-facing
  errors.

## Toolchain Checks

Use repository commands first. Common fallbacks:

```bash
uv run pytest
ruff check .
ruff format --check .
basedpyright
```

## Avoid

- Framework introduction for a one-file utility.
- Silent exception swallowing.
- Untyped public APIs in new code.
- Mixing sync and async database/client calls in the same path without a clear
  adapter.

## Review Checklist

- Public functions and classes have useful annotations.
- Boundary validation is explicit and localized.
- Error messages are actionable but do not leak internals.
- Tests cover happy path, error path, and important boundary cases.
