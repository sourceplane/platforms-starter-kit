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

## PS-D — Tenant hostnames need a zone (ACCEPTED, documented)

`<tenant>.<worker>.<sub>.workers.dev` does not resolve, so a deployed
environment is only usable as a multi-tenant app on a zone the account
owns: a wildcard DNS record plus a Worker route (`*.example.com/*` and
`example.com/*`), or Cloudflare for SaaS custom hostnames with the Worker
as fallback origin. Without it the deployed Worker still serves the landing
page and `/admin` (the smoke test uses that), and tenant links go nowhere.
The README names the steps; provisioning them is a follow-up root.

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
