import { describe, expect, it } from "vitest";
import nextConfig from "../next.config";

describe("security headers",()=>{
  it("sets the required browser protections globally",async()=>{
    const rules=await nextConfig.headers?.();
    const headers=new Map(rules?.[0]?.headers.map((header)=>[header.key,header.value]));
    expect(headers.get("Content-Security-Policy")).toContain("frame-ancestors 'none'");
    expect(headers.get("Content-Security-Policy")).toContain("object-src 'none'");
    expect(headers.get("Strict-Transport-Security")).toContain("max-age=63072000");
    expect(headers.get("X-Content-Type-Options")).toBe("nosniff");
    expect(headers.get("X-Frame-Options")).toBe("DENY");
    expect(headers.get("Permissions-Policy")).toContain("camera=(self)");
  });
});
