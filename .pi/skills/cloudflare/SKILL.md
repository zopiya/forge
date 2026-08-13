---
name: cloudflare
description: Cloudflare Workers/Pages deployment via wrangler — config, bindings, secrets, and observability
---

# Cloudflare

Use this skill for Workers, Pages, and the storage/compute primitives that
sit behind them (D1, KV, R2, Durable Objects, Queues). `wrangler` is the CLI
for all of it — prefer it over the dashboard for anything reproducible.

## Core Commands

```bash
wrangler dev                    # local dev server, closest thing to prod
wrangler deploy [--dry-run]     # ship it — always dry-run first for anything risky
wrangler tail                   # live production logs
wrangler whoami                 # confirm which account you're about to touch
```

Run `wrangler whoami` before any `deploy` against an unfamiliar repo — a
misconfigured account context deploys to the wrong place silently.

## Config

`wrangler.toml` or `wrangler.jsonc` (jsonc preferred in newer projects — check
which one the repo actually has, don't assume). Things worth checking before
touching either:

- `compatibility_date` — bumping it can change runtime behavior; don't bump
  casually, only when a feature genuinely needs it.
- `[[env.*]]` blocks — most repos have separate `dev`/`staging`/`production`
  environments; confirm which one a command targets (`--env <name>`) before
  running it, especially `deploy`.
- Bindings (`kv_namespaces`, `d1_databases`, `r2_buckets`, `durable_objects`,
  `queues`) — each needs a matching resource to already exist; a binding in
  config with no real resource behind it fails at deploy or at runtime
  depending on the binding type.

## Secrets

```bash
wrangler secret put <NAME>          # prompts, doesn't take the value as an arg
wrangler secret list
```

Never put a real secret value in `wrangler.toml`/`.jsonc` or a command-line
argument (shell history, process list). Local dev secrets go in `.dev.vars`
(gitignored) — check it's actually gitignored before assuming it's safe to
put a real value there.

## D1 / KV / R2

```bash
wrangler d1 migrations create <db> <name>
wrangler d1 migrations apply <db> [--local|--remote]
wrangler d1 execute <db> --command "..." [--local|--remote]
wrangler kv key put --binding=<name> <key> <value>
wrangler r2 object put <bucket>/<key> --file <path>
```

- Default to `--local` for anything exploratory; `--remote` touches the real
  database/bucket.
- D1 migrations are forward-only in practice — review a migration file before
  applying it remotely, there's no built-in "undo."

## Observability

`wrangler tail` for live logs during a deploy or while reproducing an issue.
For anything that needs to persist past a terminal session, the dashboard's
Logs/Analytics Engine (if configured) is the durable option — `tail` is
ephemeral, streaming only.

## Safety Rules

- Confirm the target environment (`--env`, account via `whoami`) before any
  `deploy`, `d1 migrations apply --remote`, or `secret put` — these are the
  commands that touch production state.
- Dry-run (`wrangler deploy --dry-run`) for anything where you're not
  confident about the diff.
- Don't delete a KV namespace, D1 database, or R2 bucket without explicit
  confirmation — these commands don't have an undo, and the resource ID in
  config doesn't tell you what's actually stored in it.
- Treat `compatibility_flags` changes like a dependency bump — they can
  change behavior, not just unlock a feature.
