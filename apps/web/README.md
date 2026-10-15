# apps/web — the multi-tenant app

A multi-tenant Next.js 16 app from Vercel's Platforms Starter Kit
([vercel/platforms](https://github.com/vercel/platforms)), running on
Cloudflare Workers + Static Assets through
[`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare), with the
tenant records in a **Workers KV** namespace instead of Upstash Redis:

- `app/page.tsx` — the landing page: create a tenant with a name and an emoji
  (`subdomain-form.tsx`, the `createSubdomainAction` server action)
- `app/s/[subdomain]/page.tsx` — a tenant's page
- `app/admin` — every tenant, listed and deletable (no authentication, as
  upstream: put Cloudflare Access in front of `/admin` before you rely on it)
- `proxy.ts` — `<tenant>.<root domain>/` is rewritten to `/s/<tenant>`
- `lib/redis.ts` — the Upstash client's `get / set / del / keys / mget` over
  the `KV` binding, the same `subdomain:<name>` keys and JSON records
- `lib/addresses.ts` — where a tenant lives, as seen from the request's host
- `app/site.ts` — the site's name

```bash
pnpm dev        # next dev on http://localhost:3000, a local KV through wrangler's platform proxy
pnpm build      # next build + opennextjs-cloudflare build → .open-next/
pnpm preview    # wrangler dev over the built Worker, the same local KV
```

## Subdomains, and the path they fall back to

The root domain tenants hang off is `NEXT_PUBLIC_ROOT_DOMAIN`, inlined at
build time (`localhost:3000` when unset; on a deploy, the environment's
`BASE_DOMAIN` in `intent.yaml`). On that domain every tenant is a
subdomain, `<tenant>.<root>`. A request on any other host — the Worker's
`workers.dev` address before a custom domain is attached, `wrangler dev` on
`127.0.0.1` — reaches a tenant by path on that host instead, `/s/<tenant>`:
the landing form says so, creating a tenant redirects there, and `/admin`
links there. The same build serves both; nothing needs rebuilding when the
domain's wildcard route starts pointing at the Worker.

Locally, `http://<tenant>.localhost:3000` works under `pnpm dev` (browsers
resolve `*.localhost` to the loopback address).

## The KV binding

The binding's namespace id is not hand-written. `wrangler.template.jsonc`
names it as a wiring token; `wrangler.jsonc` is that template rendered from
`wiring.fixture.json` (placeholder ids, for local work and verification),
and every deploy renders it again from the id the `cloudflare-kv` Terraform
root published for the environment (`component.yaml`'s `buildCommand`).

KV is eventually consistent across locations: a tenant created in one place
reads back at once there and within about a minute everywhere else. The
create → redirect → tenant page flow reads where it wrote.
