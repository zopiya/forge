---
name: api
description: API design checks — resource shape, contracts, errors, pagination, compatibility, and review risks
---

# API Design

Use this skill for public interfaces, HTTP APIs, RPC boundaries, webhooks, and
structured request/response contracts. Existing API style wins. If changing a
public contract or choosing a new protocol/version, escalate to a planning
pass (`.pi/agents/planner.md`) before locking the decision.

## Community Defaults

- REST for resource-oriented CRUD and simple integrations.
- RPC/gRPC for internal high-throughput service calls with strongly typed
  contracts.
- GraphQL only when clients genuinely need flexible selection across related
  data and the project can support schema governance.
- Webhooks for external event notifications; queues/streams for internal async
  workflows.

## Resource Shape

- Use nouns, not verbs: `/users`, `/projects/{id}/members`.
- Keep request and response envelopes consistent within the existing API.
- Use stable IDs and explicit timestamps when records are persisted.
- Make pagination, filtering, sorting, and idempotency explicit when present.
- Keep internal domain objects separate from transport DTOs when invariants
  differ.

## Status and Error Guide

| Code | Use |
|------|-----|
| 200 | Successful read/update |
| 201 | Created |
| 204 | Deleted/no response body |
| 400 | Bad request syntax |
| 401 | Unauthenticated |
| 403 | Authenticated but unauthorized |
| 404 | Not found |
| 409 | Conflict |
| 422 | Validation error |
| 429 | Rate limited |

Errors should include a stable machine-readable code and a human-readable
message. Field-level validation errors should identify the failing field.

## Compatibility Rules

- Safe: adding optional response fields, new endpoints, new enum values only if
  clients tolerate unknown values.
- Risky: changing default pagination, error shape, auth behavior, or sorting.
- Breaking: removing/renaming fields, changing types, changing required inputs,
  changing status semantics.

## Avoid

- Returning raw stack traces, SQL, secrets, internal paths, or provider errors.
- Hiding auth failures behind misleading 404/400 behavior unless the API already
  has that security convention.
- Adding versioning or envelope schemes inconsistent with the existing API.

## Review Checklist

- Inputs are validated at the boundary.
- Error response shape is consistent and safe.
- Backward compatibility impact is named.
- Idempotency and retries are considered for create/update/webhook endpoints.
