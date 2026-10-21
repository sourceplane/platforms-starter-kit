# platforms-starter-kit — decisions

The choices that shape this repository, one line each, with where the full
reasoning lives. Superseded decisions stay listed, marked, so the history
reads in order.

| # | Decision | Why | Source |
|---|---|---|---|
| 1 | OpenNext on Workers + Static Assets (`cloudflare-workers-assets-turbo`), the proxy inside the Worker | The template's pages, proxy and server actions run as written | `specs/epics/platforms-starter-kit/design.md` §2 |
| 2 | Workers KV, not a Durable Object per tenant | The template's store is a key-value map with a prefix scan, and that is what KV is | design.md §8, risk PS-B |
| 3 | `lib/redis.ts` keeps the Upstash client's surface (`get / set / del / keys / mget`, same keys, same JSON) | The template's data access and server actions stay untouched | design.md §3, risk PS-C |
| 4 | `wrangler.jsonc` rendered per environment from the KV wiring document, and committed as the fixture render; `dev` renders the fixture | The deploy lane checks the file exists before the build; no root applies to `dev` (PS4) | risks PS-I, PS-J |
| 5 | The root domain is one knob: the environment's `BASE_DOMAIN` in `intent.yaml`, inlined by `next build` | A wrangler var would never be read in production and would be a second place to edit | risk PS-E |
| 6 | One landing (`01-product`) then the record (`02-docs`); `web` depends on `cloudflare-kv`, enforced on a push to `main`, advisory on a pull request | The plan, not a landing boundary, orders the namespace before the Worker (cirrus-baseline since baseline-v22) | design.md §9 |
| 7 | Off the root domain a tenant is `/s/<tenant>` on the request's host; no domain phase | A fresh deploy has no zone, and `workers-deploy` carries no zone permissions; subdomains are the owner's step | design.md §8b, risk PS-D |
| 8 | `/admin` stays unauthenticated, as upstream | No auth provider to carry; Cloudflare Access in front of `/admin*` is the zero-code gate | risk PS-H |
| 9 | `ci.yml` plans nothing while `intent.yaml` names `ws_CHANGE_ME` (replaced the `ORUN_CI` gate) | A bootstrap cannot set a repository variable | IMPLEMENTATION-STATUS (PS4) |
| 10 | stack-tectonic 0.19.0, not 0.20.0 | 0.20.0's lane-scoped install is refused by Next 16's Turbopack | IMPLEMENTATION-STATUS (PS4) |
| 11 | orun is pinned only where it runs (the `orun-action` `version:` in each workflow); no kiox | `kiox.yaml` pinned a version nothing ran | IMPLEMENTATION-STATUS (PS5) |
| 12 | Component docs are generated from the manifests and checked in CI | A hand-written copy of the dependency graph, bindings and published outputs drifts silently | `tooling/catalog/gen-component-docs.py` |
| 13 | The workers.dev `subdomain` is read from the Cloudflare connection (`from: connection.cloudflare.workersSubdomain`), never asked | It belongs to the account like its id and has one right answer; a typed one could only be wrong, and showed up after deploy in the smoke and the probes | `blueprint.yaml`, IMPLEMENTATION-STATUS (PS-7) |
