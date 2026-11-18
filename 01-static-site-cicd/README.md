# Containerized Static Site with CI/CD

A static website served by **Nginx in Docker**, validated and deployed automatically by **GitHub Actions** to **GitHub Pages**, with the same image published to GHCR for a VM.

```
push/PR ─► validate (HTML lint, Dockerfile lint, docker build, run container, smoke tests)
              └─ main only ─► deploy to GitHub Pages
                          └─► push image ghcr.io/<you>/<repo>:<sha> and :latest
```

## Run locally
```bash
docker compose up --build         # http://localhost:8080
./scripts/smoke-test.sh           # run checks against it
```

## One-time GitHub setup
1. Push this folder as its own repository (branch `main`).
2. **Settings → Pages → Build and deployment → Source: GitHub Actions**.
3. Push a change. The Actions tab shows validate → deploy; the URL appears on the deploy job.

## Deploy the image to a small VM (alternative to Pages)
```bash
docker run -d --name site --restart unless-stopped -p 80:8080 ghcr.io/<you>/<repo>:latest
```

## Rollback notes
Pick the fastest option that fits:

| Situation | Action | Time |
|---|---|---|
| Bad change just merged | `git revert <bad-sha> && git push` — pipeline validates and redeploys the previous content | ~2 min |
| Need the exact last-good version now | **Actions → ci-cd → Run workflow**, enter the last good commit SHA/tag in `ref` — it re-validates and redeploys that commit | ~2 min |
| Site runs on a VM | `docker pull ghcr.io/<you>/<repo>:<good-sha>` then `docker rm -f site && docker run -d --name site -p 80:8080 ghcr.io/<you>/<repo>:<good-sha>` | seconds |
| Pipeline itself is broken | Pages: **Settings → Pages**, redeploy an earlier successful run from the Actions tab (re-run deploy job) | ~1 min |

Never rewrite history on `main`; always revert so the audit trail stays intact. Every image is tagged with its commit SHA, so any past version can be re-run.

## Design notes
Unprivileged Nginx (non-root, port 8080) · read-only root filesystem in compose · security headers · `/healthz` endpoint + container HEALTHCHECK · deploy job only runs after validation passes.
