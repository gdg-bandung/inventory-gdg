import { NextResponse } from "next/server";
import { getSupabase } from "@/lib/supabase";
import type { TransactionInput } from "@/components/inventory/types";
import { rpcError } from "@/lib/apiError";
import { requireApiAuth } from "@/lib/apiAuth";

function unauthorized() { return NextResponse.json({ error: "Unauthorized or expired session" }, { status: 401 }); }

export async function GET(request: Request) {
  const auth = await requireApiAuth(request);
  if (!auth) return unauthorized();
  const { data, error } = await getSupabase().rpc("secure_get_inventory_transactions", { p_token: auth.token });
  if (error) return rpcError("transactions.list", error)!;
  return NextResponse.json({ data });
}

export async function POST(request: Request) {
  const auth = await requireApiAuth(request);
  if (!auth) return unauthorized();
  const body = await request.json() as TransactionInput;
  if (body.id && auth.jwt.role !== "admin") return NextResponse.json({ error: "Hanya admin yang dapat mengubah catatan lama" }, { status: 403 });
  if (!body.id && auth.jwt.role !== "admin" && !["Masuk", "Keluar", "Kembali"].includes(body.type)) {
    return NextResponse.json({ error: "Jenis catatan ini hanya dapat dibuat admin" }, { status: 403 });
  }
  const { data, error } = await getSupabase().rpc("secure_save_inventory_transaction", {
    p_token: auth.token, p_id: body.id ?? null, p_item_id: body.item_id, p_type: body.type,
    p_quantity: body.quantity, p_transaction_date: body.transaction_date,
    p_is_returnable: body.is_returnable ?? false, p_expected_return_date: body.expected_return_date || null,
    p_activity_name: body.activity_name ?? null, p_notes: body.notes ?? null,
    p_related_loan_id: body.related_loan_id ?? null, p_borrower_user_id: body.borrower_user_id ?? null,
    p_external_borrower_name: body.external_borrower_name ?? null,
  });
  if (error) return rpcError("transactions.save", error)!;
  if (!data) return unauthorized();
  return NextResponse.json({ id: data });
}

export async function DELETE(request: Request) {
  const auth = await requireApiAuth(request);
  if (!auth) return unauthorized();
  if (auth.jwt.role !== "admin") return NextResponse.json({ error: "Hanya admin yang dapat membatalkan transaksi" }, { status: 403 });
  const params = new URL(request.url).searchParams;
  const id = params.get("id");
  const reason = params.get("reason")?.trim();
  if (!id) return NextResponse.json({ error: "ID catatan tidak valid" }, { status: 400 });
  if (!reason) return NextResponse.json({ error: "Alasan pembatalan wajib diisi" }, { status: 400 });
  const { data, error } = await getSupabase().rpc("secure_reverse_inventory_transaction", { p_token: auth.token, p_id: id, p_reason: reason });
  if (error) return rpcError("transactions.reverse", error)!;
  if (!data) return unauthorized();
  return NextResponse.json({ ok: true, reversal_id: data });
}
