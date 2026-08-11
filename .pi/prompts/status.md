---
description: Summarize progress across all in-progress .pi/work/ features
---

Scan `.pi/work/*/tasks.md` (and `spec.md` for context) across every feature directory.

For each in-progress feature, report:

- The feature slug and a one-line description (from `spec.md` if present).
- Task completion (N/M done).
- Anything blocked, per `clarifications.md` if unresolved items exist.

If `.pi/work/` has no feature directories, say so plainly — there's nothing in progress that needs `.pi/work/`.
