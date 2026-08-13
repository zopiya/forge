---
name: docker
description: Docker and Compose — Dockerfile conventions, multi-container setups, and safe cleanup
---

# Docker

Use this skill for Dockerfiles, Compose setups, and container debugging.
Compose is covered here too — it's a thin orchestration layer over the same
images/containers, not a separate tool with its own conventions.

## Dockerfile Conventions

- Multi-stage builds: build in one stage with the full toolchain, copy only
  the built artifact into a minimal final stage (`FROM node:20 AS build` →
  `FROM node:20-slim`, or a `-alpine`/`distroless` final image where the
  runtime allows it).
- Pin base image versions (`node:20.11-slim`, not `node:latest`) — `latest`
  makes builds non-reproducible and can break silently on rebuild.
- Order layers from least to most frequently changing (deps install before
  source copy) so the dependency layer stays cached across rebuilds.
- Run as a non-root user in the final image unless there's a concrete reason
  not to (`USER node`, or a dedicated `useradd` in the base if none exists).
- `.dockerignore` mirrors `.gitignore` intent — exclude `node_modules/`,
  `.git/`, build artifacts, and anything secret-bearing (`.env*`) from the
  build context.
- `HEALTHCHECK` for anything Compose or an orchestrator needs to know is
  actually ready, not just running.

## Compose

```bash
docker compose up [-d] [--build]
docker compose down [-v]           # -v also removes named volumes — data loss
docker compose logs -f [service]
docker compose exec <service> <cmd>
docker compose config              # resolved config — catches interpolation bugs
```

- `depends_on` controls start order, not readiness — pair it with
  `healthcheck` + `condition: service_healthy` if a service genuinely needs
  to wait for another to be ready, not just started.
- Env vars: `.env` at the compose file's directory is loaded automatically;
  don't assume a variable is set without checking it's actually defined
  somewhere in scope (shell env, `.env`, or `environment:` block).
- `docker compose config` before debugging a "why isn't this working" —
  it shows the fully resolved config after variable interpolation, which
  catches typos in `${VAR}` references immediately.

## Debugging

```bash
docker logs [-f] <container>
docker exec -it <container> <shell>
docker inspect <container>          # full config/state as JSON
docker ps -a                        # include stopped containers
```

## Cleanup

```bash
docker image prune [-a]             # -a also removes unused (not just dangling) images
docker volume prune                 # removes volumes not attached to any container
docker system prune [-a --volumes]  # broadest — confirm scope before running
```

Named volumes hold real data (databases, uploads) — `prune` commands only
touch volumes with no attached container, but confirm what's actually in a
volume before removing it if there's any doubt, especially in a shared/staging
environment.

## Safety Rules

- Never bake secrets into an image layer (`ENV`, `ARG` without
  `--build-arg` at build time only, or a `COPY`'d credentials file) — anyone
  with the image can extract them from any layer, even a later layer that
  deletes the file.
- Confirm before `docker compose down -v` or any `prune --volumes` — these
  are the commands that actually lose data, not just stop containers.
- Don't run `--privileged` or bind-mount the Docker socket
  (`-v /var/run/docker.sock:...`) unless the task genuinely requires
  container-managing-containers; both hand the container root-equivalent
  access to the host.
- Pin versions in both `Dockerfile` base images and `docker-compose.yml`
  image tags — floating tags make "works on my machine" failures common.
