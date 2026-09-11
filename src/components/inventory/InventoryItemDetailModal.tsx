"use client";

import { CalendarClock, Download, MapPin, Pencil, RotateCcw, UserRound } from "lucide-react";
import { ModalShell } from "./ModalShell";
import { useInventory } from "./InventoryContext";
import { calculateRunningBalances, csvDownload, isLoanOverdue, outstandingLoans } from "./inventoryUtils";
import { formatDateID, formatQty, formatRupiah, getConditionBadge, getExpiryBadge, getMovementBadge, getStockBadge } from "./helpers";
import type { InventoryItem } from "./types";
import { InventoryPhotos } from "./InventoryPhotos";

export function InventoryItemDetailModal({ item, onClose, onEdit, onCorrect }: { item: InventoryItem | null; onClose: () => void; onEdit: (item: InventoryItem) => void; onCorrect: (item: InventoryItem) => void }) {
  const { transactions, user } = useInventory();
  if (!item) return null;
  const related = transactions.filter((row) => row.item_id === item.id);
  const running = calculateRunningBalances(item, related);
  const loans = outstandingLoans(item.id, transactions);
  const exportCsv = () => csvDownload(`kartu-stok-${item.code}.csv`, ["Tanggal", "Jenis", "Jumlah", "Saldo", "Kegiatan", "Peminjam/PIC", "Dicatat oleh", "Catatan"], running.map((row) => [row.transaction_date, row.type, row.quantity, row.balance, row.activity_name, row.handled_by, row.recorded_by, row.notes]));

  return (
    <ModalShell open={Boolean(item)} onClose={onClose} title={item.name} description={`${item.code} · ${item.category}`} size="xl">
      <div className="max-h-[78vh] overflow-y-auto">
        <div className="grid gap-4 border-b border-slate-100 p-5 sm:grid-cols-4 sm:p-6">
          <div className="rounded-xl bg-navy p-4 text-white"><p className="text-xs font-semibold text-blue-200">Stok saat ini</p><p className="mt-2 text-2xl font-bold">{formatQty(item.current_stock, item.unit)}</p><div className="mt-3">{getStockBadge(item)}</div></div>
          <Info label="Stok minimum" value={formatQty(item.min_stock, item.unit)} />
          <Info label="Sedang dipinjam" value={formatQty(item.outstanding, item.unit)} />
          <Info label="Nilai stok" value={formatRupiah(Number(item.current_stock) * Number(item.purchase_price ?? 0))} />
        </div>

        <section className="p-5 sm:p-6">
          <div className="flex flex-wrap items-center justify-between gap-3"><h3 className="font-bold">Profil barang</h3>{user.role === "admin" && <div className="flex gap-2"><button className="btn-secondary" onClick={() => onCorrect(item)}><RotateCcw className="h-4 w-4" />Koreksi stok</button><button className="btn-secondary" onClick={() => onEdit(item)}><Pencil className="h-4 w-4" />Ubah barang</button></div>}</div>
          <div className="mt-4 grid gap-x-8 gap-y-4 rounded-xl border border-slate-100 bg-slate-50/60 p-4 sm:grid-cols-3">
            <InfoPlain label="Kondisi" value={getConditionBadge(item.condition)} />
            <InfoPlain label="Lokasi" value={<span className="inline-flex items-center gap-1.5"><MapPin className="h-4 w-4 text-slate-400" />{item.location || "—"}</span>} />
            <InfoPlain label="Penanggung jawab" value={<span className="inline-flex items-center gap-1.5"><UserRound className="h-4 w-4 text-slate-400" />{item.penanggung_jawab || "—"}</span>} />
            <InfoPlain label="Divisi pemilik" value={item.owner_division || "—"} />
            <InfoPlain label="Harga beli" value={item.purchase_price ? formatRupiah(item.purchase_price) : "—"} />
            <InfoPlain label="Tanggal beli" value={formatDateID(item.purchase_date)} />
            <InfoPlain label="Kadaluarsa" value={getExpiryBadge(item.expiry_date)} />
            <InfoPlain label="Terakhir dipakai" value={formatDateID(item.last_movement_at)} />
            <InfoPlain label="Dibuat / diubah oleh" value={`@${item.created_by}${item.updated_by !== item.created_by ? ` / @${item.updated_by}` : ""}`} />
            <InfoPlain label="Catatan" value={item.notes || "—"} />
          </div>
        </section>

        {loans.length > 0 && <section className="border-t border-slate-100 p-5 sm:p-6"><div className="flex items-center gap-2"><CalendarClock className="h-5 w-5 text-blue-600" /><h3 className="font-bold">Pinjaman belum kembali</h3><span className="rounded-full bg-blue-50 px-2 py-0.5 text-xs font-bold text-blue-700">{loans.length}</span></div><div className="mt-4 grid gap-3 sm:grid-cols-2">{loans.map((loan) => <div key={loan.id} className={`rounded-xl border p-4 ${isLoanOverdue(loan) ? "border-rose-200 bg-rose-50" : "border-slate-200"}`}><div className="flex justify-between gap-3"><p className="font-semibold">{loan.activity_name || "Tanpa kegiatan"}</p><p className="font-bold text-blue-700">{formatQty(loan.remaining, item.unit)}</p></div><p className="mt-2 text-sm text-slate-600">{loan.handled_by || "PIC belum diisi"}</p><p className={`mt-1 text-xs ${isLoanOverdue(loan) ? "font-semibold text-rose-700" : "text-slate-500"}`}>Rencana kembali: {formatDateID(loan.expected_return_date)}</p></div>)}</div></section>}

        <InventoryPhotos itemId={item.id} />

        <section className="border-t border-slate-100 p-5 sm:p-6">
          <div className="mb-4 flex items-center justify-between gap-3"><div><h3 className="font-bold">Kartu stok</h3><p className="mt-1 text-sm text-slate-500">Saldo berjalan dari stok awal {formatQty(item.initial_stock, item.unit)}.</p></div><button className="btn-secondary shrink-0" onClick={exportCsv}><Download className="h-4 w-4" /><span className="hidden sm:inline">Export CSV</span></button></div>
          {running.length === 0 ? <div className="rounded-xl border border-dashed border-slate-200 p-8 text-center text-sm text-slate-500">Belum ada catatan keluar-masuk untuk barang ini.</div> : <div className="overflow-x-auto rounded-xl border border-slate-200"><table className="table-base min-w-[720px]"><thead><tr><th>Tanggal</th><th>Jenis</th><th>Jumlah</th><th>Saldo</th><th>Kegiatan / PIC</th><th>Dicatat oleh</th></tr></thead><tbody>{running.map((row) => <tr key={row.id}><td>{formatDateID(row.transaction_date)}</td><td>{getMovementBadge(row.type)}</td><td className="font-semibold">{row.type === "Penyesuaian" && row.quantity > 0 ? "+" : ""}{formatQty(row.quantity, item.unit)}</td><td className="font-bold text-ink">{formatQty(row.balance, item.unit)}</td><td><p className="font-medium">{row.activity_name || "—"}</p><p className="mt-0.5 text-xs text-slate-500">{row.handled_by || "PIC tidak diisi"}</p></td><td className="text-slate-600">@{row.recorded_by}</td></tr>)}</tbody></table></div>}
        </section>
      </div>
    </ModalShell>
  );
}

function Info({ label, value }: { label: string; value: string }) { return <div className="rounded-xl border border-slate-200 p-4"><p className="text-xs font-semibold text-slate-500">{label}</p><p className="mt-2 text-lg font-bold text-ink">{value}</p></div>; }
function InfoPlain({ label, value }: { label: string; value: React.ReactNode }) { return <div><p className="text-xs font-semibold uppercase tracking-wide text-slate-400">{label}</p><div className="mt-1 text-sm font-medium text-slate-700">{value}</div></div>; }
