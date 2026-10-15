import { describe, expect, it } from "vitest";
import { SITE_NAME } from "@/app/site";

// The identity seam a product's bootstrap rewrites: one literal, on one line.
describe("site identity (apps/web/app/site.ts)", () => {
  it("names the site", () => {
    expect(SITE_NAME.trim()).not.toBe("");
  });
});
