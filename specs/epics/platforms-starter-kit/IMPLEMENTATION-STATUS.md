# platforms-starter-kit (PS) — Implementation status

As-built ≠ intent. This file records what actually shipped, and every place
the code departed from `design.md` or from the upstream template.

| Milestone | State | PR |
|---|---|---|
| PS0 — the spec | ✅ Shipped | [#1](https://github.com/sourceplane/platforms-starter-kit/pull/1) |
| PS1 — the platform on Workers | ✅ Shipped | [#2](https://github.com/sourceplane/platforms-starter-kit/pull/2) |
| PS2 — the KV namespace from Terraform | ✅ Shipped | [#3](https://github.com/sourceplane/platforms-starter-kit/pull/3) |
| PS3 — ready to instantiate | ✅ Shipped | [#4](https://github.com/sourceplane/platforms-starter-kit/pull/4) |

## Departures from the upstream template

### `lib/redis.ts` is Workers KV behind the Upstash client's surface

Upstream: `new Redis({ url: KV_REST_API_URL, token: KV_REST_API_TOKEN })`
from `@upstash/redis`. Here: an object with `get / set / del / keys / mget`
over `getCloudflareContext().env.KV`, the same `subdomain:<name>` keys and
JSON records. `keys()` accepts only `<prefix>*` (KV lists by prefix) and
follows the list cursor; `mget` is `get` per key. `@upstash/redis` is gone
from the dependencies. `lib/subdomains.ts` and `app/actions.ts` are
byte-for-byte upstream.

### `export const dynamic = 'force-dynamic'` on `app/admin/page.tsx`

Upstream's admin page is rendered on demand only because every Upstash
command is a `cache: 'no-store'` fetch, which opts the route out of static
rendering. A KV binding is not a fetch, so without this line `next build`
would pre-render the page — with no binding, or with an empty list that
`revalidatePath` could never refresh through the read-only static-assets
cache. The build now reports `ƒ /admin`.

### Cloudflare Web Analytics instead of `@vercel/speed-insights`

`components/analytics.tsx` renders the beacon script when
`NEXT_PUBLIC_CF_BEACON_TOKEN` is set at build time; otherwise nothing.
`@vercel/speed-insights` and the unused `@vercel/analytics` are gone from
the dependencies; `app/layout.tsx` mounts `<CloudflareWebAnalytics />`
where `<SpeedInsights />` was.

### `extractSubdomain` is exported from `proxy.ts`

One word (`export`) so `tests/web` can exercise the routing decision as a
pure function. The body is upstream's, Vercel preview branch included.

### `NEXT_PUBLIC_ROOT_DOMAIN` is a build-time value, not a wrangler var

`next build` inlines it into the server, proxy and client bundles (a probe
build left no `process.env.NEXT_PUBLIC_ROOT_DOMAIN` read in `.next/server`),
so the component's `buildCommand` sets it from the environment's
`BASE_DOMAIN` in `intent.yaml` and `wrangler.template.jsonc` carries no
copy. Locally it is `.env.local` for `next dev` and the code's
`localhost:3000` default for `wrangler dev` over a plain build. The Upstash
`KV_REST_API_*` variables the template read no longer exist.

### `next.config.ts`

`output: "standalone"` + `outputFileTracingRoot` (what `@opennextjs/cloudflare`
bundles), and `initOpenNextCloudflareForDev()` so `next dev` reaches the KV
binding declared in the rendered `wrangler.jsonc`. The upstream comment
block about Vercel Speed Insights headers went with the script.

### The monorepo wrapper

`package.json` is `@app/web` with the Workers build script; `next` is
pinned to `16.3.8` (below, Versions); `@cloudflare/workers-types` and
`wrangler` are dev dependencies; `cloudflare-env.d.ts` declares
`CloudflareEnv.KV`; `eslint.config.mjs` is the workspace's shared config
(upstream ships no lint setup). `tests/web/tsconfig.json` turns
`noUncheckedIndexedAccess` off because it compiles upstream's `proxy.ts`,
which indexes `split()` results.

### `.gitignore`: `!.dev.vars.example`

The skeleton's `.dev.vars.*` pattern swallowed the committed example; the
negation keeps it tracked while every real `.dev.vars` stays ignored.

### The KV root's wiring keys

The factory's copy of the baseline root emitted `app_kv_kv_id` /
`app_kv_kv_title` (a doubled `kv` from the rename of the baseline's
idempotency namespace). This repository's root emits `app_kv_id` /
`app_kv_title`, the names `wrangler.template.jsonc` and `wiring.fixture.json`
use, and its comments and locals speak of the tenant store.

## Verified

- Local: `pnpm run wire:fixture`, `pnpm typecheck`, `pnpm lint` (two
  upstream `any` warnings, no errors), `pnpm test` (19 tests: the adapter
  over a fake namespace with cursor paging, `lib/subdomains.ts`,
  `extractSubdomain`, the proxy's rewrite and redirect, `cn`), `pnpm build`
  green (`○ /`, `○ /_not-found`, `ƒ /admin`, `ƒ /s/[subdomain]`, proxy
  bundled as Node.js middleware).
- `wrangler dev` over `.open-next/worker.js` with a local KV: `/` 200
  (landing), `Host: nope.localhost:3000` 404 (not-found page), `/admin` 200,
  `/admin` on a tenant host 307 → `/`, CSS chunk 200. The create flow
  driven in a browser (the emoji picker and the form need JavaScript; a
  no-JS POST to the static landing page is served from the prerender cache)
  wrote `subdomain:acme`, after which `Host: acme.localhost:3000` is 200
  with the emoji, `/s/acme` is 200 and `/admin` lists it; delete from
  `/admin` emptied the namespace and the tenant host is 404 again, with
  `revalidatePath('/admin')` a silent no-op.
- `terraform init -backend=false && terraform validate` green on
  `infra/terraform/cloudflare-kv` (cloudflare 4.52.9, external 2.4.2).
- CI: `Checks` green on #2 and #3 (install, wire, typecheck, lint, test,
  build).
- Not verified: the KV apply and a live deploy, which need the product
  linked to an Orun workspace with a Cloudflare connection, and tenant
  hostnames on a real zone (a wildcard record and a Worker route).

## Versions

| Package | Version | Why |
|---|---|---|
| next | 16.3.8 | newest inside `@opennextjs/cloudflare` 1.20.11's peer range; 16.4.x fails at worker boot (`preview-props.json` manifest) |
| @opennextjs/cloudflare | ^1.20.11 | static-assets incremental cache + `populateCache local`; `initOpenNextCloudflareForDev` |
| wrangler | ^4.151.0 | compatibility_date 2026-10-01; local KV for `wrangler dev` |
| @cloudflare/workers-types | ^5.20261014.1 | `KVNamespace` for `CloudflareEnv.KV` (the 4.x line is no longer published) |
