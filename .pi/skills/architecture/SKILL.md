---
name: architecture
description: Architecture planning patterns — boundaries, trade-offs, interfaces, risks, validation, and ADR triggers
---

# Architecture

Use this skill for non-trivial design, refactor, public interface, dependency,
or system-boundary decisions. Start with the repository shape; do not wrap a
small task in ceremony.

## Decision Priorities

1. Correctness and safety at external/persistent boundaries.
2. Simplicity and local consistency.
3. Evolvability for known near-term changes.
4. Performance where measured or explicitly required.
5. Operational cost and failure visibility.

## Community Defaults

- Modular monolith before service extraction unless team/deploy/scale boundaries
  are already real.
- Explicit adapters at I/O boundaries: database, HTTP clients, queues, files,
  model providers, and CLIs.
- Typed contracts for public APIs, persisted schemas, and cross-module
  interfaces.
- Observability at boundaries: structured errors/logs and enough context to
  debug without exposing secrets.

## Planning Checklist

- Identify the source of truth: config, schema, API, command, or owning module.
- Name the user-visible behavior and the internal boundary it touches.
- Reuse an existing pattern unless it is already causing the problem.
- Compare at most 2-3 viable approaches with concrete trade-offs.
- State non-goals and compatibility constraints.
- Split implementation into independently reviewable tasks.

## ADR-Level Triggers

Use ADR-style detail for:

- Public API, persisted data, or auth/permission model changes.
- New dependency, framework, runtime, or storage choice.
- Cross-team/cross-module contracts.
- Security, privacy, deployment, or rollback constraints.

## Avoid

- Adding abstraction before a second implementation or clear change pressure.
- Replacing local consistency with generic best practices.
- Solving hypothetical scale while current correctness is unclear.
- Designing without an acceptance test or validation path.

## Validation

- Define acceptance criteria before implementation tasks.
- Use focused tests for changed behavior and broader checks for shared
  contracts.
- Include rollback or mitigation notes for release, infrastructure, or persisted
  data changes.
