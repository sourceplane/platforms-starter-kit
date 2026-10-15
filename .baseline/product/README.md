# platforms-starter-kit

A multi-tenant app: anyone creates a tenant — a name and an emoji — from the
landing page, every tenant gets a page of its own, and `/admin` lists and
deletes them. Next.js on **Cloudflare Workers + Static Assets** through
[`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare), with the
tenants in a **Workers KV** namespace that Terraform provisions per
environment.

## Live deployment

<!-- 02-docs:begin -->
Not recorded yet. The bootstrap's last phase writes the live URLs, the
workspace and the secrets inventory into
[ai/context/deployment.md](ai/context/deployment.md); how the site deploys
and how to operate it is in
[ai/context/operations.md](ai/context/operations.md).
<!-- 02-docs:end -->

## What is here

| Surface | Where |
|---|---|
| The landing page (create a tenant), a tenant's page `/s/[subdomain]`, `/admin`, not-found | `apps/web/app` |
| The site's name | `apps/web/app/site.ts` |
| Where a tenant lives: `<tenant>.<root domain>`, or `/s/<tenant>` on any other host | `apps/web/lib/addresses.ts`, `apps/web/proxy.ts` |
| The tenant store (`get / set / del / keys / mget` over the `KV` binding) | `apps/web/lib/redis.ts`, `apps/web/lib/subdomains.ts` |
| Workers build, bindings and deploy contract | `apps/web/next.config.ts`, `open-next.config.ts`, `wrangler.template.jsonc` + `wiring.fixture.json` (→ `wrangler.jsonc`), `component.yaml` |
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

```bash
pnpm --filter @app/web dev        # http://localhost:3000 — a local KV through wrangler's platform proxy
pnpm --filter @app/web preview    # wrangler dev over the built Worker, same local KV
```

Under `pnpm dev` a tenant is `http://<tenant>.localhost:3000` (browsers
resolve `*.localhost` to the loopback address); under `preview` it is
`/s/<tenant>`. Make the pages yours in `apps/web/app`, and the site's name in
`apps/web/app/site.ts`.

## Where tenants live

Every tenant is a subdomain of the environment's root domain —
`<tenant>.platforms-starter-kit.example.com` on prod,
`<tenant>.stage.platforms-starter-kit.example.com` on stage — once that
domain's wildcard route points at the Worker (below). Until then the site
answers on its workers.dev address, where a subdomain cannot resolve, so
there a tenant is a path on the same host: `/s/<tenant>`. The landing form
says which, creating a tenant redirects to it, and `/admin` links to it. The
app decides per request, from the host it was asked on: nothing is rebuilt
when the domain goes live, and the workers.dev address keeps working
afterwards.

## How the tenant store is wired

The Worker binds the namespace as `KV`; a tenant is `subdomain:<name>` →
`{ emoji, createdAt }`. The namespace id is never hand-written:
`apps/web/wrangler.template.jsonc` names it as a wiring token, and
`wrangler.jsonc` is that template rendered — from `wiring.fixture.json`
(placeholder ids) for local work and verification, and on every deploy from
the document the `cloudflare-kv` Terraform root publishes after its apply
(`WIRING_CLOUDFLARE_KV`, per environment). Edit the template, then
`pnpm run wire:fixture`; Checks fails if the committed `wrangler.jsonc` is
not the fixture render.

KV is eventually consistent across locations: a tenant created in one place
reads back at once there and within about a minute everywhere else. The
create → redirect → tenant page flow reads where it wrote.

## How it deploys

Merges to `main` converge through [Orun](https://github.com/sourceplane/orun):
`.github/workflows/ci.yml` plans the changed components and runs each lane
against the workspace in `intent.yaml`. The KV namespace applies first, then
the app builds with that environment's namespace id and root domain and
deploys — to `stage`, then to `prod` once stage has converged on the same
commit; `dev` only verifies. The Worker is
`platforms-starter-kit-web-<env>` on your account's workers.dev subdomain,
and every deploy is smoke-tested over HTTP: `/` must be rendered for the host
it was asked on, and `/admin` must read the tenant list from KV.
`checks.yml` runs install, the fixture render, typecheck, lint, test and
build on every pull request. (A push to `main` runs `ci.yml` alone, which
applies, builds and deploys.)

The pipeline holds one credential, GitHub's own `GITHUB_TOKEN`. The
Cloudflare token and account id are brokered per run from the workspace's
Cloudflare connection, and the namespace ids travel as Orun secrets; nothing
provider-shaped is stored in the repository or in GitHub.

## After the first deploy: what is yours to do

### Tenant subdomains (a custom domain)

A fresh deployment has no domain of its own. To give every tenant its
subdomain, on the Cloudflare account the site deploys into:

1. **The zone.** Add the root domain's zone (`platforms-starter-kit.example.com`,
   or the domain above it) to the account.
2. **DNS.** A proxied wildcard record, `*.platforms-starter-kit.example.com`
   (an `AAAA` to `100::` is enough: the Worker answers, not an origin), and
   one for the apex.
3. **The route.** Workers & Pages → `platforms-starter-kit-web-prod` →
   Settings → Domains & Routes → Add → Route:
   `*.platforms-starter-kit.example.com/*` and
   `platforms-starter-kit.example.com/*`. For stage, the same with
   `stage.platforms-starter-kit.example.com` and
   `platforms-starter-kit-web-stage` — a second-level wildcard needs an
   Advanced Certificate, because Universal SSL covers one level only.
4. **`BASE_DOMAIN`**, only if tenants should hang off another domain: it is
   each environment's `env.BASE_DOMAIN` in `intent.yaml`, inlined at build
   time. A change there maps to no component, so land it together with a
   change under `apps/web` (its last line, `# orun: redeploy …`, is a deploy
   trigger) and the next convergence rebuilds with it.

Nothing else changes: requests arriving on the root domain get subdomain
links, requests on workers.dev keep `/s/<tenant>`. For customer-owned
domains, Cloudflare for SaaS custom hostnames with the Worker as the
fallback origin is the same idea.

### A gate on `/admin`

`/admin` lists and deletes every tenant and has no authentication (the
template's `TODO`). Before you rely on it, put
[Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/policies/access/)
in front of `/admin*` on the Worker's hostnames — no code change. The deploy
smoke reads `/admin`; once it is gated, drop that half of `smokeCommand` in
`apps/web/component.yaml`.
