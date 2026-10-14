# platforms-starter-kit

Vercel's [Platforms Starter Kit](https://github.com/vercel/platforms) — a
multi-tenant app where every tenant is a subdomain (`acme.yourdomain.com`),
created from a landing form with an emoji, listed and deleted from `/admin` —
running on **Cloudflare Workers + Static Assets** through
[`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare), with the
tenant records in **Workers KV** instead of Upstash Redis, inside the
repository conventions of the
[Cirrus baseline](https://github.com/sourceplane/cirrus-baseline): an
[Orun](https://github.com/sourceplane/orun) intent, one component per
deployable, a credential-free check lane as the merge gate, an Orun lane
that turns on once the product is linked to a workspace, and the KV
namespace provisioned by Terraform through Orun.

The template's code is the code. What the port adds is the Workers build,
the monorepo wrapper, a KV-backed `lib/redis.ts` with the Upstash client's
surface, a test package, the KV Terraform root and the deploy contract that
binds the namespace per environment. See
[`specs/epics/platforms-starter-kit`](specs/epics/platforms-starter-kit/README.md)
for the design, the milestones and the as-built status.

## What is here

| Surface | Where |
|---|---|
| Landing (create a subdomain), `/admin`, the tenant page `/s/[subdomain]`, not-found | `apps/web/app` |
| Subdomain routing (`<tenant>.<root>` → `/s/<tenant>`) | `apps/web/proxy.ts` |
| Tenant store: the Upstash `redis` surface over Workers KV | `apps/web/lib/redis.ts`, `apps/web/lib/subdomains.ts` |
| Workers build and deploy contract | `apps/web/next.config.ts`, `apps/web/open-next.config.ts`, `apps/web/wrangler.template.jsonc`, `apps/web/component.yaml` |
| The KV namespace (stage, prod) | `infra/terraform/cloudflare-kv` |
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

Run it locally — both paths get a local KV namespace from wrangler, no
account needed:

```bash
pnpm --filter @app/web dev        # http://localhost:3000, Next's dev server (KV through initOpenNextCloudflareForDev)
pnpm --filter @app/web preview    # wrangler dev over the built Worker
```

Create a tenant on the landing page, then open `http://<tenant>.localhost:3000`
(browsers resolve `*.localhost` to the loopback address); `/admin` lists and
deletes tenants. The root domain is `NEXT_PUBLIC_ROOT_DOMAIN`
(`localhost:3000` when unset; see `apps/web/.env.example`).

## How it maps to Vercel

| Vercel | Here |
|---|---|
| Next.js hosting, `proxy.ts` on the edge | One Cloudflare Worker (`.open-next/worker.js`) + Static Assets; the proxy runs in the Worker as a pure host-header rewrite |
| Upstash Redis (`@upstash/redis`, `KV_REST_API_URL` / `KV_REST_API_TOKEN`) | Workers KV: `lib/redis.ts` exports the same `redis.get / set / del / keys / mget` over the `KV` binding (`getCloudflareContext()`), same `subdomain:<name>` keys, same JSON records |
| Project env vars in the dashboard | `NEXT_PUBLIC_ROOT_DOMAIN` is set at build time by the Orun lane from the environment's `BASE_DOMAIN` in `intent.yaml` (inlined by `next build`) |
| A Redis database created by hand | `infra/terraform/cloudflare-kv`: one namespace per environment, its id published as a wiring document the deploy renders into `wrangler.jsonc` |
| Wildcard domain on Vercel (`*.yourdomain.com`) | A wildcard DNS record and a Worker route (or Cloudflare for SaaS custom hostnames) on a zone you own — see below |
| Deploy on push | Orun deploys `platforms-starter-kit-web-{stage,prod}` on merge to `main` (`apps/web/component.yaml`) |

There are no secrets: the KV namespace is a binding, and the template's
admin page has no authentication (upstream's `TODO`). `.dev.vars.example`
is empty on purpose.

## The wildcard domain

Tenants live at `<tenant>.<NEXT_PUBLIC_ROOT_DOMAIN>`. A `workers.dev`
hostname cannot carry that (`acme.platforms-starter-kit-web-prod.<sub>.workers.dev`
does not resolve), so a deployed environment needs a zone in the Cloudflare
account:

1. Set the environment's `env.BASE_DOMAIN` in `intent.yaml` to the root
   domain tenants hang off (`example.com` for prod, `stage.example.com` for
   stage). The build inlines it as `NEXT_PUBLIC_ROOT_DOMAIN`.
2. On that zone, add a wildcard DNS record (`*.example.com`, proxied) and a
   Workers route `*.example.com/*` (plus `example.com/*`) pointing at the
   environment's Worker — or, for customer-owned domains, Cloudflare for
   SaaS custom hostnames with the Worker as the fallback origin.

Provisioning the zone, the records and the route is out of scope here
(the baseline's `cloudflare-domain` root is the shape when it is wanted).

## Deploying

`.github/workflows/checks.yml` runs install, wire, typecheck, lint, test and
build on every push and pull request. `ci.yml` is the Orun pipeline: set
`execution.state.workspace` in `intent.yaml` to this product's workspace
(`orun cloud link`), connect a Cloudflare account to that workspace, and set
the `ORUN_CI` repository variable to `true`. A merge to `main` then applies
the KV root, builds the app with that environment's root domain, renders
`wrangler.jsonc` with the namespace id from the root's wiring document, and
deploys the Worker to `stage`, then `prod`.
