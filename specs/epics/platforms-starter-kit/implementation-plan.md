# platforms-starter-kit — implementation plan

Milestones land in order; each task is one pull request on an
`orun/PS-n-<slug>` branch with an `Orun-Task: PS-n` trailer.

## PS0 — the spec ✅

This doc set, `epic.yaml` and the task contracts, merged to `main`.

**Done when**
- the five documents and `epic.yaml` are on `main`
- `tasks/PS-1..PS-4.TaskContract.yaml` exist (PS-5 joined with PS4)

## PS1 — the platform on Workers ✅

`apps/web` is the upstream template with the Workers build around it and
`lib/redis.ts` speaking the Upstash surface over the `KV` binding;
`wrangler.template.jsonc` + `wiring.fixture.json` render the config;
`tests/web` exercises the adapter over a fake namespace, `lib/subdomains.ts`,
`extractSubdomain` and the proxy's rewrite/redirect decisions.

**Done when**
- `pnpm install && pnpm run wire:fixture && pnpm typecheck && pnpm lint && pnpm test && pnpm build` is green locally and in `Checks`
- `wrangler dev` answers `/` with the landing page (200), an unknown tenant host (`Host: nope.localhost:3000`) with the not-found page (404), and after a tenant is created through the landing form, `Host: <tenant>.localhost:3000` with the tenant page (200) and `/admin` with it listed
- `/admin` is built as a dynamic route (`ƒ`), never pre-rendered

## PS2 — the KV namespace from Terraform ✅

`infra/terraform/cloudflare-kv` provisions a namespace per environment and
publishes `{app_kv_id, app_kv_title}` as the `WIRING_CLOUDFLARE_KV`
document; `apps/web/component.yaml` depends on it and declares the
`secretEnv` the deploy's render reads.

**Done when**
- `terraform init -backend=false && terraform validate` passes on the root
- the root's wiring keys match the template's tokens (`wire:fixture` renders the same keys)
- the component's `secretEnv` names match the root's `secretOutputs`

## PS3 — ready to instantiate ✅

README (run, test, preview, deploy, the wildcard domain), `IMPLEMENTATION-STATUS.md`
with PRs and departures, epic `completed`.

**Done when**
- the README quick start works from a fresh clone
- the status file lists every PR and departure

## PS4 — a baseline, in one landing ✅

`blueprint.yaml`, `repo-blueprint.yaml` (two phases: `01-product`,
`02-docs`), `.baseline/` (identity, task contracts, the product's README),
`tooling/rebrand`, `tooling/bootstrap`, `hooks/render-deployment-docs.sh`,
`ai/context/`, `docs/phases/`, `BOOTSTRAP.md`, `testing/`, `baseline.yml`
and `tag.yml` (design §9); and what the product needed to deploy from a
fresh repository and work there: `wrangler.jsonc` committed, dev rendering
the fixture, `apps/web`'s enforced `dependsOn: cloudflare-kv` on main,
`packages/`, and tenants served by path off the root domain
(`lib/addresses.ts`).

**Done when**
- orun at the bootstrap floor (v2.58.11), the lane pin (v2.78.4) and the
  current CLI (v2.79.0) reads `repo-blueprint.yaml`, and
  `testing/manifest.test.sh` holds the card to it
- the product's own push-to-main plan applies `cloudflare-kv` before it
  deploys `web` on stage and prod (`testing/placement.test.sh`)
- the product, built in the job tree and served by `wrangler dev` off its
  root domain, creates a tenant through its landing form and serves it at
  `/s/<tenant>` (`testing/e2e.test.sh`)
- `Baseline CI` is green: the contract tests, the wiring path, the leak gate,
  the offline bootstrap and the end-to-end tier
- the status file records what is proven offline and what only a live
  bootstrap (or a custom domain) can prove

## PS5 — the cirrus standard ✅

Bring the baseline to cirrus-baseline's standard, with nothing about the
product itself changing.

- **No kiox.** `kiox.yaml`/`kiox.lock` pinned an orun (v2.15.0) that nothing
  ran: every workflow installs orun itself through `orun-action` with its own
  `version:`. The files, their two modules and the rebrand's skip entry go.
- **Component docs.** `tooling/catalog/gen-component-docs.py` writes each
  component's `docs/overview.md`, `docs/architecture.md` and `docs/runbook.md`
  from what the component declares, as cirrus-baseline's do; the pages ship
  with the component. Baseline CI runs it with `--check`.
- **The context pack.** `ai/context/current.md`, `decisions.md` and
  `open-risks.md` beside the two pages a product ships with — this
  repository's own, so no module places them.
- **Status that agrees with the tags.** PS4 is shipped and tagged
  `baseline-v1`.
- **The subdomain from the Cloudflare connection (PS-7).** The card declares
  the workers.dev `subdomain` as `from: connection.cloudflare.workersSubdomain`,
  as cirrus-baseline does since baseline-v23, so the console asks for nothing
  the connection already knows; `testing/manifest.test.sh` requires the
  source's provider in `spec.requires.integrations`.

**Done when**
- nothing outside this milestone's own record names kiox (`git grep -i
  kiox`), and the leak gate and the offline bootstrap pass without the two
  modules
- the docs check is green in Baseline CI
- this file, the status file and `epic.yaml` agree

## PS6 — the domain is set later (PS-8) ✅

**Done when** the console card asks for no domain; `productdomain` is an
optional build input, empty by default; a site built without one is branded
with the reserved placeholder `<reponame>.example.com` where the domain goes
(`BASE_DOMAIN` in `intent.yaml`, `stage.<reponame>.example.com` on stage) and its README says how an owner sets the real one;
Baseline CI places, leak-checks and plans a site built with no domain.
Shipped in `baseline-v3`.

## After PS4 (outside this repository)

1. Cut `baseline-v1` with `tag.yml` from the merged `main` — done: `baseline-v1`
   is [#5](https://github.com/sourceplane/platforms-starter-kit/pull/5)'s merge.
2. Register the row in orun-cloud's `infra/baselines-registry/baselines.yaml`
   (unlisted) with the card vendored at the tag.
3. Bootstrap one product from the tag against a workspace; record its
   timings; then flip the row to public with a page on orunbase.com.

## Sequencing note

PS1 and PS2 are independent files but PS1's template already names the
root's wiring keys, so PS2 is the half that makes those names true.
Applying PS2 needs a workspace with a Cloudflare connection; until then the
Orun lane plans nothing (`ws_CHANGE_ME`) and `Checks` is the merge gate. PS3
is documentation over both. PS4 packages PS1–PS2 as a baseline whose one
landing applies PS2's root before it deploys PS1's Worker.
