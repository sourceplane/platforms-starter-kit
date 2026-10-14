// OpenNext Cloudflare adapter config.
//
// Nothing here is pre-rendered and later revalidated: the landing page is
// static and never changes, the tenant page and `/admin` render on demand
// against KV (`/admin` says so with `dynamic = 'force-dynamic'`). The
// static-assets incremental cache serves the pre-rendered shells straight
// from the Worker's static assets (read only, nothing extra to provision);
// the template's one `revalidatePath('/admin')` lands on a dynamic route and
// is a no-op under the default tag cache. A template that revalidates
// pre-rendered pages swaps this for the R2 incremental cache plus a tag cache.
import { defineCloudflareConfig } from "@opennextjs/cloudflare/config";
import staticAssetsIncrementalCache from "@opennextjs/cloudflare/overrides/incremental-cache/static-assets-incremental-cache";

export default defineCloudflareConfig({
  incrementalCache: staticAssetsIncrementalCache,
});
