"use client";

import { useEffect, useMemo, useState } from "react";
import { AlertTriangle, Archive, ChevronDown, Loader2, Trash2 } from "lucide-react";
import { ModalShell } from "./ModalShell";
import { useInventory } from "./InventoryContext";
import type { InventoryCategory, InventoryItem, ItemInput } from "./types";

export const INVENTORY_CATEGORIES: InventoryCategory[] = ["Barang Habis Pakai", "Barang Tetap", "Konsumsi", "Lainnya"];
type ItemForm = Omit<ItemInput,"initial_stock"|"min_stock"> & { initial_stock:number|""; min_stock:number|"" };
const empty: ItemForm = { name: "", category: "Barang Habis Pakai", code: "", unit: "pcs", initial_stock: "", min_stock: "", condition: "", location: "", purchase_price: null, purchase_date: "", expiry_date: "", owner_division: "", penanggung_jawab: "", notes: "", is_archived: false };

export function InventoryItemModal({ open, item, onClose }: { open: boolean; item?: InventoryItem | null; onClose: () => void }) {
  const { items, transactions, saveItem, deleteItem, toast } = useInventory();
  const [form, setForm] = useState<ItemForm>(empty);
  const [details, setDetails] = useState(false);
  const [unlockStock, setUnlockStock] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [confirmation, setConfirmation] = useState("");

  useEffect(() => {
    if (!open) return;
    const next:ItemForm = item ? { ...item } : { ...empty };
    setForm(next);
    setUnlockStock(false); setError(""); setConfirmDelete(false); setConfirmation("");
    setDetails(Boolean(item && [item.condition, item.location, item.purchase_price, item.purchase_date, item.expiry_date, item.owner_division, item.penanggung_jawab, item.notes].some(Boolean)));
  }, [open, item]);

  const transactionCount = useMemo(() => transactions.filter((row) => row.item_id === item?.id).length, [transactions, item]);
  const set = (key: keyof ItemForm, value: ItemForm[keyof ItemForm]) => setForm((current) => ({ ...current, [key]: value }));

  async function submit(event: React.FormEvent) {
    event.preventDefault(); setError("");
    if (!form.name.trim() || !form.code.trim()) { setError("Nama barang dan kode/SKU wajib diisi"); return; }
    if (items.some((row) => row.id !== item?.id && row.code.toLowerCase() === form.code.trim().toLowerCase())) { setError(`Kode/SKU "${form.code.trim()}" sudah dipakai barang lain`); return; }
    if (!Number.isFinite(Number(form.initial_stock||0)) || Number(form.initial_stock||0)<0 || !Number.isFinite(Number(form.min_stock||0)) || Number(form.min_stock||0)<0) { setError("Stok awal dan batas minimum harus berupa angka nol atau lebih"); return; }
    setSaving(true);
    try { await saveItem({ ...form, id: item?.id ?? null, name: form.name.trim(), code: form.code.trim(), initial_stock: Number(form.initial_stock), min_stock: Number(form.min_stock), purchase_price: form.purchase_price == null ? null : Number(form.purchase_price) }); toast(item ? "Barang berhasil diperbarui" : "Barang berhasil ditambahkan"); onClose(); }
    catch (err) { setError(err instanceof Error ? err.message : "Gagal menyimpan barang"); }
    finally { setSaving(false); }
  }

  async function remove() {
    if (!item || confirmation !== item.name) return;
    setSaving(true); setError("");
    try { await deleteItem(item.id); toast("Barang tanpa riwayat berhasil dihapus"); onClose(); }
    catch (err) { setError(err instanceof Error ? err.message : "Gagal menghapus barang"); }
    finally { setSaving(false); }
  }

  return (
    <ModalShell open={open} onClose={onClose} title={item ? "Ubah barang" : "Tambah barang"} description={item ? `${item.code} · ${item.category}` : "Isi data utama barang. Detail lain dapat ditambahkan kapan saja."}>
      <form onSubmit={submit}>
        <div className="max-h-[70vh] space-y-5 overflow-y-auto px-5 py-5 sm:px-6">
          {error && <div className="rounded-xl border border-rose-100 bg-rose-50 px-4 py-3 text-sm font-medium text-rose-700">{error}</div>}
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="sm:col-span-2"><label className="field-label">Nama barang *</label><input className="field" value={form.name} onChange={(e) => set("name", e.target.value)} placeholder="Contoh: Kursi lipat" /></div>
            <div><label className="field-label">Kode / SKU *</label><input className="field uppercase" value={form.code} onChange={(e) => set("code", e.target.value)} placeholder="INV-001" /></div>
            <div><label className="field-label">Kategori *</label><select className="field" value={form.category} onChange={(e) => set("category", e.target.value as InventoryCategory)}>{INVENTORY_CATEGORIES.map((row) => <option key={row}>{row}</option>)}</select></div>
            <div><label className="field-label">Satuan</label><input className="field" value={form.unit} onChange={(e) => set("unit", e.target.value)} placeholder="pcs" /></div>
            <div><label className="field-label">Batas stok minimum</label><input className="field" type="number" min="0" step="any" value={form.min_stock} placeholder="0" onChange={(e) => set("min_stock", e.target.value===""?"":Number(e.target.value))} /></div>
            <div className="sm:col-span-2">
              <div className="flex items-center justify-between"><label className="field-label">Stok awal</label>{item && transactionCount === 0 && !unlockStock && <button type="button" className="text-xs font-semibold text-brand hover:underline" onClick={() => setUnlockStock(true)}>Ubah stok awal</button>}</div>
              <input className="field" type="number" min="0" step="any" value={form.initial_stock} placeholder="0" disabled={Boolean(item && !unlockStock)} onChange={(e) => set("initial_stock", e.target.value===""?"":Number(e.target.value))} />
              {item && transactionCount > 0 && <p className="mt-2 flex gap-2 rounded-lg bg-slate-50 px-3 py-2 text-xs leading-5 text-slate-600"><AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />Stok awal dikunci karena barang sudah memiliki riwayat. Gunakan Koreksi Stok agar perubahan dapat diaudit.</p>}
              {item && transactionCount === 0 && unlockStock && <p className="mt-2 flex gap-2 rounded-lg bg-amber-50 px-3 py-2 text-xs leading-5 text-amber-800"><AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />Stok awal hanya boleh diperbaiki sebelum ada riwayat transaksi.</p>}
            </div>
          </div>
          <button type="button" onClick={() => setDetails((v) => !v)} className="flex w-full items-center justify-between border-y border-slate-100 py-3 text-sm font-semibold text-slate-700"><span>Detail tambahan</span><ChevronDown className={`h-4 w-4 transition ${details ? "rotate-180" : ""}`} /></button>
          {details && <div className="grid gap-4 sm:grid-cols-2">
            {form.category === "Barang Tetap" && <div><label className="field-label">Kondisi</label><select className="field" value={form.condition ?? ""} onChange={(e) => set("condition", e.target.value)}><option value="">Pilih kondisi</option><option>Baik</option><option>Perlu Perbaikan</option><option>Rusak</option></select></div>}
            <div><label className="field-label">Lokasi penyimpanan</label><input className="field" value={form.location ?? ""} onChange={(e) => set("location", e.target.value)} /></div>
            <div><label className="field-label">Harga beli / satuan</label><input className="field" type="number" min="0" value={form.purchase_price ?? ""} onChange={(e) => set("purchase_price", e.target.value ? Number(e.target.value) : null)} /></div>
            <div><label className="field-label">Tanggal beli</label><input className="field" type="date" value={form.purchase_date ?? ""} onChange={(e) => set("purchase_date", e.target.value)} /></div>
            {(form.category === "Konsumsi" || form.category === "Barang Habis Pakai") && <div><label className="field-label">Tanggal kadaluarsa</label><input className="field" type="date" value={form.expiry_date ?? ""} onChange={(e) => set("expiry_date", e.target.value)} /></div>}
            <div><label className="field-label">Divisi pemilik</label><input className="field" value={form.owner_division ?? ""} onChange={(e) => set("owner_division", e.target.value)} /></div>
            <div><label className="field-label">Penanggung jawab</label><input className="field" value={form.penanggung_jawab ?? ""} onChange={(e) => set("penanggung_jawab", e.target.value)} /></div>
            <div className="sm:col-span-2"><label className="field-label">Catatan</label><textarea className="field min-h-24 py-3" value={form.notes ?? ""} onChange={(e) => set("notes", e.target.value)} /></div>
            {item && <label className={`flex items-center gap-3 rounded-xl border border-slate-200 p-4 sm:col-span-2 ${item.outstanding>0&&!form.is_archived?"cursor-not-allowed opacity-60":""}`}><input type="checkbox" className="h-4 w-4 accent-brand" checked={form.is_archived} disabled={item.outstanding>0&&!form.is_archived} onChange={(e) => set("is_archived", e.target.checked)} /><span><span className="flex items-center gap-2 text-sm font-semibold"><Archive className="h-4 w-4" />Arsipkan barang</span><span className="mt-0.5 block text-xs text-slate-500">{item.outstanding>0&&!form.is_archived?`Selesaikan ${item.outstanding} ${item.unit} pinjaman sebelum mengarsipkan.`:"Barang tidak tampil di daftar aktif dan tidak bisa dipilih untuk catatan baru."}</span></span></label>}
          </div>}
          {item && transactionCount === 0 && <div className="border-t border-slate-100 pt-5">
            {!confirmDelete ? <button type="button" onClick={() => setConfirmDelete(true)} className="inline-flex items-center gap-2 text-sm font-semibold text-rose-600 hover:text-rose-700"><Trash2 className="h-4 w-4" />Hapus barang tanpa riwayat</button> : <div className="rounded-xl border border-rose-200 bg-rose-50 p-4"><p className="text-sm font-bold text-rose-800">Hapus “{item.name}”?</p><p className="mt-1 text-xs leading-5 text-rose-700">Hanya barang yang belum pernah masuk histori yang dapat dihapus. Ketik nama barang untuk mengonfirmasi.</p><input className="field mt-3 border-rose-200" value={confirmation} onChange={(e) => setConfirmation(e.target.value)} placeholder={item.name} /><div className="mt-3 flex gap-2"><button type="button" className="btn-secondary" onClick={() => setConfirmDelete(false)}>Batal</button><button type="button" className="btn-danger" disabled={confirmation !== item.name || saving} onClick={remove}>Hapus permanen</button></div></div>}
          </div>}
        </div>
        <footer className="flex items-center justify-end gap-3 border-t border-slate-100 bg-slate-50/60 px-5 py-4 sm:px-6"><button type="button" className="btn-secondary" onClick={onClose}>Batal</button><button className="btn-primary" disabled={saving}>{saving && <Loader2 className="h-4 w-4 animate-spin" />}{item ? "Simpan perubahan" : "Tambah barang"}</button></footer>
      </form>
    </ModalShell>
  );
}
