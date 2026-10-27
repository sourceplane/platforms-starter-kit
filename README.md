# platforms-starter-kit

Vercel's [Platforms Starter Kit](https://github.com/vercel/platforms) — a
multi-tenant app where every tenant is a subdomain (`acme.yourdomain.com`),
created from a landing form with an emoji, listed and deleted from `/admin` —
running on **Cloudflare Workers + Static Assets** through
[`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare), with the
tenant records in a **Workers KV** namespace provisioned by Terraform through
[Orun](https://github.com/sourceplane/orun), and packaged as an **Orun
baseline**: one command takes a new product from nothing to live on stage
and prod, in its own repository, under its own name — in ONE landing.

The template's code is the code; the store is KV behind the Upstash client's
surface instead of Redis, and a tenant is served by path (`/s/<tenant>`) on
any host that is not its root domain, so a fresh deploy works on workers.dev
before a custom domain exists. What the baseline adds is everything needed
to make a copy of it somebody else's, built the way
[cirrus-baseline](https://github.com/sourceplane/cirrus-baseline) is since
its one-landing bootstrap. See
[`specs/epics/platforms-starter-kit`](specs/epics/platforms-starter-kit/README.md)
for the design, the milestones and the as-built status.

## Instantiating a product

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/platforms-starter-kit
cd platforms-starter-kit
orun new --blueprint repo-blueprint.yaml --out ~/sites/acme-tenants --run-hooks --resume \
  --set reponame=acme-tenants --set productname="Acme Tenants" \
  --set githuborg=acme-inc --set subdomain=<workers-dev-subdomain>
```

Or, once the platform's registry lists it, from the Orun console (Baselines →
`platforms-starter-kit` → Build). Two phases: **`01-product`** creates the
repository and lands the whole product as ONE pull request — intent, CI,
tooling, the KV root, the app and its tests — and one convergence applies
the KV namespace on stage and prod and then deploys the app with its id;
**`02-docs`** records the live deployment from probed facts.
**[BOOTSTRAP.md](BOOTSTRAP.md)** is the operator guide;
[docs/phases/](docs/phases/README.md) has a page per phase.

The new repository receives the **product only** — the app, its KV root, its
tests, its CI, its tooling, a README of its own and its operating contract —
renamed throughout to the product's name, repository, Cloudflare Worker,
namespace titles and root domain. None of this repository's machinery ships.

It goes live on workers.dev: the landing page, creating a tenant, the
tenant's page at `/s/<tenant>` and `/admin` all work there. Tenant
SUBDOMAINS need a root domain on a Cloudflare zone with a wildcard route to
the Worker — the owner's step after the bootstrap, described in the
product's README. The console does not ask for it: a product is born with
the reserved placeholder `<reponame>.example.com` as its root domain
(`BASE_DOMAIN`), and that step replaces it with the owner's.

| What makes it a baseline | Where |
|---|---|
| The console card (inputs, secrets, programme) | `blueprint.yaml` |
| The build document (modules, phases, hooks) | `repo-blueprint.yaml` |
| This tree's identity, and the bootstrap's task contracts | `.baseline/` |
| The rename engine | `tooling/rebrand/rebrand.mjs` |
| The bootstrap's helpers (deferrals, redeploy marker, work-tree strip) | `tooling/bootstrap/` |
| The deployment-record renderer | `hooks/render-deployment-docs.sh` |
| The product's README and context pack | `.baseline/product/README.md`, `ai/context/` |
| The baseline's tests: contract, wiring, leak, offline bootstrap, end to end | `testing/`, `.github/workflows/baseline.yml` |
| Cutting a `baseline-vN` tag | `.github/workflows/tag.yml` |

## What is here (the product)

| Surface | Where |
|---|---|
| Landing (create a tenant), `/admin`, the tenant page `/s/[subdomain]`, not-found | `apps/web/app` |
| The site's name | `apps/web/app/site.ts` |
| Subdomain routing (`<tenant>.<root>` → `/s/<tenant>`) | `apps/web/proxy.ts` |
| Where a tenant lives from a given host (subdomain on the root domain, `/s/<tenant>` elsewhere) | `apps/web/lib/addresses.ts` |
| Tenant store: the Upstash `redis` surface over Workers KV | `apps/web/lib/redis.ts`, `apps/web/lib/subdomains.ts` |
| Workers build, bindings and deploy contract | `apps/web/next.config.ts`, `open-next.config.ts`, `wrangler.template.jsonc` + `wiring.fixture.json` (→ the committed `wrangler.jsonc`), `component.yaml` |
| The KV namespace (stage, prod) | `infra/terraform/cloudflare-kv` |
| The wrangler renderer | `tooling/wire` |
| Tests | `tests/web` (vitest) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # render apps/web/wrangler.jsonc from the offline fixture
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # next build + opennextjs-cloudflare build → apps/web/.open-next
```

```bash
pnpm --filter @app/web dev        # http://localhost:3000, tenants at http://<tenant>.localhost:3000
pnpm --filter @app/web preview    # wrangler dev over the built Worker, tenants at /s/<tenant>
```

Both get a local KV namespace from wrangler, no account needed. The root
domain is `NEXT_PUBLIC_ROOT_DOMAIN` (`localhost:3000` when unset; see
`apps/web/.env.example`).

## How it maps to Vercel

| Vercel | Here |
|---|---|
| Next.js hosting, `proxy.ts` on the edge | One Cloudflare Worker (`.open-next/worker.js`) + Static Assets; the proxy runs in the Worker as a pure host-header rewrite |
| Upstash Redis (`@upstash/redis`, `KV_REST_API_URL` / `KV_REST_API_TOKEN`) | Workers KV: `lib/redis.ts` exports the same `redis.get / set / del / keys / mget` over the `KV` binding (`getCloudflareContext()`), same `subdomain:<name>` keys, same JSON records |
| Project env vars in the dashboard | `NEXT_PUBLIC_ROOT_DOMAIN` is set at build time by the Orun lane from the environment's `BASE_DOMAIN` in `intent.yaml` (inlined by `next build`) |
| A Redis database created by hand | `infra/terraform/cloudflare-kv`: one namespace per environment, its id published as a wiring document the deploy renders into `wrangler.jsonc` |
| Wildcard domain on Vercel (`*.yourdomain.com`) | A wildcard DNS record and a Worker route on a zone you own (the product README's "Tenant subdomains"); before it, `/s/<tenant>` on workers.dev |
| Deploy on push | Orun applies the namespace and deploys `<repo>-web-{stage,prod}` on merge to `main` (`apps/web/component.yaml`) |
| "Deploy with Vercel" (clone the template) | `orun new --blueprint repo-blueprint.yaml` — a new repository, branded, deployed |

There are no secrets: the KV namespace is a binding, and the template's
admin page has no authentication (upstream's `TODO`; Cloudflare Access in
front of `/admin` is the zero-code gate). `.dev.vars.example` is empty on
purpose.

## How the namespace id reaches the Worker

```
infra/terraform/cloudflare-kv ──apply──► orun secret WIRING_CLOUDFLARE_KV (stage, prod)
                                               │   (each deploy resolves it as it starts;
                                               │    a missing one fails the lane)
                                               ▼
apps/web  dependsOn cloudflare-kv (enforced on main) · secretEnv WIRING_CLOUDFLARE_KV_<ENV>
  build:  tooling/wire/live.mjs → wrangler.jsonc with the environment's namespace id
          (dev, verify-only, renders the fixture) → next build (BASE_DOMAIN) → opennextjs-cloudflare
```

`wrangler.jsonc` is committed as the fixture render of
`wrangler.template.jsonc`, because the deploy lane's `verify-app-structure`
step checks the config exists before it builds; `testing/e2e.test.sh` fails
if the two disagree.

## CI

| Workflow | What it runs | Ships to a product |
|---|---|---|
| `ci.yml` | the Orun pipeline, and the only workflow a product carries: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes (the KV root planned for stage and prod, the app built and dry-deployed per environment; no tests or lint — `baseline.yml`'s e2e tier runs those before each tag), except the bootstrap's own landings (`orun/BASE-*`), where `plan` alone runs and nothing waits for it (the landing checked its commit in the box); a merge applies the KV namespace, then deploys stage → prod. It plans nothing while `intent.yaml` names the placeholder workspace `ws_CHANGE_ME`, as this repository does. A manual run (Orunbase's Deploy button, or Run workflow on `main`) plans the environment and components it names under the push-to-main trigger, so they deploy as a merge deploys them | yes |
| `baseline.yml` | the baseline's own tiers: contract tests, the wiring path, the blueprint read by the pinned orun, the leak gate, the offline bootstrap with the product's own plan, the product built in the job tree, dry-deployed and served — a tenant created and read back through the Worker | no |
| `tag.yml` | cuts a `baseline-vN` tag (manual) | no |
