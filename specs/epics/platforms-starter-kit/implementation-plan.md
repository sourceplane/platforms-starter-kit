# platforms-starter-kit — implementation plan

Milestones land in order; each task is one pull request on an
`orun/PS-n-<slug>` branch with an `Orun-Task: PS-n` trailer.

## PS0 — the spec ✅

This doc set, `epic.yaml` and the task contracts, merged to `main`.

**Done when**
- the five documents and `epic.yaml` are on `main`
- `tasks/PS-1..PS-4.TaskContract.yaml` exist

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

## Sequencing note

PS1 and PS2 are independent files but PS1's template already names the
root's wiring keys, so PS2 is the half that makes those names true.
Applying PS2 needs a workspace with a Cloudflare connection; until then the
Orun lane is gated and `Checks` is the merge gate. PS3 is documentation over
both.
