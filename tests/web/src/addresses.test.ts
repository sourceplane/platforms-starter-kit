import { afterEach, describe, expect, it, vi } from "vitest";

// lib/addresses.ts decides, per request host, whether a tenant is a subdomain
// of the root domain (upstream's model) or a path on the host the request
// came in on — the only thing that works on workers.dev, where
// `<tenant>.<worker>.<account>.workers.dev` does not resolve.
//
// rootDomain is read from NEXT_PUBLIC_ROOT_DOMAIN when lib/utils.ts loads, so
// every case sets it and imports afresh.
async function load(root: string | undefined, nodeEnv = "production") {
  vi.resetModules();
  if (root === undefined) delete process.env.NEXT_PUBLIC_ROOT_DOMAIN;
  else process.env.NEXT_PUBLIC_ROOT_DOMAIN = root;
  vi.stubEnv("NODE_ENV", nodeEnv);
  return import("@/lib/addresses");
}
afterEach(() => {
  vi.unstubAllEnvs();
  delete process.env.NEXT_PUBLIC_ROOT_DOMAIN;
});

describe("onRootDomain (lib/addresses.ts)", () => {
  it("is the root domain, www and any subdomain of it, whatever the port", async () => {
    const { onRootDomain } = await load("tenants.acme.dev");
    for (const host of ["tenants.acme.dev", "www.tenants.acme.dev", "t1.tenants.acme.dev", "T1.Tenants.Acme.Dev:443"]) {
      expect(onRootDomain(host), host).toBe(true);
    }
  });

  it("is not workers.dev, wrangler dev, a lookalike or nothing", async () => {
    const { onRootDomain } = await load("tenants.acme.dev");
    for (const host of [
      "acme-platforms-web-prod.acme.workers.dev",
      "127.0.0.1:8787",
      "eviltenants.acme.dev",
      "tenants.acme.dev.evil.com",
      "",
      null,
      undefined,
    ]) {
      expect(onRootDomain(host), String(host)).toBe(false);
    }
  });

  it("matches a root domain with a port only on that port (localhost:3000, the default)", async () => {
    const { onRootDomain } = await load(undefined);
    expect(onRootDomain("localhost:3000")).toBe(true);
    expect(onRootDomain("acme.localhost:3000")).toBe(true);
    // opennextjs-cloudflare preview / wrangler dev on another port: the
    // subdomain link would point at a server that is not there.
    expect(onRootDomain("localhost:8787")).toBe(false);
  });
});

describe("tenant links (lib/addresses.ts)", () => {
  it("on the root domain: the tenant's subdomain, as upstream", async () => {
    const { tenantUrl, tenantAddress, homeUrl, siteAddress } = await load("tenants.acme.dev");
    expect(tenantUrl("t1", "tenants.acme.dev")).toBe("https://t1.tenants.acme.dev");
    expect(tenantUrl("t1", "t2.tenants.acme.dev")).toBe("https://t1.tenants.acme.dev");
    expect(tenantAddress("t1", "tenants.acme.dev")).toBe("t1.tenants.acme.dev");
    expect(homeUrl("t2.tenants.acme.dev")).toBe("https://tenants.acme.dev");
    expect(siteAddress("t2.tenants.acme.dev")).toBe("tenants.acme.dev");
  });

  it("on workers.dev: a path on the same host, which answers today", async () => {
    const { tenantUrl, tenantAddress, homeUrl, siteAddress } = await load("tenants.acme.dev");
    const host = "acme-platforms-web-prod.acme.workers.dev";
    expect(tenantUrl("t1", host)).toBe("/s/t1");
    expect(tenantAddress("t1", host)).toBe(`${host}/s/t1`);
    expect(homeUrl(host)).toBe("/");
    expect(siteAddress(host)).toBe(host);
  });

  it("in local development: http subdomains of localhost", async () => {
    const { tenantUrl } = await load(undefined, "development");
    expect(tenantUrl("t1", "localhost:3000")).toBe("http://t1.localhost:3000");
    expect(tenantUrl("t1", "127.0.0.1:8787")).toBe("/s/t1");
  });

  it("without a host, says what upstream says rather than guess one", async () => {
    const { tenantAddress, siteAddress } = await load("tenants.acme.dev");
    expect(tenantAddress("t1", null)).toBe("t1.tenants.acme.dev");
    expect(siteAddress(null)).toBe("tenants.acme.dev");
  });
});

describe("requestHost (lib/addresses.ts)", () => {
  it("prefers the forwarded host, first of a list, then the Host header", async () => {
    const { requestHost } = await load("tenants.acme.dev");
    expect(requestHost(new Headers({ host: "127.0.0.1:8787" }))).toBe("127.0.0.1:8787");
    expect(
      requestHost(new Headers({ host: "internal", "x-forwarded-host": "t1.tenants.acme.dev, proxy" })),
    ).toBe("t1.tenants.acme.dev");
    expect(requestHost(new Headers({}))).toBeNull();
  });
});
