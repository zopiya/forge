---
name: typescript
description: TypeScript patterns — strict types, async boundaries, modules, toolchain defaults, and review checks
---

# TypeScript

Use this skill when planning, building, reviewing, or testing TypeScript code.
Project conventions win. If choosing a new framework, dependency, runtime, or
version, verify current official docs before deciding; this file is a fallback,
not a source of latest truth.

## Community Defaults

- TypeScript strict mode for production code.
- ESM-first modules unless the repo is already CommonJS.
- Runtime: use the repo runtime; otherwise prefer the active Node LTS for
  compatibility, or Bun only when the project already leans Bun.
- Package manager: follow lockfile/package metadata; otherwise npm for simple
  projects, pnpm for workspaces.
- Tests: Vitest for Vite/native ESM projects, Jest only when already established,
  Playwright for browser E2E.
- Formatting/linting: repo config first; otherwise Prettier + ESLint.

## Layout

See `.pi/skills/project-layout/SKILL.md` for the cross-cutting discipline;
this is the TypeScript-specific idiom it defers to.

- `src/` for all source; compiled output (`dist/`/`build/`) gitignored, never
  committed alongside source.
- `src/index.ts` as the package/app entrypoint when there is a single one.
- Tests: co-located `*.test.ts`/`*.spec.ts` next to the file under test, or a
  parallel `test/`/`__tests__/` tree mirroring `src/` — match whatever the
  repo already does, don't mix both styles in one project.
- Structure `src/` by feature (`src/orders/`, `src/users/`) over by layer
  (`src/{controllers,services,models}/`) once the app has more than a
  handful of files — layer-first flattens badly as it grows; feature-first
  keeps related files next to each other.
- CLI entrypoints referenced from `package.json`'s `bin` field live in `bin/`,
  not mixed into `src/`.
- Workspaces (pnpm/npm/yarn): `packages/<name>/`, each with its own `src/`
  and `package.json` — only once there are genuinely independent publishable
  units, see `.pi/skills/project-layout/SKILL.md`'s monorepo guidance.
- Cloudflare Workers projects: see `.pi/skills/cloudflare/SKILL.md` — the
  `wrangler.toml`/`.jsonc` config lives at the project root regardless of
  where `src/` conventions above put everything else.

## Decision Rules

- App framework: extend the existing framework. For greenfield, escalate to a
  planning pass (`.pi/agents/planner.md`, or think it through in-session for
  smaller cases) and compare options against product shape, deployment, team
  familiarity, and ecosystem maturity.
- Shared types: expose stable exported types only at module/API boundaries; keep
  internal helper types local.
- Runtime validation: TypeScript types do not validate external data. Use the
  repo's schema tool, or a small local validator for narrow inputs.
- Async flows: centralize retries, cancellation, and timeout behavior at I/O
  boundaries, not deep in pure functions.
- State/data fetching: follow existing app architecture; do not introduce a new
  state library for one feature.

## Boundary Checks

- Validate API, CLI, config, environment, file-system, and webhook inputs.
- Use `unknown` and narrow instead of `any`.
- Check optional/null values before access.
- Do not leak stack traces, tokens, or internal paths through errors.
- Keep request/response transport shapes separate from domain objects when the
  repo already has that separation.

## Toolchain Checks

Use repository commands first. Common fallbacks:

```bash
tsc --noEmit
eslint .
prettier --check .
vitest run
```

## Avoid

- Adding `any`, non-null assertions, or broad type casts to silence errors.
- Mixing ESM and CJS casually.
- Introducing framework-specific abstractions into domain logic.
- Changing public exports without compatibility review.

## Review Checklist

- Public exports and types remain backward compatible unless approved.
- Promise rejections and async boundary failures are handled.
- Validation exists where runtime data enters the system.
- Tests cover behavior and edge cases, not private implementation.
