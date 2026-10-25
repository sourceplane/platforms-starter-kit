# platforms-starter-kit — operating contract (for humans and agents)

This is the standing guide to how this site is deployed and operated.
Instance facts (live URLs, workspace, the secrets it uses) live in
[deployment.md](deployment.md), rendered from probed reality by the
bootstrap's `02-docs` phase; this file is the contract that stays true
between deployments. It is written to give an agent with repository read
access enough context to reason about and operate the site without any
other source.

## What this system is

A multi-tenant app on Cloudflare alone, expressed as an Orun
component-native desired-state repo.

- **`infra/terraform/cloudflare-kv`** — one Workers KV namespace per deployed
  environment (`stage`, `prod`), applied by Terraform. After each apply it
  publishes a wiring document — `{app_kv_id, app_kv_title}` — as the Orun
  secret `WIRING_CLOUDFLARE_KV` on that environment.
- **`apps/web`** — the app: Next.js built by `@opennextjs/cloudflare` into one
  Worker plus Static Assets. The landing page creates a tenant (a server
  action writes `subdomain:<name>` → `{emoji, createdAt}` to the `KV`
  binding), a tenant's page reads it, `/admin` lists (`list` by prefix) and
  deletes them. `proxy.ts` rewrites `<tenant>.<root domain>/` to
  `/s/<tenant>`.
- **`tests/web`** — the store adapter over a fake namespace, the proxy's
  routing, the host-dependent tenant links (vitest). Run them with
  `pnpm test` before you push: its `dev` lane installs and checks the
  package, and does not run the suite.
- **`tooling/*`** — shared TypeScript and ESLint configuration, and the
  wrangler renderer that turns `wrangler.template.jsonc` plus a wiring
  document into `wrangler.jsonc`.

Environments: **`stage`** and **`prod`** are deployed; **`dev` is
verify-only by design** — lanes build and dry-deploy, nothing deploys, and
no KV namespace exists for it (its build renders the committed fixture).

## Where a tenant lives

The root domain is each environment's `env.BASE_DOMAIN` in `intent.yaml`
(`platforms-starter-kit.example.com` on prod,
`stage.platforms-starter-kit.example.com` on stage — the reserved
placeholder the site was born with, until an owner replaces it with a
domain of theirs), inlined into the build as `NEXT_PUBLIC_ROOT_DOMAIN`. A
request arriving ON that domain sees tenants as subdomains,
`<tenant>.<root>`; a request on any other host — the workers.dev address,
before the domain's wildcard route points at the Worker — sees them as
paths on that host, `/s/<tenant>` (`apps/web/lib/addresses.ts`). Both work
against the same build; attaching the domain is the owner's step (README,
"Tenant subdomains"), and its one change in the repository is replacing the
placeholder in `BASE_DOMAIN`.

## Identity and tenancy

Every remote operation runs against ONE Orun workspace, declared in
`intent.yaml` under `execution.state.workspace` — committed, enforced, and
what CI uses. Do not remove it; headless credentials depend on it. If it
reads `ws_SET_ME`, the bootstrap had no workspace to write: set the real one
before anything else.

## How deployment works

1. Merge (or push) to `main`.
2. CI (`.github/workflows/ci.yml`) runs `orun plan --changed` — only
   components whose files changed are planned — then runs each planned lane
   with `orun run --remote-state`, authenticated by GitHub OIDC (the
   exchange resolves this repository's linked workspace server-side).
3. **The namespace before the Worker.** `cloudflare-kv` applies for the
   environment and publishes `WIRING_CLOUDFLARE_KV`. `apps/web` declares an
   enforced `dependsOn` on it for pushes to `main`, so its deploy starts only
   after that apply — and a job resolves its secrets when it starts, so the
   document is there.
4. `apps/web` renders `wrangler.jsonc` from that document (the real
   namespace id), builds once per environment with that environment's
   `BASE_DOMAIN`, `wrangler deploy` ships `platforms-starter-kit-web-<env>`,
   and a smoke test fetches `/` (it must name the host it was asked on in its
   `/s/` tenant addresses — only the Worker rendering per request can) and
   `/admin` (it must answer — it lists the tenants from KV).
5. `prod` deploys after `stage` has converged on the same commit
   (`environments.prod.promotion` in intent.yaml).
6. **The convergence run is the deployment.** A green run means every
   planned lane applied. Failed lanes are retried with
   `gh run rerun --failed`, which resumes the same execution.

On a pull request nothing applies or deploys: the KV root plans, the app
builds and dry-deploys, and the edges in step 3 are advisory.

Caveats that matter:

- A push that touches no component files plans zero lanes — that run is
  green and deployed nothing. Never treat "latest run green" as "site
  converged"; probe the URLs instead.
- A change to `intent.yaml`'s `environments` (a new `BASE_DOMAIN`) maps to
  no component and redeploys nothing on its own. Land it with a change under
  `apps/web`.
- `wrangler.jsonc` is generated. Edit `wrangler.template.jsonc`, run
  `pnpm run wire:fixture` and commit both; the deploy renders its own
  config from the template, so a stale committed render misleads local work.

## Secrets model

- **Brokered provider secrets**: `CLOUDFLARE_API_TOKEN` (the
  `workers-deploy` scope: Workers Scripts and KV Storage write) and
  `CLOUDFLARE_ACCOUNT_ID` — pointers minted per run from the workspace's
  Cloudflare connection. No long-lived values at rest; nothing to rotate by
  hand. The KV root and the Worker deploy use the same two.
- **Wiring**: `WIRING_CLOUDFLARE_KV` on `stage` and `prod`, written by the
  KV root's apply (lease-published), read by the Worker's build as
  `WIRING_CLOUDFLARE_KV_<ENV>`. It holds ids, not credentials.
- Inspect by NAME only: `orun secrets list --org <ws> --project` and
  `--env stage|prod`. No tooling in this repository prints a secret value,
  and no document in `ai/context/` may contain one.
- The app needs no runtime secret. `/admin` has no authentication: gate it
  with Cloudflare Access (README), not with a secret in the app.

## Verifying the system

```bash
# the landing page on each environment (also recorded, probed, in deployment.md):
# rendered for the host it was asked on, tenants under /s/ on workers.dev
curl -s https://platforms-starter-kit-web-stage.your-workers-subdomain.workers.dev/ | grep -o 'Opens at [^<]*'
curl -s -o /dev/null -w '%{http_code}\n' https://platforms-starter-kit-web-prod.your-workers-subdomain.workers.dev/admin

# the wiring the deploys read, and workspace readiness
orun secrets list --org <ws> --env stage && orun secrets list --org <ws> --env prod
orun integrations list --org <ws> --json && orun cloud check --org <ws>
```

## Common operations

| task | how |
|---|---|
| change the app | edit `apps/web/app` (its name: `apps/web/app/site.ts`), merge |
| deploy a change | merge to `main`; watch the run; failed lanes → `gh run rerun --failed` |
| redeploy without a change | edit the last line of `apps/web/component.yaml` (`# orun: redeploy <reason> <stamp>`) and merge — it is a deploy trigger, nothing reads it |
| tenant subdomains | the zone, a wildcard DNS record and a Worker route on the root domain (README, "Tenant subdomains"), and the placeholder `platforms-starter-kit.example.com` replaced with it in `env.BASE_DOMAIN` (below) |
| change the root domain | `env.BASE_DOMAIN` per environment in `intent.yaml`, landed with a change under `apps/web` (it is inlined at build time) |
| gate `/admin` | Cloudflare Access on `/admin*`; then drop the `/admin` half of the smoke in `apps/web/component.yaml` |
| list or delete tenants by hand | `wrangler kv key list --namespace-id <id> --prefix subdomain: --remote`, `wrangler kv key delete subdomain:<name> --namespace-id <id> --remote` (the id is in the environment's `WIRING_CLOUDFLARE_KV`) |
| add a binding (R2, D1, another KV) | a Terraform root under `infra/terraform/` that publishes `WIRING_<ROOT>`, a token in `wrangler.template.jsonc`, its fixture entry, the root in the build's `--components`, the `WIRING_<ROOT>_<ENV>` secretEnv and an enforced `dependsOn` on it in `apps/web/component.yaml` |
| add a runtime secret | `orun secrets set <KEY> --org <ws> --env <env>` |
| headless credentials | `ORUN_TOKEN` (workspace-scoped) + `GITHUB_TOKEN` |

The deployment record is the bootstrap's `02-docs` phase. Re-running it (the
Orun console's Retry on that phase, or `orun new … --phase 02-docs`)
re-probes the URLs and re-renders [deployment.md](deployment.md); it is
idempotent.

## Evolution

KV is eventually consistent across locations (a tenant created in one place
reads back elsewhere within about a minute) and lists by prefix. Per-tenant
data that needs transactions belongs in a Durable Object per tenant.
Structural changes follow the same contract that deployed the site: add a
component under `apps/`, `infra/` or `packages/` with a `component.yaml`,
land it as a pull request, and the convergence run applies it.
