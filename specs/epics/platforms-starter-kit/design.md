# platforms-starter-kit — design

## 1. What the template is

Next.js App Router, one Worker's worth of app. `proxy.ts` (Next 16's
middleware) reads the `Host` header: on `<tenant>.<root>` it rewrites `/` to
`/s/<tenant>` and sends `/admin` back to `/`; on the root domain it does
nothing. `app/page.tsx` is the landing page with `subdomain-form.tsx`
(name + emoji, `frimousse` picker) posting to the `createSubdomainAction`
server action, which validates, writes `subdomain:<name>` →
`{ emoji, createdAt }` and redirects to the new tenant.
`app/s/[subdomain]/page.tsx` reads the record and renders the tenant page
or `notFound()`; `app/not-found.tsx` names the missing tenant from the
hostname. `app/admin` lists every tenant (`keys('subdomain:*')` + `mget`)
and deletes with `deleteSubdomainAction` + `revalidatePath('/admin')`.
`lib/redis.ts` is `new Redis({ url: KV_REST_API_URL, token: KV_REST_API_TOKEN })`
from `@upstash/redis`; `lib/utils.ts` exports `rootDomain`
(`NEXT_PUBLIC_ROOT_DOMAIN`, default `localhost:3000`) and `protocol`.
shadcn/ui, Tailwind 4, Geist, Vercel Speed Insights.

## 2. The mapping (Vercel → Cloudflare)

| Vercel primitive the template uses | Here |
|---|---|
| Next.js hosting (SSR pages, server actions, the proxy) | Cloudflare Workers + Static Assets; the Worker is `@opennextjs/cloudflare`'s output, assets bound as `ASSETS` |
| `proxy.ts` on the edge | Runs inside the same Worker (OpenNext bundles it as the middleware function). It never touched Redis upstream, so it stays a pure host-header rewrite; the record is read in the page, where `getCloudflareContext()` is ordinary request-time code |
| Upstash Redis through `@upstash/redis` (`KV_REST_API_URL`, `KV_REST_API_TOKEN`) | Workers KV, bound as `KV`. `lib/redis.ts` exports `redis` with the client's surface (§3) over `getCloudflareContext().env.KV`; same keys, same JSON records; `lib/subdomains.ts` and `app/actions.ts` are untouched |
| `*.yourdomain.com` wildcard domain on the Vercel project | A zone in the Cloudflare account with a wildcard DNS record and a Worker route (`*.example.com/*`), or Cloudflare for SaaS custom hostnames with the Worker as fallback origin. `workers.dev` hostnames cannot carry a tenant subdomain. Documented in the README; not provisioned here |
| `NEXT_PUBLIC_ROOT_DOMAIN` in the project's env | One knob: the environment's `env.BASE_DOMAIN` in `intent.yaml`. The component's `buildCommand` exports it as `NEXT_PUBLIC_ROOT_DOMAIN`; `next build` inlines it into the server, proxy and client bundles (verified: no `process.env` read survives), so no wrangler var is carried |
| `/admin` rendered on demand because every Upstash command is a `cache: 'no-store'` fetch | `export const dynamic = 'force-dynamic'` on the page: a KV binding is not a fetch, and the tenant list must never be baked in at build time |
| `@vercel/speed-insights` | `components/analytics.tsx`: the Cloudflare Web Analytics beacon, rendered only when `NEXT_PUBLIC_CF_BEACON_TOKEN` is set (the portfolio port's swap) |
| An Upstash database created from the Vercel marketplace | `infra/terraform/cloudflare-kv`: one namespace per environment, id and title published as the `WIRING_CLOUDFLARE_KV` document |
| Deploy on push | Orun: `apps/web/component.yaml` (`cloudflare-workers-assets-turbo`) deploys `platforms-starter-kit-web-{stage,prod}` on merge to `main` once the product is linked |

Secrets: none. The namespace is a binding, the admin page has no
authentication (upstream's `TODO`), and the Upstash URL/token the template
read from env no longer exist. `.dev.vars.example` says so.

## 3. The KV adapter contract (`lib/redis.ts`)

The module exports `redis`, an object with exactly the commands the
template calls, typed the way `@upstash/redis` types them:

| Command | Upstash | Over KV |
|---|---|---|
| `get<T>(key): Promise<T \| null>` | GET, JSON-decoded | `KV.get(key, 'json')` |
| `set<T>(key, value): Promise<'OK'>` | SET, JSON-encoded | `KV.put(key, JSON.stringify(value))` |
| `del(...keys): Promise<number>` | DEL | `KV.delete` each; returns the count asked for |
| `keys(pattern): Promise<string[]>` | KEYS with a glob | `KV.list({ prefix })` following `cursor` until `list_complete`; the pattern must be `<prefix>*` (the template's is `subdomain:*`), anything else throws |
| `mget<T[]>(...keys): Promise<(T \| null)[]>` | MGET | `get` for each key, order preserved |

The binding is read lazily inside each call, never at import: the module
is imported by server-action modules that client components reference,
and `getCloudflareContext()` is a request-time call. A missing binding
throws a message that names the fix (`pnpm run wire:fixture`).

What changes semantically: KV is eventually consistent across locations
(a write is visible to reads at the same location at once, elsewhere
within about a minute), where Redis was strongly consistent. The
template's one write-then-read — create, then redirect to the tenant page
— lands at the same location. See risks PS-B.

## 4. The env and wiring flow

```
infra/terraform/cloudflare-kv  ──apply──►  orun secrets (project/<env> rung)
   outputs: app_kv_id, app_kv_title,          WIRING_CLOUDFLARE_KV = {app_kv_id, app_kv_title}
            wiring                                     │
apps/web/component.yaml secretEnv ◄────────────────────┘
   WIRING_CLOUDFLARE_KV_<ENV>  → tooling/wire/live.mjs → wrangler.jsonc kv_namespaces[KV].id

intent.yaml environments.<env>.env.BASE_DOMAIN
   → buildCommand: NEXT_PUBLIC_ROOT_DOMAIN="${BASE_DOMAIN}" → next build (inlined everywhere)
```

`wrangler.template.jsonc` carries `@@wiring(cloudflare-kv/__ENV__:app_kv_id)@@`.
The verify lane (and `pnpm run wire:fixture`) renders it from
`wiring.fixture.json`; the deploy lane renders it from the live document
for `$ORUN_ENVIRONMENT`. The rendered `wrangler.jsonc` is git-ignored.
`wrangler dev` binds a local namespace whatever the id says, so the fixture
render is also the local development config; `initOpenNextCloudflareForDev()`
in `next.config.ts` gives `next dev` the same binding through wrangler's
platform proxy.

## 5. The repository

```
apps/web                      the template (app/, components/, lib/, proxy.ts) + the Workers build
  lib/redis.ts                the Upstash surface over the KV binding (§3)
  cloudflare-env.d.ts         CloudflareEnv.KV for getCloudflareContext()
  component.yaml              render wrangler from the KV wiring, build with the env's root domain, deploy, smoke /
  wrangler.template.jsonc     worker name, nodejs_compat, ASSETS, the KV binding as a wiring token
  wiring.fixture.json         offline namespace ids for the verify lane and local dev
  open-next.config.ts         static-assets incremental cache; nothing pre-rendered revalidates
infra/terraform/cloudflare-kv the namespace per environment (the baseline's root), wiring {app_kv_id, app_kv_title}
tests/web                     vitest: the adapter over a fake namespace, lib/subdomains.ts, extractSubdomain and proxy, cn
```

## 6. The build

`pnpm --filter @app/web build` = `next build` (standalone, traced from the
monorepo root) → `opennextjs-cloudflare build --skipBuild` (the Next 16
`proxy.ts` bundles as Node.js middleware) → `opennextjs-cloudflare
populateCache local` (the landing page's prerender into the assets bundle).
`/` and `/_not-found` are static; `/admin` and `/s/[subdomain]` render on
demand against KV. `revalidatePath('/admin')` in the delete action lands on
a dynamic route and is a no-op under OpenNext's default tag cache — so the
static-assets incremental cache (read-only, nothing to provision) is enough,
and the R2 cache + tag cache a revalidating template would need is not
pulled in.

## 7. Out of scope

Authentication on `/admin` (upstream's `TODO`), the zone and its wildcard
record and route (the baseline's `cloudflare-domain` root is the shape),
Cloudflare for SaaS custom hostnames, per-tenant content beyond the emoji,
and Vercel preview deployments (the `tenant---branch.vercel.app` branch of
`extractSubdomain` stays as written and is simply never true here).

## 8. The rejected alternative: a Durable Object per tenant

A Durable Object per tenant (`idFromName(subdomain)`) would give strongly
consistent reads and writes and a natural home for per-tenant state. It
was rejected because the template's store is not per-tenant state: it is
one map with a prefix scan (`keys('subdomain:*')`) feeding an admin list,
and a DO has no cross-object listing — the admin page would need a second
index (a registry DO or KV anyway) and the adapter would stop being a drop-in
for the Upstash client. KV is the Cloudflare primitive that *is* a
key-value map with prefix listing, it is what the Cirrus baseline already
provisions and wires, and its one semantic difference (eventual consistency
across locations) does not touch the template's flows. A port that grows
per-tenant data with transactions is where a DO belongs.
