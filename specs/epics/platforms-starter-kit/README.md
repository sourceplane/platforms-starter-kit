# Epic: platforms-starter-kit (PS)

**Vercel's Platforms Starter Kit is the multi-tenant template: every tenant is a subdomain, a Next.js proxy reads the host and rewrites `acme.yourdomain.com/` to `/s/acme`, a landing form creates tenants with an emoji, an admin page lists and deletes them, and the records live in Upstash Redis under `subdomain:<name>`. Nothing in that shape is Vercel's except where the app runs and where the records live. On Cloudflare the app is an OpenNext Worker + Static Assets with the proxy inside it, and the records are in Workers KV behind a module that keeps the Upstash client's surface — `redis.get / set / del / keys / mget`, the same keys, the same JSON — so the template's data access and server actions stay as written. The namespace comes from Terraform through Orun and is bound per environment through the wiring document, the way the Cirrus baseline binds its own KV.**

The upstream code stays the code: the proxy, the pages, the server actions, `lib/subdomains.ts`, the shadcn components and the emoji picker. The port adds the Workers build, the monorepo wrapper, the KV adapter, a test package that exercises the adapter over a fake namespace and the proxy's routing decisions, the KV Terraform root and the deploy contract. The wildcard hostname tenants need is a zone matter (a wildcard record and a Worker route, or Cloudflare for SaaS) and is documented, not provisioned.

## Status

| Field | Value |
|-------|-------|
| Status | ✅ PS0–PS4 shipped (#1–#5), PS4 tagged `baseline-v1`; PS5 (the cirrus standard, PS-6 #6 and PS-7 #7) tagged `baseline-v2`. The KV apply and a live deploy are not yet proven by a live bootstrap (risk PS-K) |
| Cluster | **PS** (PS0–PS5) |
| Owner(s) | `apps/web` (the app) · `tests/web` (adapter and proxy tests) · `infra/terraform/cloudflare-kv` (the namespace) |
| Builds on | `cirrus-baseline` conventions — the `cloudflare-kv` Terraform root and the `@@wiring(...)@@` per-environment render; intent, components, `checks.yml` gate, gated `ci.yml` |
| Upstream | [vercel/platforms](https://github.com/vercel/platforms) |
| Changes | Adds the Workers build, the monorepo wrapper, `lib/redis.ts` over KV, tests, the KV root and the deploy contract; swaps Vercel Speed Insights for the Cloudflare Web Analytics beacon; makes `/admin` explicitly dynamic |
| Decisions locked | (1) OpenNext on Workers + Static Assets. (2) Workers KV, not a Durable Object per tenant: the template's store is a key-value map with a prefix scan, and that is what KV is. (3) The adapter keeps the Upstash surface; the app's data access is untouched. (4) `wrangler.jsonc` is rendered per environment from the wiring document — and, since PS4, committed as the fixture render, because the deploy lane checks it exists before the build (risk PS-I). (5) The root domain is one knob — the environment's `BASE_DOMAIN` in `intent.yaml`, inlined by `next build`. (6) PS4: one landing — the plan, not a landing boundary, orders the namespace before the Worker. (7) PS4: off the root domain a tenant is a path on the request's host (`/s/<tenant>`), so a fresh deploy works on workers.dev; subdomains are the owner's custom-domain step. |
| Gate | PS1 is the first user-visible rung. PS2 needs a workspace with a Cloudflare connection to apply; it is verified by `terraform validate` and `plan`. |
| Shipped as | `baseline-v1` ([#5](https://github.com/sourceplane/platforms-starter-kit/pull/5)), then `baseline-v2` (PS5: [#6](https://github.com/sourceplane/platforms-starter-kit/pull/6), [#7](https://github.com/sourceplane/platforms-starter-kit/pull/7)); proven offline (Baseline CI: the produced product built, served by `wrangler dev` with a local KV, and used), `terraform validate` on the root, deploy gated until a workspace is linked |

## Read order

1. `design.md` — what maps to what, the adapter contract, the env/wiring flow, the rejected alternative
2. `implementation-plan.md` — the milestones and what "done" means for each
3. `risks-and-open-questions.md` — what could go wrong and what was decided
4. `IMPLEMENTATION-STATUS.md` — what actually shipped (kept distinct from intent)

## Milestones at a glance

| Milestone | What it lands | Done when |
|---|---|---|
| PS0 — the spec | this doc set and the task contracts | merged on `main` |
| PS1 — the platform on Workers | `apps/web` built by OpenNext with `lib/redis.ts` over KV, rendered wrangler config, `tests/web` | `wrangler dev` serves `/`, 404s an unknown tenant, serves a created one; Checks green |
| PS2 — the KV namespace from Terraform | `infra/terraform/cloudflare-kv`, the app's `dependsOn` and `secretEnv` | the root validates; the wiring keys match the template's tokens |
| PS3 — ready to instantiate | README, as-built status | a reader can run, test, preview and deploy it, and knows what the wildcard domain needs |
| PS4 — a baseline, in one landing | card, build document, rename, bootstrap tooling, the workers.dev path fallback, tests | a new product goes from nothing to live in one landing, the KV namespace applied before the Worker, tenants created and served on workers.dev; Baseline CI green |
| PS5 — the cirrus standard | no kiox, generated component docs, the context pack, status that agrees with the tags; the workers.dev subdomain read from the Cloudflare connection | Baseline CI green with the docs check; the card asks for no workers.dev subdomain |
