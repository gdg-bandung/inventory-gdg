"use client";

import { useEffect, useMemo, useState } from "react";
import { AlertTriangle, ArrowRight, Loader2, RotateCcw } from "lucide-react";
import { authHeaders } from "@/lib/clientAuth";
import { ModalShell } from "./ModalShell";
import { useInventory } from "./InventoryContext";
import { formatQty } from "./helpers";
import { movementDelta } from "./inventoryUtils";
import type { BorrowerOption, InventoryItem, InventoryTransaction, TransactionInput, TransactionType } from "./types";

export const TRANSACTION_TYPES: Array<{ value: TransactionType; label: string }> = [
  { value: "Masuk", label: "Barang Masuk" }, { value: "Keluar", label: "Barang Keluar" },
  { value: "Kembali", label: "Barang Kembali" }, { value: "Rusak", label: "Barang Rusak" },
  { value: "Hilang", label: "Barang Hilang" }, { value: "Penyesuaian", label: "Koreksi Stok" },
];

const today = () => new Date().toISOString().slice(0, 10);
const base: TransactionInput = { item_id: "", type: "Keluar", quantity: 1, transaction_date: today(), is_returnable: false, expected_return_date: "", activity_name: "", notes: "", related_loan_id: null, borrower_user_id: null, external_borrower_name: "" };

export function InventoryTransactionModal({ open, transaction, initialItem, initialType, onClose }: { open: boolean; transaction?: InventoryTransaction | null; initialItem?: InventoryItem | null; initialType?: TransactionType; onClose: () => void }) {
  const { items, transactions, saveTransaction, toast, user } = useInventory();
  const [form, setForm] = useState<TransactionInput>(base);
  const [borrowers, setBorrowers] = useState<BorrowerOption[]>([]);
  const [borrowerMode, setBorrowerMode] = useState("");
  const [physicalCount, setPhysicalCount] = useState(0);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  const selectedItem = items.find((row) => row.id === form.item_id) ?? initialItem ?? null;
  const activityNames = useMemo(() => [...new Set(transactions.map((row) => row.activity_name).filter(Boolean) as string[])].sort(), [transactions]);
  const existingDelta = transaction && !transaction.reversed_at ? movementDelta(transaction.type, Number(transaction.quantity), transaction.related_loan_id) : 0;
  const stockBefore = selectedItem ? Number(selectedItem.current_stock) - existingDelta : 0;
  const correction = physicalCount - stockBefore;
  const storedQuantity = form.type === "Penyesuaian" ? correction : Number(form.quantity);
  const stockAfter = selectedItem ? stockBefore + movementDelta(form.type, storedQuantity, form.related_loan_id) : 0;
  const allowedTypes = user.role === "admin" ? TRANSACTION_TYPES : TRANSACTION_TYPES.filter((row) => ["Masuk", "Keluar", "Kembali"].includes(row.value));
  const loanOptions = useMemo(() => transactions.filter((row) => row.type === "Keluar" && row.is_returnable && !row.reversed_at).map((loan) => {
    const closed = transactions.filter((row) => row.related_loan_id === loan.id && row.id !== transaction?.id && !row.reversed_at).reduce((sum, row) => sum + Math.abs(Number(row.quantity)), 0);
    return { ...loan, remaining: Number(loan.quantity) - closed };
  }).filter((loan) => loan.remaining > 0 || loan.id === transaction?.related_loan_id), [transactions, transaction]);
  const selectedLoan = loanOptions.find((loan) => loan.id === form.related_loan_id);
  const willOverReturn = Boolean(selectedLoan && Number(form.quantity) > selectedLoan.remaining);

  useEffect(() => {
    if (!open) return;
    void fetch("/api/inventory/borrowers", { headers: authHeaders() }).then(async (response) => {
      const payload = await response.json().catch(() => ({}));
      if (response.ok) setBorrowers(payload.data ?? []);
    });
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const item = initialItem ?? (transaction ? items.find((row) => row.id === transaction.item_id) : null);
    const requestedType = initialType ?? transaction?.type ?? "Keluar";
    const type = user.role === "admin" || ["Masuk", "Keluar", "Kembali"].includes(requestedType) ? requestedType : "Keluar";
    const next: TransactionInput = transaction ? {
      id: transaction.id, item_id: transaction.item_id, type: transaction.type, quantity: transaction.quantity,
      transaction_date: transaction.transaction_date, is_returnable: transaction.is_returnable,
      expected_return_date: transaction.expected_return_date, activity_name: transaction.activity_name,
      notes: transaction.notes, related_loan_id: transaction.related_loan_id,
      borrower_user_id: transaction.borrower_user_id, external_borrower_name: transaction.external_borrower_name,
    } : { ...base, item_id: item?.id ?? "", type, transaction_date: today(), is_returnable: type === "Keluar" && item?.category === "Barang Tetap" };
    setForm(next);
    setBorrowerMode(next.borrower_user_id ?? (next.external_borrower_name ? "__external" : ""));
    const before = item ? Number(item.current_stock) - existingDelta : 0;
    setPhysicalCount(type === "Penyesuaian" && transaction ? before + Number(transaction.quantity) : before);
    setError("");
  }, [open, transaction, initialItem, initialType, items, user.role, existingDelta]);

  function set<K extends keyof TransactionInput>(key: K, value: TransactionInput[K]) { setForm((current) => ({ ...current, [key]: value })); }
  function chooseItem(id: string) {
    const item = items.find((row) => row.id === id);
    setForm((current) => ({ ...current, item_id: id, is_returnable: current.type === "Keluar" && item?.category === "Barang Tetap", expected_return_date: "", related_loan_id: null, borrower_user_id: null, external_borrower_name: "" }));
    setPhysicalCount(Number(item?.current_stock ?? 0));
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault(); setError("");
    if (!form.item_id) return setError("Pilih barang terlebih dahulu");
    if (form.type === "Kembali" && !form.related_loan_id) return setError("Pilih pinjaman yang dikembalikan");
    if (form.type === "Penyesuaian" && correction === 0) return setError("Hasil hitung fisik sama dengan stok sistem; tidak ada koreksi yang perlu disimpan");
    if (form.type !== "Penyesuaian" && Number(form.quantity) <= 0) return setError("Jumlah harus lebih dari nol");
    if (stockAfter < 0) return setError(`Stok tidak mencukupi: tersisa ${formatQty(stockBefore, selectedItem?.unit)}, diminta ${formatQty(form.quantity, selectedItem?.unit)}`);
    if (willOverReturn) return setError(`Jumlah penyelesaian melebihi sisa pinjaman: ${formatQty(selectedLoan?.remaining ?? 0, selectedItem?.unit)}`);
    if (form.type === "Keluar" && form.is_returnable && !form.expected_return_date) return setError("Tanggal rencana kembali wajib diisi");
    if (form.type === "Keluar" && form.is_returnable && !form.borrower_user_id && !form.external_borrower_name?.trim()) return setError("Pilih akun peminjam atau isi nama peminjam eksternal");
    setSaving(true);
    try {
      await saveTransaction({ ...form, id: transaction?.id ?? null, quantity: storedQuantity,
        is_returnable: form.type === "Keluar" ? Boolean(form.is_returnable) : false,
        expected_return_date: form.type === "Keluar" && form.is_returnable ? form.expected_return_date : null,
        related_loan_id: ["Kembali", "Rusak", "Hilang"].includes(form.type) ? form.related_loan_id : null,
        borrower_user_id: form.type === "Keluar" && form.is_returnable ? form.borrower_user_id : null,
        external_borrower_name: form.type === "Keluar" && form.is_returnable ? form.external_borrower_name?.trim() : null,
      });
      toast(transaction ? "Catatan berhasil diperbarui" : "Catatan keluar-masuk berhasil disimpan"); onClose();
    } catch (err) { setError(err instanceof Error ? err.message : "Gagal menyimpan catatan"); }
    finally { setSaving(false); }
  }

  return <ModalShell open={open} onClose={onClose} title={transaction ? "Ubah catatan" : form.type === "Penyesuaian" ? "Koreksi stok" : "Catat keluar/masuk"} description="Pencatat diambil otomatis dari sesi login; peminjam dicatat terpisah.">
    <form onSubmit={submit}>
      <div className="max-h-[70vh] space-y-5 overflow-y-auto px-5 py-5 sm:px-6">
        {error && <div className="rounded-xl border border-rose-100 bg-rose-50 px-4 py-3 text-sm font-medium text-rose-700">{error}</div>}
        <div><label className="field-label">Barang *</label><select className="field" value={form.item_id} onChange={(e) => chooseItem(e.target.value)} disabled={Boolean(transaction)}><option value="">Pilih barang</option>{items.filter((row) => !row.is_archived || row.id === transaction?.item_id).map((row) => <option key={row.id} value={row.id}>{row.code} — {row.name} ({formatQty(row.current_stock, row.unit)})</option>)}</select></div>
        <div><label className="field-label">Jenis catatan *</label><select className="field" value={form.type} disabled={Boolean(transaction?.stocktake_id)} onChange={(e) => { const type = e.target.value as TransactionType; setForm((current) => ({ ...current, type, is_returnable: type === "Keluar" ? current.is_returnable : false, expected_return_date: type === "Keluar" ? current.expected_return_date : "", related_loan_id: ["Kembali", "Rusak", "Hilang"].includes(type) ? current.related_loan_id : null, borrower_user_id: type === "Keluar" ? current.borrower_user_id : null, external_borrower_name: type === "Keluar" ? current.external_borrower_name : "" })); if (type === "Penyesuaian") setPhysicalCount(stockBefore); }}>{allowedTypes.map((row) => <option key={row.value} value={row.value}>{row.label}</option>)}</select></div>
        {["Kembali", "Rusak", "Hilang"].includes(form.type) && <div><label className="field-label">Terkait pinjaman {form.type === "Kembali" ? "*" : ""}</label><select className="field" value={form.related_loan_id ?? ""} onChange={(e) => { const loan = loanOptions.find((row) => row.id === e.target.value); setForm((current) => ({ ...current, related_loan_id: e.target.value || null, item_id: loan?.item_id ?? current.item_id, activity_name: loan?.activity_name ?? current.activity_name, borrower_user_id: loan?.borrower_user_id ?? null, external_borrower_name: loan?.external_borrower_name ?? "" })); }}><option value="">{form.type === "Kembali" ? "Pilih pinjaman" : `${form.type} di penyimpanan (bukan pinjaman)`}</option>{loanOptions.map((loan) => <option key={loan.id} value={loan.id}>{loan.item_code} — {loan.item_name} · {formatQty(loan.remaining, loan.item_unit)} · {loan.handled_by || "peminjam tidak diketahui"}</option>)}</select>{selectedLoan && <p className="mt-2 text-xs text-slate-500">Sisa pinjaman: <strong>{formatQty(selectedLoan.remaining, selectedLoan.item_unit)}</strong> · peminjam {selectedLoan.handled_by}</p>}</div>}
        {form.type === "Penyesuaian" ? <div className="rounded-2xl border border-amber-200 bg-amber-50 p-4"><div className="flex items-center gap-2 font-semibold text-amber-800"><RotateCcw className="h-4 w-4" />Hitung fisik</div><div className="mt-4 grid grid-cols-[1fr_auto_1fr] items-end gap-3"><div><label className="field-label">Stok sistem</label><div className="field bg-white text-center font-bold">{formatQty(stockBefore, selectedItem?.unit)}</div></div><ArrowRight className="mb-3 h-5 w-5 text-amber-500" /><div><label className="field-label">Hasil fisik *</label><input className="field text-center font-bold" type="number" min="0" step="any" value={physicalCount} onChange={(e) => setPhysicalCount(Number(e.target.value))} /></div></div><p className="mt-3 text-sm text-amber-800">Selisih: <strong>{correction > 0 ? "+" : ""}{formatQty(correction, selectedItem?.unit)}</strong></p></div> : <div><label className="field-label">Jumlah *</label><input className="field" type="number" min="0.01" step="any" value={form.quantity} onChange={(e) => set("quantity", Number(e.target.value))} /></div>}
        {form.type === "Keluar" && <label className="flex items-start gap-3 rounded-xl border border-slate-200 p-4"><input type="checkbox" className="mt-1 h-4 w-4 accent-brand" checked={Boolean(form.is_returnable)} onChange={(e) => setForm((current) => ({ ...current, is_returnable: e.target.checked, expected_return_date: e.target.checked ? current.expected_return_date : "", borrower_user_id: e.target.checked ? current.borrower_user_id : null, external_borrower_name: e.target.checked ? current.external_borrower_name : "" }))} /><span><strong className="block text-sm">Barang dipinjam dan akan kembali</strong><span className="mt-1 block text-xs text-slate-500">Aktifkan untuk inventaris tetap yang dibawa sementara.</span></span></label>}
        {form.type === "Keluar" && form.is_returnable && <div className="grid gap-4 rounded-xl border border-blue-100 bg-blue-50/60 p-4 sm:grid-cols-2"><div><label className="field-label">Rencana kembali *</label><input className="field bg-white" type="date" min={form.transaction_date} value={form.expected_return_date ?? ""} onChange={(e) => set("expected_return_date", e.target.value)} /></div><div><label className="field-label">Peminjam *</label><select className="field bg-white" value={borrowerMode} onChange={(e) => { setBorrowerMode(e.target.value); setForm((current) => ({ ...current, borrower_user_id: e.target.value && e.target.value !== "__external" ? e.target.value : null, external_borrower_name: e.target.value === "__external" ? current.external_borrower_name : "" })); }}><option value="">Pilih peminjam</option>{borrowers.map((row) => <option key={row.id} value={row.id}>{row.full_name || row.username} (@{row.username})</option>)}<option value="__external">Peminjam eksternal</option></select></div>{borrowerMode === "__external" && <div className="sm:col-span-2"><label className="field-label">Nama peminjam eksternal *</label><input className="field bg-white" value={form.external_borrower_name ?? ""} onChange={(e) => set("external_borrower_name", e.target.value)} placeholder="Nama lengkap / organisasi" /></div>}</div>}
        <div className="grid gap-4 sm:grid-cols-2"><div><label className="field-label">Tanggal *</label><input className="field" type="date" value={form.transaction_date} onChange={(e) => set("transaction_date", e.target.value)} /></div><div><label className="field-label">Kegiatan</label><input className="field" list="activity-options" value={form.activity_name ?? ""} onChange={(e) => set("activity_name", e.target.value)} placeholder="Contoh: DevFest 2026" /><datalist id="activity-options">{activityNames.map((name) => <option key={name}>{name}</option>)}</datalist></div></div>
        <div><label className="field-label">Catatan</label><textarea className="field min-h-24 resize-y" value={form.notes ?? ""} onChange={(e) => set("notes", e.target.value)} /></div>
        {selectedItem && form.type !== "Penyesuaian" && <div className={`flex items-start gap-3 rounded-xl border p-4 ${stockAfter < 0 || willOverReturn ? "border-rose-200 bg-rose-50 text-rose-700" : "border-slate-200 bg-slate-50 text-slate-600"}`}><AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" /><p className="text-sm">Perkiraan stok setelah disimpan: <strong>{formatQty(stockAfter, selectedItem.unit)}</strong></p></div>}
      </div>
      <div className="flex justify-end gap-3 border-t border-slate-100 px-5 py-4 sm:px-6"><button type="button" className="btn-secondary" onClick={onClose}>Batal</button><button className="btn-primary" disabled={saving}>{saving && <Loader2 className="h-4 w-4 animate-spin" />}{saving ? "Menyimpan..." : "Simpan catatan"}</button></div>
    </form>
  </ModalShell>;
}
