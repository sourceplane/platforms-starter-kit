import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

// proxy.ts is upstream's subdomain router: it reads the host, decides whether
// the request is for a tenant, and rewrites `/` on a tenant host to
// `/s/<tenant>` (and keeps `/admin` off tenant hosts). It never touches the
// store, so on Cloudflare it is the same pure rewrite inside the Worker.

// A request the way a server sees it: the Host header carries the hostname.
function request(url: string, host?: string) {
  const target = new URL(url);
  return new NextRequest(target, {
    headers: { host: host ?? target.host },
  });
}

describe("extractSubdomain (proxy.ts)", () => {
  beforeEach(() => {
    vi.resetModules();
    process.env.NEXT_PUBLIC_ROOT_DOMAIN = "example.com";
  });

  it("reads the tenant from a localhost URL in development", async () => {
    const { extractSubdomain } = await import("@/proxy");
    expect(extractSubdomain(request("http://acme.localhost:3000/"))).toBe("acme");
    expect(extractSubdomain(request("http://localhost:3000/"))).toBeNull();
    expect(extractSubdomain(request("http://127.0.0.1:3000/"))).toBeNull();
  });

  it("falls back to the host header on localhost", async () => {
    const { extractSubdomain } = await import("@/proxy");
    expect(
      extractSubdomain(request("http://localhost:8793/", "beta.localhost:8793")),
    ).toBe("beta");
  });

  it("reads the tenant under the configured root domain", async () => {
    const { extractSubdomain } = await import("@/proxy");
    expect(extractSubdomain(request("https://acme.example.com/"))).toBe("acme");
    expect(extractSubdomain(request("https://example.com/"))).toBeNull();
    expect(extractSubdomain(request("https://www.example.com/"))).toBeNull();
    expect(extractSubdomain(request("https://acme.other.com/"))).toBeNull();
  });

  it("keeps upstream's Vercel preview convention (tenant---branch.vercel.app)", async () => {
    const { extractSubdomain } = await import("@/proxy");
    expect(extractSubdomain(request("https://acme---feature-x.vercel.app/"))).toBe("acme");
  });
});

describe("proxy (proxy.ts)", () => {
  beforeEach(() => {
    vi.resetModules();
    process.env.NEXT_PUBLIC_ROOT_DOMAIN = "example.com";
  });

  it("rewrites the root of a tenant host to the tenant page", async () => {
    const { proxy } = await import("@/proxy");
    const res = await proxy(request("https://acme.example.com/"));
    expect(res.headers.get("x-middleware-rewrite")).toBe("https://acme.example.com/s/acme");
  });

  it("sends /admin on a tenant host back to the tenant root", async () => {
    const { proxy } = await import("@/proxy");
    const res = await proxy(request("https://acme.example.com/admin"));
    expect(res.status).toBe(307);
    expect(res.headers.get("location")).toBe("https://acme.example.com/");
  });

  it("lets the root domain through untouched", async () => {
    const { proxy } = await import("@/proxy");
    for (const path of ["/", "/admin"]) {
      const res = await proxy(request(`https://example.com${path}`));
      expect(res.headers.get("x-middleware-next"), path).toBe("1");
      expect(res.headers.get("x-middleware-rewrite"), path).toBeNull();
    }
  });
});
