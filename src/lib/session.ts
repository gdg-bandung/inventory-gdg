import { cookies } from "next/headers";
import { getSupabase } from "./supabase";
import type { SessionUser } from "@/components/inventory/types";

export const SESSION_COOKIE = "inv_session";

export async function getSessionToken() {
  return (await cookies()).get(SESSION_COOKIE)?.value ?? null;
}

export async function getSessionUser(): Promise<SessionUser | null> {
  const token = await getSessionToken();
  if (!token) return null;
  try {
    const { data, error } = await getSupabase().rpc("secure_me", { p_token: token }).maybeSingle();
    if (error || !data) return null;
    return data as SessionUser;
  } catch {
    return null;
  }
}
