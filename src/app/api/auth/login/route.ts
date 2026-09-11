import { NextResponse } from "next/server";
import { getSupabase } from "@/lib/supabase";
import { SESSION_COOKIE } from "@/lib/session";
import { signAppJwt } from "@/lib/jwt";

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const username = String(body.username ?? "").trim();
    const password = String(body.password ?? "");
    if (!username || !password) return NextResponse.json({ error: "Username dan password wajib diisi" }, { status: 400 });

    const { data, error } = await getSupabase().rpc("secure_login", { p_username: username, p_password: password }).maybeSingle();
    if (error) throw error;
    if (!data) return NextResponse.json({ error: "Username atau password salah" }, { status: 401 });
    const row = data as { token: string; username: string; full_name: string | null; role?: "admin"|"member"; expires_at: string };
    const user = { username: row.username, full_name: row.full_name, role: row.role ?? "member", expires_at: row.expires_at };
    const response = NextResponse.json({ user, jwt: signAppJwt(user) });
    response.cookies.set(SESSION_COOKIE, row.token, {
      httpOnly: true,
      sameSite: "lax",
      secure: process.env.NODE_ENV === "production",
      path: "/",
      maxAge: 60 * 60 * 24 * 7,
    });
    return response;
  } catch (error) {
    console.error("[inventory:auth.login]", error instanceof Error ? error.message : error);
    return NextResponse.json({ error: "Tidak dapat masuk. Periksa koneksi lalu coba lagi." }, { status: 500 });
  }
}
