# platforms-starter-kit (PS) — Implementation status

As-built ≠ intent. This file records what actually shipped, and every place
the code departed from `design.md` or from the upstream template.

| Milestone | State | PR |
|---|---|---|
| PS0 — the spec | ✅ Shipped | [#1](https://github.com/sourceplane/platforms-starter-kit/pull/1) |
| PS1 — the platform on Workers | ✅ Shipped | [#2](https://github.com/sourceplane/platforms-starter-kit/pull/2) |
| PS2 — the KV namespace from Terraform | ✅ Shipped | [#3](https://github.com/sourceplane/platforms-starter-kit/pull/3) |
| PS3 — ready to instantiate | ✅ Shipped | [#4](https://github.com/sourceplane/platforms-starter-kit/pull/4) |
| PS4 — a baseline, in one landing | ✅ Shipped (offline-proven; no live bootstrap yet, risk PS-K) | [#5](https://github.com/sourceplane/platforms-starter-kit/pull/5) (PS-5), tagged `baseline-v1` |
| PS5 — the cirrus standard | ✅ Shipped | [#6](https://github.com/sourceplane/platforms-starter-kit/pull/6) (PS-6), [#7](https://github.com/sourceplane/platforms-starter-kit/pull/7) (PS-7), tagged `baseline-v2` |

## Departures from the upstream template

### `lib/redis.ts` is Workers KV behind the Upstash client's surface

Upstream: `new Redis({ url: KV_REST_API_URL, token: KV_REST_API_TOKEN })`
from `@upstash/redis`. Here: an object with `get / set / del / keys / mget`
over `getCloudflareContext().env.KV`, the same `subdomain:<name>` keys and
JSON records. `keys()` accepts only `<prefix>*` (KV lists by prefix) and
follows the list cursor; `mget` is `get` per key. `@upstash/redis` is gone
from the dependencies. `lib/subdomains.ts` is byte-for-byte upstream, and
so was `app/actions.ts` until PS4 changed its redirect target (below).

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

### Off the root domain a tenant is `/s/<tenant>` on the request's host (PS4)

Upstream links, redirects to and names every tenant as
`<tenant>.<NEXT_PUBLIC_ROOT_DOMAIN>`. A deploy with no custom domain answers
on workers.dev, where that host does not resolve: the form created a tenant
and redirected nowhere. `lib/addresses.ts` (new) decides per request from the
`Host`: on the root domain, upstream's subdomain; anywhere else, `/s/<tenant>`
on the same host. `createSubdomainAction` redirects with it; `/admin`, the
tenant page and the not-found page link with it; the landing form shows a
`/s/` prefix and the full address off the root domain, plus a line saying
subdomains wait for the domain's wildcard route; the tenant page's heading
and title name the address it was reached at. `app/page.tsx` reads the host,
so `/` renders per request (`ƒ /`, was `○ /`). `proxy.ts`,
`lib/subdomains.ts` and `lib/redis.ts` are unchanged.

### `app/not-found.tsx` reads `/s/<tenant>`, not `/subdomain/<tenant>` (PS4)

Upstream's not-found page looked for a tenant name under `/subdomain/`, a
path the template no longer has; under `/s/` it now names the missing
tenant, and its link goes to this host's `/` off the root domain.

### The site's name comes from `app/site.ts` (PS4)

`SITE_NAME` is the `<title>` (was the literal "Platforms Starter Kit") and a
label above the landing page's heading (new; the heading stays the
domain — or, off it, the host). It is the one seam the product's rename
rewrites.

### `apps/web/README.md` is the app's, not the template's (PS4)

The upstream README advertised Upstash, `KV_REST_API_*` and "Deploy on
Vercel", and it ships into every product.

## Departures from the port (PS4)

| What | Before | After | Why |
|---|---|---|---|
| tenant links off the root domain | `<tenant>.<root>` everywhere (unreachable on workers.dev) | `/s/<tenant>` on the request's host (`lib/addresses.ts`) | a fresh deploy has no custom domain (risk PS-D) |
| `apps/web/wrangler.jsonc` | git-ignored, rendered by the build | committed as the fixture render, GENERATED banner; Checks diffs it | the deploy lane checks it exists before the build (risk PS-I) |
| dev's render | `live.mjs --env dev` → no document → red | `--fixture wiring.fixture.json --fixture-envs dev`; the fixture has a `dev` entry | dev is verify-only; no root applies there (PS-J) |
| `apps/web` → `cloudflare-kv` | `dependsOn` in the default mode | `mode: enforced`, `modeRules` advisory on `github-pull-request` | the one landing's order on main; a PR deploys nothing (cirrus-baseline v22's shape) |
| `apps/web` smoke | `grep 'Create your own subdomain…'` (a static prerender passed it) | `/` names `<host>/s/` for the host asked on, and `/admin` answers | only a Worker rendering per request, and reading its KV, passes |
| stage's `BASE_DOMAIN` | the product domain, as prod | `stage.<domain>` | stage and prod never claim the same tenant hostnames once routed |
| `ci.yml` gate | `vars.ORUN_CI == 'true'` | skip only while `intent.yaml` names `ws_CHANGE_ME` | a bootstrap cannot set a repository variable |
| `checks.yml` | push to main + PRs | PRs + `workflow_dispatch` | `orun.run/watch@v1` takes the newest run on the merge sha from ANY workflow |
| stack-tectonic | 0.18.2 | 0.19.0 | first-deploy retry and smoke backoff; not 0.20.0, whose lane-scoped install Next 16's Turbopack refuses |
| orun lane pin | v2.78.0 | v2.78.4 | cirrus-baseline's and the sibling baselines' pin |
| `packages/` | absent — `orun plan` failed: `failed to access discovery root packages` | `packages/.gitkeep` | the discovery roots are required |
| `intent.yaml` docs pages | `specs/epics/…` | `ai/context/*` | the pages must exist in a product |
| the KV root's title comment | "unique to this fork … shares an account with the baseline" | per product slug | it ships into every product |
| `tooling/wire/render.mjs` | copied the template's header comment | writes a GENERATED banner | the committed render must say it is one |
| `tasks/PS-1..4` | no `metadata` | `metadata.name` and `title` | `orun work check` (≥ v2.79) refused them |

## The cirrus standard (PS5)

Nothing about the product changed. What changed is the baseline around it:

| What | Before | After | Why |
|---|---|---|---|
| orun pin | `kiox.yaml` (v2.15.0) + `kiox.lock`, shipped to every product | gone; orun is pinned where it runs, the `orun-action` `version:` in each workflow | nothing ran the kiox pin, and it disagreed with the lanes (v2.78.4) |
| `root-kiox`, `root-kiox-lock` modules | in `01-product` | removed (`testing/phases.test.sh` and the rebrand's skip list follow) | a product is placed with 84 − 2 + 9 = 91 files: no kiox, plus the docs below |
| component docs | none | `apps/web/docs/`, `infra/terraform/cloudflare-kv/docs/`, `tests/web/docs/` — `overview.md`, `architecture.md`, `runbook.md` | cirrus-baseline documents every component; the workspace Docs library renders `docs/` beside each `component.yaml` |
| how the docs stay true | — | `tooling/catalog/gen-component-docs.py` derives them from the manifest, the Worker config, Terraform, migrations and package scripts; Baseline CI runs it with `--check` | a hand-written copy of a manifest drifts silently |
| context pack | `operations.md`, `deployment.md` | plus `current.md`, `decisions.md`, `open-risks.md` | cirrus-baseline's shape; the three new pages are this repository's own and no module places them (the leak gate still allows exactly two) |
| status | PS4 "this PR (PS-5), to be tagged `baseline-v1`"; the epic README's "Shipped as" at #4 | PS4 shipped and tagged `baseline-v1` | the tag existed; the documents had not caught up |

### The subdomain from the Cloudflare connection (PS-7)

`subdomain` — the account's workers.dev subdomain, not a tenant's — was the
one input an operator typed that the platform could answer itself: it belongs
to the Cloudflare account the same way its id does, and it has exactly one
right answer. A typed one could only be wrong, and wrong showed up after
deploy — in the deploy's smoke (its `DEPLOYED_URL`), the phase probes and the
console's verify URLs. `blueprint.yaml` now declares
`from: connection.cloudflare.workersSubdomain`, as cirrus-baseline does since
baseline-v23: the Cloudflare integration reads the subdomain at connect and on
its hourly health check, and the bootstrap door fills the input from the
connection the build is bound to — the same one `CLOUDFLARE_ACCOUNT_ID` and the
deploy tokens mint from. The console renders no field for it, and an account
with no workers.dev subdomain is refused at the door with the fix named.

- `testing/manifest.test.sh` takes cirrus-baseline's rule verbatim: the source
  is accepted, and only when `spec.requires.integrations` lists its provider.
- `repo-blueprint.yaml` keeps the input and its default; it, `BOOTSTRAP.md`
  and `docs/phases/README.md` say only a hand-run build passes
  `--set subdomain`.
- Nothing a product carries changes: the rename writes the value where it
  always did (`workersDevSubdomain`, the URLs), and the probes read it as
  before.

Verified:

- `testing/{manifest,phases,coverage,rebrand,retouch,bootstrap-defer,wire}.test.sh`
  green; `gen-component-docs.py --check` green (3 components).
- Mutation: with `cloudflare` dropped from `spec.requires.integrations`,
  `manifest.test.sh` fails with exactly one finding, naming
  `inputs[subdomain]`; restored, it passes.
- `orun new --status` (v2.58.11): `01-product` pending, 91 files.
  `testing/leak.test.sh` (v2.58.11): 91 files derived; 85 shipped sources name
  no factory path. `testing/placement.test.sh` (v2.78.4, as `baseline.yml`
  runs it): 91 tracked files, both landings; the product's own plan applies
  `cloudflare-kv` (level 0) before it deploys `web` (level 1) on stage and
  prod; the 02-docs merge plans 0 jobs; `--resume` changes nothing.
- `orun task check PS-7` complete.

## Verified (PS5)

- `testing/{manifest,phases,coverage,rebrand,retouch,bootstrap-defer,wire}.test.sh`
  green; `gen-component-docs.py --check` green (3 components, 9 pages).
- `testing/leak.test.sh` (v2.58.11): 91 files derived (84 − 2 kiox + 9 docs
  pages); 85 shipped sources name no factory path; ai/context still exactly
  the two declared pages.
- `testing/placement.test.sh` (v2.78.4, as `baseline.yml` runs it): 91
  tracked files, both landings, branded, re-tenanted; the product's own
  `orun plan` for the 01-product merge applies `cloudflare-kv` (level 0)
  before it deploys `web` (level 1) on stage and prod; a pull request's plan
  waits on nothing; the 02-docs merge plans 0 jobs; `--resume` changes
  nothing.
- `pnpm install --frozen-lockfile`, `wire:fixture` (the committed config is
  its render), `typecheck`, `lint` (upstream's two `any` warnings), `test`
  (28 tests, 6 files), `build` green.
- `testing/e2e.test.sh` (v2.78.4) green: the stage lane's planned steps in a
  staged job tree, `wrangler dev` over the built Worker, the component's own
  smoke, and a tenant created, read back by path, by `/admin` and by Host
  header, and deleted.
- `terraform fmt -check`, `init -backend=false` and `validate` (1.15.3) on
  `infra/terraform/cloudflare-kv` green.
- `orun task check PS-6` complete.

## Verified (PS4)

- `orun new --status` reads the blueprint at v2.58.11 (the bootstrap floor),
  v2.78.4 (the lane pin) and v2.79.0: `01-product` 84 files, `02-docs`
  hook-only. `orun validate` and `orun work check` clean (1 epic, 5
  contracts).
- `pnpm install --frozen-lockfile`, `wire:fixture` (the committed config is
  its render), typecheck, lint (upstream's two `any` warnings), test (28
  tests, 6 files: + `lib/addresses.ts`, `app/site.ts`), build (`ƒ /`,
  `○ /_not-found`, `ƒ /admin`, `ƒ /s/[subdomain]`).
- `testing/{manifest,phases,coverage,rebrand,retouch,bootstrap-defer,wire}.test.sh`
  green.
- `testing/leak.test.sh` (v2.79.0 and v2.58.11): 84 files derived; nothing
  of the factory, nothing local or built, no provenance prose; 78 shipped
  sources name no factory path.
- `testing/placement.test.sh` (fixture "Sam's Tenants & Co" /
  `acme-inc/acme-platforms`, root domain `tenants.acme.dev`): two landings;
  rebrand `--verify` clean; the app, the Worker, the KV titles, the root
  domains (`tenants.acme.dev`, `stage.tenants.acme.dev`) and every secret
  ref the product's; no file names a factory path; workspace re-tenanted,
  `work:` stripped, promotion and dev lanes restored; record rendered. The
  product's own `orun plan --trigger github-push-main` for the 01-product
  merge: `cloudflare-kv.{stage,prod}.terraform` (apply) at lane level 0,
  `web.{stage,prod}.verify-deploy` (deploy) at level 1, each waiting on its
  own environment's apply alone, building with that environment's
  `BASE_DOMAIN`; on a pull request `web` waits on nothing; the 02-docs merge
  plans 0 jobs; `--resume` changes nothing. Green under v2.78.4 and v2.79.0;
  refused under v2.58.11 (risk PS-L).
- `testing/e2e.test.sh` (v2.78.4): the 01-product landing passes the Checks
  sequence; in the job tree staged as orun stages it, the stage lane's
  `verify-app-structure`, `build-app` (the live render from a stage document
  in the job's environment, the build with `BASE_DOMAIN=stage.tenants.acme.dev`),
  `verify-build-output` and `deploy-dry-run` pass, binding `KV` to the
  document's id; `wrangler dev` serves the built Worker; the component's own
  smoke passes; `/` carries the product's name and offers tenants at
  `<host>/s/<name>`; a tenant is created through the landing form as a
  browser without JavaScript submits it (303 → `/s/acme-e2e`), read back on
  its page, on `/admin` and by a refused duplicate, served as
  `acme-e2e.stage.tenants.acme.dev` by Host header, kept off `/admin` on its
  host; unknown tenants and paths are 404s; assets serve; deleted from
  `/admin`, it is gone.
- `terraform init -backend=false && terraform validate` green on
  `infra/terraform/cloudflare-kv` (1.15.3). A plan needs the account (the
  adoption lookup calls the Cloudflare API).
- Not verified: a live bootstrap against a workspace, and tenant subdomains
  on a real zone (risk PS-K).

## Verified (PS1–PS3)

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
