# platforms-starter-kit — open risks

What is not yet proven or not yet decided. The full write-up of every risk,
including the accepted and resolved ones, is
`specs/epics/platforms-starter-kit/risks-and-open-questions.md`; this page
lists only what is still live, so it should be short.

| ID | Risk | State | What closes it |
|---|---|---|---|
| PS-K | No live bootstrap yet: the repository created and linked, the token minted, a real `terraform apply`, the lease-published wiring document, a real `wrangler deploy`, the probes and tenant subdomains on a real zone are all unproven | OPEN | One bootstrap from a tag against a workspace (and a zone routed to the Worker for subdomains) |

Accepted, and worth knowing before you change them: PS-B (KV is eventually
consistent across locations), PS-D (tenant hostnames need a zone; the
baseline provisions none), PS-H (no authentication on `/admin`, as upstream),
PS-L (the bootstrap floor, orun v2.58.11, plans every edge enforced).
