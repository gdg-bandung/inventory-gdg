import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { verifyAppJwt } from "@/lib/jwt";

export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;
  if (pathname === "/api/auth/login") return NextResponse.next();
  if (pathname.startsWith("/api/")) {
    const authorization = request.headers.get("authorization");
    try {
      if (!authorization?.startsWith("Bearer ")) throw new Error("JWT diperlukan");
      verifyAppJwt(authorization.slice(7));
      return NextResponse.next();
    } catch {
      return NextResponse.json({ error: "Unauthorized or expired JWT" }, { status: 401 });
    }
  }
  if (pathname === "/login") return NextResponse.next();
  if (!request.cookies.get("inv_session")?.value) {
    return NextResponse.redirect(new URL("/login", request.url));
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
