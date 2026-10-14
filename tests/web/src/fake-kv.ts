// A Workers KV namespace in a Map: the four methods lib/redis.ts uses, with
// KV's own list shape (`keys`, `list_complete`, `cursor`) and a small page so
// the adapter's cursor loop is exercised.
export type FakeKv = {
  store: Map<string, string>;
  get: (key: string, type: "json") => Promise<unknown>;
  put: (key: string, value: string) => Promise<void>;
  delete: (key: string) => Promise<void>;
  list: (options: { prefix?: string; cursor?: string }) => Promise<{
    keys: { name: string }[];
    list_complete: boolean;
    cursor?: string;
  }>;
  calls: { list: { prefix?: string; cursor?: string }[] };
};

export function fakeKv(pageSize = 2): FakeKv {
  const store = new Map<string, string>();
  const calls: FakeKv["calls"] = { list: [] };
  return {
    store,
    calls,
    async get(key, type) {
      const raw = store.get(key);
      if (raw === undefined) return null;
      return type === "json" ? JSON.parse(raw) : raw;
    },
    async put(key, value) {
      store.set(key, value);
    },
    async delete(key) {
      store.delete(key);
    },
    async list(options) {
      calls.list.push(options);
      const names = [...store.keys()]
        .filter((name) => !options.prefix || name.startsWith(options.prefix))
        .sort();
      const start = options.cursor ? Number(options.cursor) : 0;
      const page = names.slice(start, start + pageSize);
      const done = start + pageSize >= names.length;
      return {
        keys: page.map((name) => ({ name })),
        list_complete: done,
        ...(done ? {} : { cursor: String(start + pageSize) }),
      };
    },
  };
}
