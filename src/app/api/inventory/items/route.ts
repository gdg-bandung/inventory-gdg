import { NextResponse } from "next/server";
import { getSupabase } from "@/lib/supabase";
import { requireApiAuth } from "@/lib/apiAuth";
import type { ItemInput } from "@/components/inventory/types";
import { rpcError } from "@/lib/apiError";

function unauthorized() { return NextResponse.json({ error: "Unauthorized or expired session" }, { status: 401 }); }

export async function GET(request: Request) {
  const auth = await requireApiAuth(request);
  if (!auth) return unauthorized();
  const { data, error } = await getSupabase().rpc("secure_get_inventory_items", { p_token: auth.token });
  if (error) return rpcError("items.list", error)!;
  return NextResponse.json({ data });
}

export async function POST(request: Request) {
  const auth = await requireApiAuth(request);
  if (!auth) return unauthorized();
  if (auth.jwt.role !== "admin") return NextResponse.json({ error: "Hanya admin yang dapat mengelola master barang" }, { status: 403 });
  const body = await request.json() as ItemInput;
  const { data, error } = await getSupabase().rpc("secure_save_inventory_item", {
    p_token: auth.token, p_id: body.id ?? null, p_name: body.name, p_category: body.category,
    p_code: body.code, p_unit: body.unit, p_initial_stock: body.initial_stock,
    p_min_stock: body.min_stock, p_condition: body.condition ?? null, p_location: body.location ?? null,
    p_purchase_price: body.purchase_price ?? null, p_purchase_date: body.purchase_date || null,
    p_expiry_date: body.expiry_date || null, p_owner_division: body.owner_division ?? null,
    p_penanggung_jawab: body.penanggung_jawab ?? null, p_notes: body.notes ?? null,
    p_is_archived: body.is_archived ?? false,
  });
  if (error) return rpcError("items.save", error)!;
  if (!data) return unauthorized();
  return NextResponse.json({ id: data });
}

export async function DELETE(request: Request) {
  const auth = await requireApiAuth(request);
  if (!auth) return unauthorized();
  if (auth.jwt.role !== "admin") return NextResponse.json({ error: "Hanya admin yang dapat menghapus barang" }, { status: 403 });
  const id = new URL(request.url).searchParams.get("id");
  if (!id) return NextResponse.json({ error: "ID barang tidak valid" }, { status: 400 });
  const { data, error } = await getSupabase().rpc("secure_delete_inventory_item", { p_token: auth.token, p_id: id });
  if (error) return rpcError("items.delete", error)!;
  if (!data) return unauthorized();
  return NextResponse.json({ ok: true });
}
