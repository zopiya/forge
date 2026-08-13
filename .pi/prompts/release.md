---
description: Cut a release — version bump, changelog, tag, GitHub release, and deploy if this project has one
argument-hint: "[patch|minor|major|<version>]"
---

Cut a release for this project. This chains together `.pi/skills/git/SKILL.md`,
`.pi/prompts/changelog.md`'s process, and whichever of `.pi/skills/github/`,
`.pi/skills/cloudflare/`, `.pi/skills/docker/`, `.pi/skills/ansible/` actually
applies — detect, don't assume. Confirm before any step in Deploy; the steps
before that (version bump, changelog, tag) are cheap/local until the tag and
release are pushed.

**1. Preconditions.**

- `git status --porcelain` must be empty — stop and say so if it isn't, don't
  release on top of uncommitted or unreviewed changes.
- Confirm the current branch is the one this project actually releases from
  (usually `main` after everything's merged — see `.pi/skills/git/SKILL.md`'s
  branch table; adapt if this repo does it differently). If it's a feature
  branch mid-review, stop and say so instead of releasing from it.
- Run whatever test/lint the project has (see the relevant `.pi/skills/<lang>/SKILL.md`
  Toolchain Checks) — don't release on a red build.

**2. Determine the version.**

- If $1 looks like an explicit version (e.g. `2.3.0`), use it.
- If $1 is `patch`/`minor`/`major`, apply that bump to the current version.
- If no argument was given, infer the bump from commits since the last tag
  using the same conventional-commit grouping `.pi/prompts/changelog.md` uses:
  any `BREAKING CHANGE`/`feat!` → major, else any `feat` → minor, else patch.
  Show your inference and the resulting version before proceeding — this is a
  judgment call, don't apply it silently.
- Find the current version from whatever the project actually uses
  (`package.json`, `Cargo.toml`, `pyproject.toml`, a `VERSION` file, or the
  latest `git tag`) — don't invent a versioning scheme the project doesn't
  already have. If there's genuinely no existing version anywhere, ask.

**3. Changelog.**

Follow `.pi/prompts/changelog.md`'s process for the range since the last tag,
using the new version as the header instead of `[Unreleased]`. Ask whether to
append to `CHANGELOG.md` (same as that template does) before writing it.

**4. Bump and commit.**

If the project has a version field (`package.json`, `Cargo.toml`,
`pyproject.toml`, ...), update it. Commit the version bump + changelog
together: `chore(release): vX.Y.Z` (see `.pi/skills/git/SKILL.md`'s commit
format). Show the diff before committing.

**5. Tag.**

```bash
git tag -a vX.Y.Z -m "vX.Y.Z"
```

Confirm the tag name matches whatever convention this repo's existing tags
already use (`git tag --sort=-version:refname | head -5`) — `v`-prefixed or
not, don't introduce a second convention.

**6. Push and GitHub release.**

This is the first step that's outward-facing — confirm before running it.

```bash
git push origin <branch> --follow-tags
gh release create vX.Y.Z --title "vX.Y.Z" --notes "<changelog entry for this version>"
```

See `.pi/skills/github/SKILL.md`. Mark `--prerelease` if the version has a
pre-release suffix (`-rc.1`, `-beta.1`, ...).

**7. Deploy — detect what this project actually is, don't assume.**

Confirm before running any of these; they touch real infrastructure.

- `wrangler.toml`/`wrangler.jsonc` present → this is a Cloudflare project.
  See `.pi/skills/cloudflare/SKILL.md`. Confirm the target environment
  (`--env`) and run `wrangler deploy --dry-run` first if there's any doubt
  about the diff, then `wrangler deploy` for real.
- `Dockerfile`/`docker-compose.yml` present → see `.pi/skills/docker/SKILL.md`.
  Build and tag the image against the new version (`docker build -t
  <image>:X.Y.Z .`); push to whatever registry the project already uses
  (check existing tags/CI config for the registry, don't invent one). Don't
  assume `docker compose up -d` on this machine is "the deploy" unless
  that's genuinely how this project ships.
- An `ansible/` directory or `*.yml` playbooks referencing `hosts:` present →
  see `.pi/skills/ansible/SKILL.md`. `--check --diff` first, always, then the
  real run scoped with `--limit` to what actually needs updating.
- None of the above → this is a library/package release, not a deployment.
  Stop after step 6 — don't invent a deploy step for a project that doesn't
  have one. If it publishes to a registry (npm, crates.io, PyPI), only do
  that if the project already has a publish workflow/script to follow; don't
  freehand `npm publish` against an unfamiliar package's registry settings.

**8. Report.**

One-line summary: version, changelog range, whether it was pushed/released,
whether anything was deployed and where.
