import { NextResponse } from "next/server";
import { requireApiAuth } from "@/lib/apiAuth";
import { rpcError } from "@/lib/apiError";
import { getSupabase } from "@/lib/supabase";

export async function GET(request: Request) {
  const auth = await requireApiAuth(request);
  if (!auth) return NextResponse.json({ error: "Unauthorized or expired session" }, { status: 401 });
  const { data, error } = await getSupabase().rpc("secure_get_borrower_options", { p_token: auth.token });
  if (error) return rpcError("borrowers.list", error)!;
  return NextResponse.json({ data: data ?? [] });
}
