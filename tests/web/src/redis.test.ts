import { beforeEach, describe, expect, it, vi } from "vitest";
import { fakeKv, type FakeKv } from "./fake-kv";

// lib/redis.ts is the port's one new module: the Upstash client's surface
// (`get`, `set`, `del`, `keys`, `mget`) over the Worker's `KV` binding, with
// the same key names and JSON records, so the template's data access stays
// as written.

let kv: FakeKv;
vi.mock("@opennextjs/cloudflare", () => ({
  getCloudflareContext: () => ({ env: { KV: kv } }),
}));

describe("redis (lib/redis.ts) over Workers KV", () => {
  beforeEach(() => {
    kv = fakeKv(2);
  });

  it("stores a record as JSON under the key the template uses and reads it back", async () => {
    const { redis } = await import("@/lib/redis");
    const record = { emoji: "🚀", createdAt: 1700000000000 };
    expect(await redis.set("subdomain:acme", record)).toBe("OK");
    expect(kv.store.get("subdomain:acme")).toBe(JSON.stringify(record));
    expect(await redis.get<typeof record>("subdomain:acme")).toEqual(record);
  });

  it("returns null for a key that was never written", async () => {
    const { redis } = await import("@/lib/redis");
    expect(await redis.get("subdomain:nope")).toBeNull();
  });

  it("lists keys by prefix, following KV's cursor across pages", async () => {
    const { redis } = await import("@/lib/redis");
    for (const name of ["acme", "beta", "gamma", "delta", "eps"]) {
      await redis.set(`subdomain:${name}`, { emoji: "✨", createdAt: 1 });
    }
    await redis.set("other:thing", { x: 1 });
    const keys = await redis.keys("subdomain:*");
    expect(keys.sort()).toEqual([
      "subdomain:acme",
      "subdomain:beta",
      "subdomain:delta",
      "subdomain:eps",
      "subdomain:gamma",
    ]);
    expect(kv.calls.list.length).toBe(3);
    expect(kv.calls.list[0]).toEqual({ prefix: "subdomain:", cursor: undefined });
    expect(kv.calls.list[1]?.cursor).toBe("2");
  });

  it("refuses a glob KV cannot answer", async () => {
    const { redis } = await import("@/lib/redis");
    await expect(redis.keys("subdomain:a*c")).rejects.toThrow(/prefix/);
    await expect(redis.keys("subdomain:acme")).rejects.toThrow(/prefix/);
  });

  it("deletes keys and reports how many it was asked to delete", async () => {
    const { redis } = await import("@/lib/redis");
    await redis.set("subdomain:acme", { emoji: "🚀", createdAt: 1 });
    expect(await redis.del("subdomain:acme", "subdomain:ghost")).toBe(2);
    expect(await redis.get("subdomain:acme")).toBeNull();
  });

  it("mget keeps the order of the keys and yields null for the missing ones", async () => {
    const { redis } = await import("@/lib/redis");
    await redis.set("subdomain:acme", { emoji: "🚀", createdAt: 1 });
    await redis.set("subdomain:beta", { emoji: "🐙", createdAt: 2 });
    const values = await redis.mget<{ emoji: string; createdAt: number }[]>(
      "subdomain:beta",
      "subdomain:missing",
      "subdomain:acme",
    );
    expect(values).toEqual([
      { emoji: "🐙", createdAt: 2 },
      null,
      { emoji: "🚀", createdAt: 1 },
    ]);
  });

  it("says what is wrong when the binding is absent", async () => {
    kv = undefined as unknown as FakeKv;
    const { redis } = await import("@/lib/redis");
    await expect(redis.get("subdomain:acme")).rejects.toThrow(/KV binding is missing/);
  });
});
