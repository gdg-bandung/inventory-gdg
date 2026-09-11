import { NextResponse } from "next/server";

export function rpcError(scope: string, error: { message: string; code?: string } | null, fallbackStatus = 400) {
  if (!error) return null;
  console.error(`[inventory:${scope}]`, { code: error.code, message: error.message });
  return NextResponse.json({ error: error.message }, { status: error.message.includes("Unauthorized") ? 401 : fallbackStatus });
}
