import { NextResponse } from "next/server";
import { getSupabase } from "@/lib/supabase";
import { requireApiAuth } from "@/lib/apiAuth";
import { rpcError } from "@/lib/apiError";
import type { SaleInput } from "@/components/inventory/types";

function unauthorized() { return NextResponse.json({ error: "Unauthorized or expired session" }, { status: 401 }); }

export async function GET(request: Request) {
  const auth = await requireApiAuth(request); if (!auth) return unauthorized();
  const { data, error } = await getSupabase().rpc("secure_get_inventory_sales", { p_token: auth.token });
  if (error) return rpcError("sales.list", error)!;
  return NextResponse.json({ data });
}

export async function POST(request: Request) {
  const auth = await requireApiAuth(request); if (!auth) return unauthorized();
  const body = await request.json() as SaleInput;
  const { data, error } = await getSupabase().rpc("secure_create_inventory_sale", {
    p_token: auth.token, p_item_id: body.item_id, p_quantity: body.quantity, p_unit_price: body.unit_price,
    p_sale_date: body.sale_date, p_customer_name: body.customer_name ?? null, p_notes: body.notes ?? null,
  });
  if (error) return rpcError("sales.create", error)!;
  if (!data) return unauthorized();
  return NextResponse.json({ id: data });
}

export async function DELETE(request: Request) {
  const auth = await requireApiAuth(request); if (!auth) return unauthorized();
  if (auth.jwt.role !== "admin") return NextResponse.json({ error: "Hanya admin yang dapat membatalkan penjualan" }, { status: 403 });
  const params = new URL(request.url).searchParams; const id = params.get("id"); const reason = params.get("reason")?.trim();
  if (!id || !reason) return NextResponse.json({ error: "ID dan alasan pembatalan wajib diisi" }, { status: 400 });
  const { data, error } = await getSupabase().rpc("secure_cancel_inventory_sale", { p_token: auth.token, p_id: id, p_reason: reason });
  if (error) return rpcError("sales.cancel", error)!;
  if (!data) return unauthorized();
  return NextResponse.json({ ok: true });
}
