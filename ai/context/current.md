# platforms-starter-kit — where this repository stands

The entry page for anyone (or any agent) picking this repository up. It is
this repository's own state and does not ship to a product built from it; the
two pages that do are [operations.md](operations.md) and
[deployment.md](deployment.md).

## What it is

Vercel's Platforms Starter Kit — a multi-tenant app, every tenant a subdomain
— on Cloudflare Workers + Static Assets (`@opennextjs/cloudflare`), its tenant
records in Workers KV behind a module that keeps the Upstash client's surface,
the namespace provisioned per environment by Terraform through Orun. Packaged
as an Orun baseline: `orun new --blueprint repo-blueprint.yaml` builds a new
product in its own repository and takes it to live on stage and prod in one
landing (`01-product`: cloudflare-kv → web per environment), then records
what went live (`02-docs`). Off the root domain a tenant is `/s/<tenant>`, so
a fresh product is whole on workers.dev before any custom domain.

## Release

| | |
|---|---|
| Latest tag | `baseline-v1` (PS4) |
| On `main` since | PS5 — the cirrus standard (no kiox, generated component docs, this context pack) |
| Proven live | No. Everything short of the platform is proven offline in Baseline CI; a live bootstrap from a tag, and tenant subdomains on a real zone, are still to come (risk PS-K) |

## Where to read

| Question | Page |
|---|---|
| What shipped, and every departure from upstream | `specs/epics/platforms-starter-kit/IMPLEMENTATION-STATUS.md` |
| Why it is built this way | [decisions.md](decisions.md), then `specs/epics/platforms-starter-kit/design.md` |
| What could still go wrong | [open-risks.md](open-risks.md), then `specs/epics/platforms-starter-kit/risks-and-open-questions.md` |
| How to instantiate it | `BOOTSTRAP.md`, `docs/phases/` |
| What each component is | `apps/web/docs/`, `infra/terraform/cloudflare-kv/docs/`, `tests/web/docs/` (generated; `python3 tooling/catalog/gen-component-docs.py`) |

## Next

1. Bootstrap one product from the next tag against a workspace, and record
   its timings (closes PS-K); then the registry row can leave `unlisted`.
2. Cut the next `baseline-vN` with `tag.yml` so the registry can pin PS5.
