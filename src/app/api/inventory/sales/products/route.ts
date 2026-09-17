import { NextResponse } from "next/server";
import { getSupabase } from "@/lib/supabase";
import { requireApiAuth } from "@/lib/apiAuth";
import { rpcError } from "@/lib/apiError";

function unauthorized() { return NextResponse.json({ error: "Unauthorized or expired session" }, { status: 401 }); }

export async function GET(request: Request) {
  const auth = await requireApiAuth(request); if (!auth) return unauthorized();
  const { data, error } = await getSupabase().rpc("secure_get_inventory_sale_products", { p_token: auth.token });
  if (error) return rpcError("sale-products.list", error)!;
  return NextResponse.json({ data });
}
export async function POST(request: Request) {
  const auth = await requireApiAuth(request); if (!auth) return unauthorized();
  if (auth.jwt.role !== "admin") return NextResponse.json({ error: "Hanya admin yang dapat mengatur katalog penjualan" }, { status: 403 });
  const body = await request.json() as { item_id: string; unit_price: number; default_quantity: number };
  const { data, error } = await getSupabase().rpc("secure_save_inventory_sale_product", { p_token: auth.token, p_item_id: body.item_id, p_unit_price: body.unit_price, p_default_quantity: body.default_quantity });
  if (error) return rpcError("sale-products.save", error)!;
  if (!data) return unauthorized();
  return NextResponse.json({ id: data });
}
export async function DELETE(request: Request) {
  const auth = await requireApiAuth(request); if (!auth) return unauthorized();
  if (auth.jwt.role !== "admin") return NextResponse.json({ error: "Hanya admin yang dapat mengatur katalog penjualan" }, { status: 403 });
  const id = new URL(request.url).searchParams.get("item_id"); if (!id) return NextResponse.json({ error: "ID barang tidak valid" }, { status: 400 });
  const { data, error } = await getSupabase().rpc("secure_delete_inventory_sale_product", { p_token: auth.token, p_item_id: id });
  if (error) return rpcError("sale-products.delete", error)!;
  if (!data) return NextResponse.json({ error: "Barang tidak ada di katalog" }, { status: 404 });
  return NextResponse.json({ ok: true });
}
