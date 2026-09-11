import { NextResponse } from "next/server";
import { getSupabase } from "@/lib/supabase";
import { requireApiAuth } from "@/lib/apiAuth";
import { rpcError } from "@/lib/apiError";

export async function GET(request: Request) {
  const auth = await requireApiAuth(request);
  if (!auth) return NextResponse.json({ error: "Unauthorized or expired session" }, { status: 401 });
  const { data, error } = await getSupabase().rpc("secure_get_inventory_audit_logs", { p_token: auth.token });
  return rpcError("audit.list", error) ?? NextResponse.json({ data });
}
