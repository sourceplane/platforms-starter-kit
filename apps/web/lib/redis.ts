// The template keeps its tenants in Upstash Redis through `@upstash/redis`:
// `subdomain:<name>` → `{ emoji, createdAt }`. On Cloudflare the store is
// Workers KV, bound to the Worker as `KV` (wrangler.template.jsonc) and
// reached through `getCloudflareContext()`. This module keeps the client's
// surface — `redis.get / set / del / keys / mget`, the same key names, the
// same JSON records — so `lib/subdomains.ts` and `app/actions.ts` stay as
// upstream wrote them.
//
// Only what the template uses is implemented. `keys()` is the one command
// without a KV equivalent: Redis takes a glob, KV lists by prefix, so the
// pattern must be `<prefix>*` (the template's is `subdomain:*`).
import { getCloudflareContext } from '@opennextjs/cloudflare';

function kv(): KVNamespace {
  const { env } = getCloudflareContext();
  if (!env.KV) {
    throw new Error(
      'The KV binding is missing. Render wrangler.jsonc first (pnpm run wire:fixture) so wrangler can bind a namespace.'
    );
  }
  return env.KV;
}

export const redis = {
  async get<TData = unknown>(key: string): Promise<TData | null> {
    return kv().get<TData>(key, 'json');
  },

  async set<TData = unknown>(key: string, value: TData): Promise<'OK'> {
    await kv().put(key, JSON.stringify(value));
    return 'OK';
  },

  async del(...keys: string[]): Promise<number> {
    const store = kv();
    await Promise.all(keys.map((key) => store.delete(key)));
    return keys.length;
  },

  async keys(pattern: string): Promise<string[]> {
    if (!pattern.endsWith('*') || pattern.slice(0, -1).includes('*')) {
      throw new Error(
        `KV lists keys by prefix: expected a "<prefix>*" pattern, got "${pattern}"`
      );
    }
    const prefix = pattern.slice(0, -1);
    const store = kv();
    const names: string[] = [];
    let cursor: string | undefined;
    do {
      const page = await store.list({ prefix, cursor });
      names.push(...page.keys.map((entry) => entry.name));
      cursor = page.list_complete ? undefined : page.cursor;
    } while (cursor);
    return names;
  },

  async mget<TData extends unknown[]>(
    ...keys: string[]
  ): Promise<{ [K in keyof TData]: TData[K] | null }> {
    const values = await Promise.all(keys.map((key) => this.get(key)));
    return values as { [K in keyof TData]: TData[K] | null };
  }
};
