---
name: paradigms
description: Programming paradigm guidance — imperative, functional, OOP, concurrency, domain boundaries, and anti-patterns
---

# Programming Paradigms

Use this skill when choosing how to organize code. Do not use it as permission
to refactor working code outside the task.

## Selection Heuristics

- Imperative: ordered side effects, scripts, system boundaries, retries,
  migrations, and orchestration.
- Functional: collection/data transformations, pure calculations, immutable
  value flows, and pipeline-style logic.
- Object-oriented: identity, lifecycle, polymorphism, long-lived collaborators,
  and stateful domain concepts.
- Traits/interfaces/protocols: real substitution boundaries, plugin points,
  adapters, and tests where fake implementations represent external systems.
- Domain layering: complex business rules, multiple delivery mechanisms, or
  persistence-independent invariants.

## Combination Rules

- Keep side effects at the edges; keep core decisions as pure as practical.
- Prefer composition over inheritance unless the language/framework expects
  inheritance.
- Use dependency injection for external systems, not for every helper function.
- Separate commands that mutate state from queries when the workflow or data
  model benefits from that clarity.

## Avoid

- Introducing a paradigm shift inside a small bug fix.
- Wrapping one implementation behind a new abstraction without a second real use
  case or a boundary worth isolating.
- Mixing concurrency models in the same flow without an adapter.
- Turning a simple data structure into a class hierarchy for aesthetics.

## Review Questions

- Does this organization reduce change risk today?
- Are side effects isolated at clear boundaries?
- Is the abstraction easier to test than the concrete code it replaces?
- Can the next change be made locally, or did the design spread responsibility?
