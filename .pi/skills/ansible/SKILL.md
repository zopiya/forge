---
name: ansible
description: Ansible playbook/deployment conventions — idempotency, dry-run, inventory scoping, and vault
---

# Ansible

Use this skill for playbooks, roles, and inventory-driven deployment/config
management. The core discipline is idempotency — a playbook run twice should
converge to the same state, not double-apply changes.

## Core Commands

```bash
ansible-playbook <playbook>.yml --check --diff     # dry run, always do this first
ansible-playbook <playbook>.yml --limit <host/group>
ansible-playbook <playbook>.yml --tags <tag>
ansible-playbook <playbook>.yml -i <inventory>
ansible <host/group> -m ping                        # connectivity check
ansible-inventory -i <inventory> --list              # resolved inventory, catches group typos
```

- `--check --diff` first for anything touching a real target — `--check`
  simulates without applying, `--diff` shows what would change. Not every
  module supports check mode (notably ones that shell out); treat those as
  higher-risk and read the task before running for real.
- `--limit` scopes a run to specific hosts/groups — use it to test against
  one node before fleet-wide, especially for a new or edited playbook.
- `--tags`/`--skip-tags` for partial runs (e.g. `--tags deploy` to skip a
  slow `setup` block already known-good).

## Idempotency

- Prefer declarative modules (`ansible.builtin.copy`, `template`, `package`,
  `service`, `user`, ...) over `shell`/`command` — declarative modules check
  current state before acting and report `changed: false` when nothing needed
  to happen; `shell`/`command` run unconditionally every time unless you add
  your own `creates`/`removes`/`when` guard.
- If `shell`/`command` is genuinely necessary (no module covers it), add
  `creates:`/`removes:` or a `when:` condition based on a preceding check
  task — otherwise every run re-executes it and the diff/check output stops
  being trustworthy.
- Avoid tasks whose result depends on run order across unrelated hosts —
  each host's play should converge independently.

## Inventory & Variables

- Confirm which inventory file/dynamic source (`-i`) a run is actually using
  before running anything against a group like `production` or `all` — a
  wrong `-i` silently targets the wrong fleet.
- Group/host variable precedence gets confusing fast (`group_vars/all` →
  `group_vars/<group>` → `host_vars/<host>` → play vars → `-e` on the CLI,
  roughly least to most specific) — when a variable isn't taking the value
  you expect, check for a more specific override before assuming the task
  itself is wrong.

## Vault (Secrets)

```bash
ansible-vault encrypt <file>
ansible-vault edit <file>
ansible-playbook <playbook>.yml --ask-vault-pass
ansible-playbook <playbook>.yml --vault-password-file <path>
```

Never commit an unencrypted secret "temporarily" — `ansible-vault encrypt`
before the first commit, not after. `--vault-password-file` pointed at a
gitignored file is the non-interactive form for automation; confirm the
file is actually gitignored before relying on it.

## Safety Rules

- `--check --diff` (and ideally `--limit` to one host) before any run against
  a group that includes production — no exceptions for "small" changes,
  small changes are exactly the ones that get run without checking.
- Read what a role/playbook actually does before running it against
  real infrastructure if it came from somewhere other than this session —
  a role can run arbitrary shell tasks with no indication from its name.
- Don't widen `--limit`/target group beyond what the task asked for — a
  playbook that's correct for one host isn't automatically safe to fleet-wide
  without a `--check` pass at the wider scope first.
- Treat any task using `shell`/`command`/`raw` against production as
  higher-risk than a declarative module doing the same thing — read it twice.
