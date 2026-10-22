# Epics

Orun-style work programs. Each epic is a folder carrying `epic.yaml` (the
declaration the platform reads: slug, key prefix, milestones with exit
criteria and task keys) beside its doc set. The pull request that adds the
folder is the adoption; the merge creates the epic in the workspace.

| Epic | Cluster | Status | What it is |
|------|---------|--------|------------|
| [`platforms-starter-kit/`](./platforms-starter-kit/) | **PS** | ✅ Shipped (`baseline-v3`); live bootstrap pending | Vercel's Platforms Starter Kit, equivalent in code and function, on Cloudflare Workers with tenants in Workers KV — and an Orun baseline that instantiates it in one landing, live on workers.dev before any custom domain (PS4) |

As-built ≠ intent: what shipped lives in each epic's `IMPLEMENTATION-STATUS.md`.
