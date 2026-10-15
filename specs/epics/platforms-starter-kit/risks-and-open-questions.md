# platforms-starter-kit — risks and open questions

## PS-A — `/admin` would be baked in at build time (RESOLVED)

Upstream never declares `/admin` dynamic; it is dynamic because every
`@upstash/redis` command is a `fetch` with `cache: 'no-store'`, which opts
the route out of static rendering. Over a KV binding there is no fetch, so
Next would pre-render the page at build — with no binding available, or
with an empty list that `revalidatePath` could never refresh through the
read-only static-assets cache. `export const dynamic = 'force-dynamic'` on
`app/admin/page.tsx` says what upstream relied on. `revalidatePath('/admin')`
stays as written; on a dynamic route under OpenNext's default tag cache it
is a no-op and does not throw.

## PS-B — KV is eventually consistent (ACCEPTED, documented)

Redis reads its own writes everywhere at once; KV reads them at once at the
location that wrote and within about a minute elsewhere. The template's
flows are create → redirect to the tenant page (same location), delete →
re-render `/admin` (same location), and visitors reading a tenant that was
created earlier. A visitor who hits a different location within a minute of
creation sees the not-found page once. No flow in the template depends on
a global read-after-write; a port that does (a uniqueness check across
regions, a counter) is where a Durable Object belongs (design §8).

## PS-C — `keys()` is a prefix scan, not a glob (RESOLVED)

The adapter implements `keys('<prefix>*')` with `KV.list({ prefix })`
and throws on any other pattern. The template calls it once, with
`subdomain:*`. `list` pages at 1000 keys; the adapter follows the cursor.

## PS-D — Tenant hostnames need a zone (ACCEPTED, documented; workers.dev made whole in PS4)

`<tenant>.<worker>.<sub>.workers.dev` does not resolve, so a deployed
environment is only usable as a multi-tenant app on a zone the account
owns: a wildcard DNS record plus a Worker route (`*.example.com/*` and
`example.com/*`), or Cloudflare for SaaS custom hostnames with the Worker
as fallback origin. Without it the deployed Worker still serves the landing
page and `/admin` (the smoke test uses that), and tenant links go nowhere.
The README names the steps; provisioning them is a follow-up root.

PS4: tenant links no longer go nowhere. Off the root domain a tenant is a
path on the request's host, `/s/<tenant>` (design §8b): the landing form
says so, creating a tenant redirects there, `/admin` links there. A fresh
product is whole on workers.dev; subdomains turn on by themselves when the
owner routes the root domain to the Worker. The baseline does not provision
the zone, the record or the route: there is no domain phase, because
`workers-deploy` carries no zone permissions and the build has no zone.
`BASE_DOMAIN` defaults to `productdomain` (prod, dev) and
`stage.<productdomain>` (stage); a second-level wildcard for stage needs an
Advanced Certificate, which the product README says.

## PS-E — The root domain lives in one place (RESOLVED)

`NEXT_PUBLIC_ROOT_DOMAIN` is inlined by `next build` into the server, the
proxy and the client bundles (verified: no `process.env` read survives in
`.next/server`). A wrangler `var` would therefore never be read in
production and would be a second place to edit. The component's build
takes the value from the environment's `BASE_DOMAIN` in `intent.yaml`, the
baseline's existing knob for the product's zone; locally it is
`.env.local` for `next dev` and the code's `localhost:3000` default for a
`wrangler dev` of a plain build.

## PS-F — `getCloudflareContext()` in the proxy (SETTLED, not needed)

Upstream's proxy never reads the store; it is a pure host-header rewrite
and stays one. The tenant record is read in `app/s/[subdomain]/page.tsx`,
request-time code where the sync `getCloudflareContext()` is the documented
call. Whether the binding is reachable from the middleware bundle is not
exercised by this port.

## PS-G — Node ≥ 25 stub `localStorage` at prerender (SETTLED)

Nothing in this template reads `localStorage`; the landing page is the
only prerender and it is server-rendered markup. CI builds on Node 22.

## PS-H — No authentication on `/admin` (ACCEPTED, as upstream)

Upstream ships `// TODO: You can add authentication here`. The port keeps
it: there is no admin secret to carry, `.dev.vars.example` is empty on
purpose, and a deployed environment's `/admin` is open until an
instantiator adds a gate (Cloudflare Access in front of the route is the
zero-code option on a zone).

PS4: the baseline keeps it so. The brief's rule for third-party services
(a feature without its key degrades visibly; the card asks for no secret
the platform cannot broker) has nothing to apply to: there is no auth
provider and no key. The product README and `ai/context/operations.md` say
to put Cloudflare Access in front of `/admin*`, and that the deploy smoke's
`/admin` half goes when they do.

## PS-I — The deploy lane checked for a config only the build makes (RESOLVED in PS4)

stack-tectonic's `cloudflare-workers-assets-turbo` runs `verify-app-structure`
— `test -f package.json`, `test -f <wranglerConfig>` — BEFORE `build-app`, in
a job tree staged from the checkout. `wrangler.jsonc` was git-ignored and
rendered only by the build, so every Orun lane of the product would have
failed at that step: no lane had ever run (`ORUN_CI` was never set). Fix:
commit `wrangler.jsonc` as the fixture render of `wrangler.template.jsonc`
(with a GENERATED banner); the build still re-renders it for its
environment. Checks fails when the two disagree (`git diff --exit-code`
after `wire:fixture`), and `testing/wire.test.sh` checks the same.
`testing/e2e.test.sh` runs the step in a staged tree.

## PS-J — The dev lane had no wiring document to render (RESOLVED in PS4)

`buildCommand` rendered with `live.mjs --env "${ORUN_ENVIRONMENT}"`, which
needs `WIRING_CLOUDFLARE_KV_<ENV>`. `dev` subscribes `web` (verify) but no
root applies there, so `WIRING_CLOUDFLARE_KV_DEV` never exists: every dev
lane would have failed in `build-app`. Fix: `live.mjs --fixture
wiring.fixture.json --fixture-envs dev` renders the fixture for the
verify-only environment, and only for it; the fixture gained a `dev` entry.
stage and prod still need the real document and refuse without it
(`testing/wire.test.sh`).

## PS-K — No live bootstrap yet (OPEN)

Everything short of the platform is proven on every pull request: the card
against the build, the blueprint read by three orun versions, the leak gate,
the wiring path, the offline bootstrap with the blueprint's own hooks, the
product's own plan (the KV apply before the Worker's deploy; nothing waiting
on a pull request), and the produced product built in the job tree,
dry-deployed with the stage document's namespace id, served, smoke-tested,
and used: a tenant created through the landing form, read back by path, by
`/admin` and as a subdomain by Host header, and deleted. NOT proven: the
repository created and linked, the token minted by `integrations/reconcile`,
a real `terraform apply` (the root is held to `terraform validate`; its
`adopt.tf` lookup calls the Cloudflare API), the lease-published document, a
real `wrangler deploy`, the probes, and tenant subdomains on a real zone.
Hence the registry row is `unlisted` until one bootstrap from the tag has
come up.

## PS-L — The bootstrap floor plans every edge enforced (ACCEPTED)

orun v2.58.11 — the floor for RUNNING a bootstrap — does not apply a
`dependsOn` edge's `modeRules`: it plans a pull request with `web` waiting on
the KV plan. That CLI never plans the product's CI (its `ci.yml` pins
v2.78.4, which applies them), and on a push to main both agree. The
placement tier plans as the product does: `baseline.yml` runs it under the
lane pin, and the test refuses an orun older than `ci.yml`'s pin.
