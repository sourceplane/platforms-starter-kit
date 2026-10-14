import { beforeEach, describe, expect, it, vi } from "vitest";
import { fakeKv, type FakeKv } from "./fake-kv";

// lib/subdomains.ts is upstream's data access, untouched; these tests show
// it behaves over KV as it did over Redis.

let kv: FakeKv;
vi.mock("@opennextjs/cloudflare", () => ({
  getCloudflareContext: () => ({ env: { KV: kv } }),
}));

describe("subdomains (lib/subdomains.ts)", () => {
  beforeEach(() => {
    kv = fakeKv(100);
  });

  it("reads a tenant by its sanitised name", async () => {
    const { getSubdomainData } = await import("@/lib/subdomains");
    kv.store.set("subdomain:acme", JSON.stringify({ emoji: "🚀", createdAt: 42 }));
    expect(await getSubdomainData("ACME")).toEqual({ emoji: "🚀", createdAt: 42 });
    expect(await getSubdomainData("ac.me")).toEqual({ emoji: "🚀", createdAt: 42 });
    expect(await getSubdomainData("nope")).toBeNull();
  });

  it("lists every tenant with the fallback emoji for a damaged record", async () => {
    const { getAllSubdomains } = await import("@/lib/subdomains");
    kv.store.set("subdomain:acme", JSON.stringify({ emoji: "🚀", createdAt: 42 }));
    kv.store.set("subdomain:beta", JSON.stringify({ createdAt: 7 }));
    kv.store.set("unrelated", JSON.stringify({ emoji: "x" }));
    const all = await getAllSubdomains();
    expect(all.map((t) => t.subdomain).sort()).toEqual(["acme", "beta"]);
    expect(all.find((t) => t.subdomain === "acme")).toEqual({
      subdomain: "acme",
      emoji: "🚀",
      createdAt: 42,
    });
    expect(all.find((t) => t.subdomain === "beta")?.emoji).toBe("❓");
  });

  it("returns an empty list when there are no tenants", async () => {
    const { getAllSubdomains } = await import("@/lib/subdomains");
    expect(await getAllSubdomains()).toEqual([]);
  });

  it("validates icons as upstream does", async () => {
    const { isValidIcon } = await import("@/lib/subdomains");
    expect(isValidIcon("🚀")).toBe(true);
    expect(isValidIcon("🐙🐙")).toBe(true);
    // Upstream measures UTF-16 code units: a ZWJ family sequence is 11.
    expect(isValidIcon("👨‍👩‍👧‍👦")).toBe(false);
    expect(isValidIcon("")).toBe(false);
    expect(isValidIcon("a".repeat(11))).toBe(false);
  });
});
