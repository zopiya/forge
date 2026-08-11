---
name: test
description: Testing strategy — focused validation, regression tests, integration scope, doubles, and acceptance reporting
---

# Testing

Use this skill when choosing validation scope or reviewing test coverage.
Existing repo test style wins.

## Scope Decision

- Tiny docs/config change: static checks may be enough.
- Small local behavior change: focused unit or integration test.
- Bug fix: add or identify a regression test that would have failed before the
  fix when practical.
- Shared contract/public API: contract or integration coverage plus focused
  regression cases.
- UI workflow: component tests for behavior, E2E only for critical user paths.
- Data migration/release change: dry run, fixture, rollback, or smoke validation.

## Test Shape

- Test behavior and externally visible outcomes, not private implementation.
- Cover happy path, relevant error path, and boundary cases.
- Keep fixtures explicit; do not depend on ambient database state.
- Use real dependencies for your own persistence/integration layer when the repo
  already supports it.
- Use mocks for external services, time, randomness, network, and expensive or
  flaky dependencies.

## Community Defaults

- Python: pytest.
- TypeScript: Vitest/Jest according to repo; Playwright for browser E2E.
- Rust: cargo test, optionally nextest if already configured.
- Shell: shellcheck plus command-level smoke tests where possible.

## Avoid

- Snapshot-only coverage for meaningful logic.
- Mocking the code under test instead of its external dependencies.
- Broad suites when a focused command validates the changed surface.
- Marking validation as passed when setup failed.

## Validation Report

Always report:

- Command run.
- Result.
- Relevant failures or skipped checks.
- Residual risk if no automated test exists.
