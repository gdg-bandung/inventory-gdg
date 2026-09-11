import { NextResponse } from "next/server";
import { getSupabase } from "@/lib/supabase";
import { SESSION_COOKIE } from "@/lib/session";
import { requireApiAuth } from "@/lib/apiAuth";

export async function POST(request: Request) {
  const auth = await requireApiAuth(request);
  if (auth) {
    try { await getSupabase().rpc("secure_logout", { p_token: auth.token }); } catch { /* cookie tetap dihapus */ }
  }
  const response = auth
    ? NextResponse.json({ ok: true })
    : NextResponse.json({ error: "Unauthorized or expired session" }, { status: 401 });
  response.cookies.set(SESSION_COOKIE, "", { httpOnly: true, sameSite: "lax", path: "/", maxAge: 0 });
  return response;
}
