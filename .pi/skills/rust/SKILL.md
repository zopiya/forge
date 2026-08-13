---
name: rust
description: Rust patterns — ownership, errors, async boundaries, cargo defaults, and review checks
---

# Rust

Use this skill when planning, building, reviewing, or testing Rust code. Project
conventions win. If choosing a new crate, runtime, or version, verify current
official docs before deciding; this file is a fallback, not a source of latest
truth.

## Community Defaults

- `cargo fmt`, `cargo clippy`, and `cargo test` are the baseline.
- Use `Result<T, E>` for recoverable errors.
- Use `thiserror` for library/domain error enums when a typed error surface
  matters; use `anyhow` for application binaries or top-level orchestration when
  callers do not need to match error variants.
- Tokio is the common async runtime for network services, but use the runtime
  already present in the repo.

## Layout

See `.pi/skills/project-layout/SKILL.md` for the cross-cutting discipline;
Cargo itself dictates most of the Rust-specific idiom, so there's less
judgment involved here than in other ecosystems — follow it rather than
inventing a variant.

- `src/main.rs` for a binary, `src/lib.rs` for a library; a crate producing
  both has `src/lib.rs` plus a thin `src/main.rs` that depends on it.
- Multiple binaries: `src/bin/<name>.rs`, one file per binary.
- Unit tests inline in the module under test (`#[cfg(test)] mod tests`);
  `tests/` at crate root only for integration tests that exercise the crate
  through its public API as an external caller would.
- `benches/` for Criterion benchmarks, `examples/` for runnable example
  binaries — both optional, add only when they exist for real.
- Workspace: root `Cargo.toml` with `[workspace] members = ["crates/*"]` (or
  an explicit list), each member a full crate under `crates/<name>/` with
  its own `Cargo.toml` — same "only for genuinely independent units" rule
  as `.pi/skills/project-layout/SKILL.md`'s monorepo guidance.

## Decision Rules

- Ownership: prefer clear ownership flow over clever lifetimes. Clone only when
  data is small, infrequent, or explicitly cheaper than lifetime complexity.
- Error boundaries: typed errors at public/library boundaries; contextual errors
  at application edges.
- Async: do not block inside async tasks. Move CPU-heavy work to blocking pools
  or sync layers.
- Traits: introduce traits for real substitution or test seams, not for a single
  implementation.
- Serialization: keep wire/config types distinct from domain types when behavior
  or invariants differ.

## Boundary Checks

- Validate CLI args, config, file contents, network payloads, and FFI inputs.
- Mark traits/types `Send + Sync` only when values cross thread/task boundaries.
- Avoid global mutable state; if needed, use explicit synchronization and narrow
  scope.
- Avoid `unwrap`/`expect` in production paths unless the invariant is local and
  obvious.

## Toolchain Checks

Use repository commands first. Common fallbacks:

```bash
cargo test
cargo clippy -- -D warnings
cargo fmt --check
```

## Avoid

- Over-general trait layers before a second implementation exists.
- Hiding source errors behind string-only messages.
- Spawning detached tasks without cancellation or error reporting.
- Optimizing allocations before profiling or measuring.

## Review Checklist

- Error surfaces are appropriate for callers.
- Ownership is understandable without broad cloning or lifetime tricks.
- Async code has clear cancellation/error behavior.
- Tests cover changed behavior and failure paths.
