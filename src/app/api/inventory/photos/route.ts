import { NextResponse } from "next/server";
import { getSupabase } from "@/lib/supabase";
import { requireApiAuth } from "@/lib/apiAuth";
import { rpcError } from "@/lib/apiError";

const unauthorized = () => NextResponse.json({ error: "Unauthorized or expired session" }, { status: 401 });

export async function GET(request: Request) {
  const auth = await requireApiAuth(request); if (!auth) return unauthorized();
  const itemId = new URL(request.url).searchParams.get("item_id");
  if (!itemId) return NextResponse.json({ error: "ID barang tidak valid" }, { status: 400 });
  const { data, error } = await getSupabase().rpc("secure_get_inventory_item_photos", { p_token: auth.token, p_item_id: itemId });
  return rpcError("photos.list", error) ?? NextResponse.json({ data });
}

export async function POST(request: Request) {
  const auth = await requireApiAuth(request); if (!auth) return unauthorized();
  const body = await request.json();
  if (typeof body.data_url !== "string" || body.data_url.length > 2_800_000) return NextResponse.json({ error: "Foto maksimal sekitar 2 MB" }, { status: 400 });
  const { data, error } = await getSupabase().rpc("secure_save_inventory_item_photo", { p_token: auth.token, p_item_id: body.item_id, p_data_url: body.data_url, p_caption: body.caption ?? null });
  const failure = rpcError("photos.save", error); if (failure) return failure;
  if (!data) return unauthorized(); return NextResponse.json({ id: data });
}

export async function DELETE(request: Request) {
  const auth = await requireApiAuth(request); if (!auth) return unauthorized();
  const id = new URL(request.url).searchParams.get("id"); if (!id) return NextResponse.json({ error: "ID foto tidak valid" }, { status: 400 });
  const { data, error } = await getSupabase().rpc("secure_delete_inventory_item_photo", { p_token: auth.token, p_id: id });
  const failure = rpcError("photos.delete", error); if (failure) return failure;
  if (!data) return unauthorized(); return NextResponse.json({ ok: true });
}
