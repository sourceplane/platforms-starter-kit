# Epics

Orun-style work programs. Each epic is a folder carrying `epic.yaml` (the
declaration the platform reads: slug, key prefix, milestones with exit
criteria and task keys) beside its doc set. The pull request that adds the
folder is the adoption; the merge creates the epic in the workspace.

| Epic | Cluster | Status | What it is |
|------|---------|--------|------------|
| [`platforms-starter-kit/`](./platforms-starter-kit/) | **PS** | Draft | Vercel's Platforms Starter Kit, equivalent in code and function, on Cloudflare Workers with tenants in Workers KV |

As-built ≠ intent: what shipped lives in each epic's `IMPLEMENTATION-STATUS.md`.
