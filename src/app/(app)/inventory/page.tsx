"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { AlertTriangle, Archive, Boxes, ChevronDown, ClipboardPlus, Download, FileUp, Filter, Handshake, MapPin, PackagePlus, Pencil, ScanLine, Search, TrendingUp, WalletCards } from "lucide-react";
import { useInventory } from "@/components/inventory/InventoryContext";
import { InventoryItemModal } from "@/components/inventory/InventoryItemModal";
import { InventoryTransactionModal } from "@/components/inventory/InventoryTransactionModal";
import { InventoryItemDetailModal } from "@/components/inventory/InventoryItemDetailModal";
import { SortHeader } from "@/components/inventory/SortHeader";
import { csvDownload, isExpiring, isLowStock, outstandingLoans } from "@/components/inventory/inventoryUtils";
import { formatDateID, formatQty, formatRupiah, getConditionBadge, getExpiryBadge, getStockBadge } from "@/components/inventory/helpers";
import type { InventoryItem, TransactionType } from "@/components/inventory/types";
import { InventoryImportModal } from "@/components/inventory/InventoryImportModal";
import { BarcodeScannerModal } from "@/components/inventory/BarcodeScannerModal";

const PAGE_SIZE = 25;

export default function InventoryPage() {
  const params = useSearchParams();
  const { items, transactions, user, loading, error, refetchInventory } = useInventory();
  const [query, setQuery] = useState("");
  const [advanced, setAdvanced] = useState(false);
  const [condition, setCondition] = useState("");
  const [location, setLocation] = useState("");
  const [owner, setOwner] = useState("");
  const [showArchived, setShowArchived] = useState(params.get("archived") === "true");
  const [alertFilter, setAlertFilter] = useState<"" | "low" | "expiry" | "loans">("");
  const [sort, setSort] = useState("name");
  const [direction, setDirection] = useState<"asc" | "desc">("asc");
  const [page, setPage] = useState(1);
  const [itemModal, setItemModal] = useState<{ open: boolean; item: InventoryItem | null }>({ open: false, item: null });
  const [txModal, setTxModal] = useState<{ open: boolean; item: InventoryItem | null; type?: TransactionType }>({ open: false, item: null });
  const [detail, setDetail] = useState<InventoryItem | null>(null);
  const [importOpen, setImportOpen] = useState(false);
  const [scannerOpen, setScannerOpen] = useState(false);
  const category = params.get("category") || "";
  const closeScanner = useCallback(() => setScannerOpen(false), []);
  const handleScan = useCallback((value:string) => setQuery(value), []);

  useEffect(() => setShowArchived(params.get("archived") === "true"), [params]);

  const active = items.filter((item) => !item.is_archived);
  const lowItems = active.filter(isLowStock);
  const expiryItems = active.filter((item) => isExpiring(item));
  const overdueItemIds = new Set(active.flatMap((item) => outstandingLoans(item.id, transactions)).filter((row) => row.expected_return_date && new Date(`${row.expected_return_date}T23:59:59`) < new Date()).map((row) => row.item_id));
  const activeLoans = active.filter((item) => Number(item.outstanding) > 0);
  const totalValue = active.reduce((sum, item) => sum + Number(item.current_stock) * Number(item.purchase_price ?? 0), 0);
  const locations = [...new Set(items.map((row) => row.location).filter(Boolean) as string[])].sort();
  const owners = [...new Set(items.map((row) => row.penanggung_jawab).filter(Boolean) as string[])].sort();
  const filterCount = Number(Boolean(condition)) + Number(Boolean(location)) + Number(Boolean(owner)) + Number(showArchived);

  const filtered = useMemo(() => items.filter((item) => {
    if (!showArchived && item.is_archived) return false;
    if (category && item.category !== category) return false;
    const needle = query.toLowerCase();
    if (needle && ![item.name, item.code, item.location, item.penanggung_jawab, item.owner_division].some((value) => value?.toLowerCase().includes(needle))) return false;
    if (condition && item.condition !== condition) return false;
    if (location && item.location !== location) return false;
    if (owner && item.penanggung_jawab !== owner) return false;
    if (alertFilter === "low" && !isLowStock(item)) return false;
    if (alertFilter === "expiry" && !isExpiring(item)) return false;
    if (alertFilter === "loans" && !overdueItemIds.has(item.id)) return false;
    return true;
  }).sort((a, b) => {
    const av = a[sort as keyof InventoryItem] ?? "";
    const bv = b[sort as keyof InventoryItem] ?? "";
    const result = typeof av === "number" ? Number(av) - Number(bv) : String(av).localeCompare(String(bv), "id");
    return direction === "asc" ? result : -result;
  }), [items, transactions, showArchived, category, query, condition, location, owner, alertFilter, sort, direction]);

  useEffect(() => setPage(1), [query, condition, location, owner, showArchived, alertFilter, category, sort, direction]);
  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const visible = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
  const onSort = (field: string) => { if (sort === field) setDirection((v) => v === "asc" ? "desc" : "asc"); else { setSort(field); setDirection("asc"); } };
  const exportCsv = () => csvDownload("inventaris.csv", ["Kode", "Nama", "Kategori", "Stok", "Satuan", "Status", "Lokasi", "PJ", "Harga", "Kadaluarsa", "Terakhir Dipakai"], filtered.map((row) => [row.code, row.name, row.category, row.current_stock, row.unit, row.is_archived ? "Diarsipkan" : isLowStock(row) ? "Perlu restock" : "Aman", row.location, row.penanggung_jawab, row.purchase_price, row.expiry_date, row.last_movement_at?.slice(0, 10)]));

  if (loading && items.length === 0) return <PageLoading />;
  if (error && items.length === 0) return <div className="grid min-h-[80vh] place-items-center p-5"><div className="panel max-w-md p-8 text-center"><AlertTriangle className="mx-auto h-8 w-8 text-rose-500" /><h1 className="mt-4 text-xl font-bold">Data belum berhasil dimuat</h1><p className="mt-2 text-sm text-slate-500">Periksa koneksi lalu coba lagi.</p><button className="btn-primary mt-5" onClick={() => void refetchInventory()}>Coba lagi</button></div></div>;

  if (items.length === 0) return <div className="p-4 sm:p-8"><div className="mx-auto mt-[8vh] max-w-2xl rounded-3xl border border-dashed border-blue-200 bg-white p-8 text-center shadow-panel sm:p-12"><div className="mx-auto grid h-16 w-16 place-items-center rounded-2xl bg-blue-50 text-brand"><PackagePlus className="h-8 w-8" /></div><h1 className="mt-6 text-2xl font-bold">{user.role === "admin" ? "Mulai inventaris pertama" : "Inventaris belum tersedia"}</h1><p className="mx-auto mt-3 max-w-lg text-sm leading-6 text-slate-500">{user.role === "admin" ? "Tambahkan barang beserta stok awalnya. Setelah itu, catat setiap pergerakan agar stok dan riwayat selalu sinkron." : "Admin belum menambahkan master barang. Hubungi admin sebelum mencatat pergerakan."}</p>{user.role === "admin" && <><button className="btn-primary mt-8" onClick={() => setItemModal({ open: true, item: null })}><PackagePlus className="h-4 w-4" />Tambah barang pertama</button><InventoryItemModal open={itemModal.open} item={itemModal.item} onClose={() => setItemModal({ open: false, item: null })} /></>}</div></div>;

  return (
    <div className="mx-auto max-w-[1600px] p-4 sm:p-6 xl:p-8">
      <header className="mb-6 flex flex-col justify-between gap-4 sm:flex-row sm:items-center"><div><p className="text-sm font-semibold text-brand">Pusat data barang</p><h1 className="mt-1 text-2xl font-bold tracking-tight sm:text-3xl">{category || "Semua Inventaris"}</h1><p className="mt-1 text-sm text-slate-500">Pantau stok, peminjaman, dan kondisi barang dalam satu tempat.</p></div><div className="flex flex-wrap gap-2"><button className="btn-secondary" onClick={() => setScannerOpen(true)}><ScanLine className="h-4 w-4" />Pindai</button>{user.role === "admin" && <button className="btn-secondary" onClick={() => setImportOpen(true)}><FileUp className="h-4 w-4" />Import</button>}<button className="btn-secondary" onClick={exportCsv}><Download className="h-4 w-4" />CSV</button>{user.role === "admin" && <button className="btn-primary" onClick={() => setItemModal({ open: true, item: null })}><PackagePlus className="h-4 w-4" />Tambah barang</button>}</div></header>

      <div className="grid grid-cols-2 gap-3 xl:grid-cols-4">
        <Summary icon={<Boxes />} label="Total barang" value={formatQty(active.length)} note={`${new Set(active.map((item)=>item.unit)).size} jenis satuan`} color="blue" />
        <Summary icon={<WalletCards />} label="Nilai stok" value={formatRupiah(totalValue)} note="berdasarkan harga beli" color="violet" />
        <Summary icon={<TrendingUp />} label="Perlu restock" value={formatQty(lowItems.length)} note="stok di bawah batas" color="amber" />
        <Summary icon={<Handshake />} label="Sedang dipinjam" value={formatQty(activeLoans.length)} note={`${activeLoans.reduce((sum, item) => sum + Number(item.outstanding), 0).toLocaleString("id-ID")} unit di luar`} color="cyan" />
      </div>

      {(lowItems.length > 0 || expiryItems.length > 0 || overdueItemIds.size > 0) && <div className="mt-4 flex flex-wrap gap-2 rounded-2xl border border-amber-200 bg-amber-50/70 p-3"><AlertTriangle className="mx-1 mt-2 h-5 w-5 text-amber-600" />{lowItems.length > 0 && <AlertButton active={alertFilter === "low"} onClick={() => setAlertFilter(alertFilter === "low" ? "" : "low")}>{lowItems.length} perlu restock</AlertButton>}{expiryItems.length > 0 && <AlertButton active={alertFilter === "expiry"} onClick={() => setAlertFilter(alertFilter === "expiry" ? "" : "expiry")}>{expiryItems.length} mendekati kadaluarsa</AlertButton>}{overdueItemIds.size > 0 && <AlertButton active={alertFilter === "loans"} onClick={() => setAlertFilter(alertFilter === "loans" ? "" : "loans")}>{overdueItemIds.size} pinjaman terlambat</AlertButton>}</div>}

      <section className="mt-5">
        <div className="panel p-3 sm:p-4"><div className="flex flex-col gap-3 md:flex-row"><div className="relative flex-1"><Search className="absolute left-3.5 top-3 h-5 w-5 text-slate-400" /><input className="field pl-11" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Cari nama, kode, lokasi, atau penanggung jawab..." /></div><button onClick={() => setAdvanced((v) => !v)} className={`btn-secondary md:w-auto ${advanced || filterCount ? "border-blue-200 bg-blue-50 text-blue-700" : ""}`}><Filter className="h-4 w-4" />Filter lainnya{filterCount > 0 && <span className="grid h-5 w-5 place-items-center rounded-full bg-brand text-xs text-white">{filterCount}</span>}<ChevronDown className={`h-4 w-4 transition ${advanced ? "rotate-180" : ""}`} /></button><select className="field md:hidden" value={`${sort}:${direction}`} onChange={(e) => { const [field, dir] = e.target.value.split(":"); setSort(field); setDirection(dir as "asc" | "desc"); }}><option value="name:asc">Nama A–Z</option><option value="name:desc">Nama Z–A</option><option value="current_stock:asc">Stok terendah</option><option value="current_stock:desc">Stok tertinggi</option><option value="last_movement_at:desc">Terakhir dipakai</option></select></div>
          {advanced && <div className="mt-4 grid gap-3 border-t border-slate-100 pt-4 sm:grid-cols-2 lg:grid-cols-4"><select className="field" value={condition} onChange={(e) => setCondition(e.target.value)}><option value="">Semua kondisi</option><option>Baik</option><option>Perlu Perbaikan</option><option>Rusak</option></select><select className="field" value={location} onChange={(e) => setLocation(e.target.value)}><option value="">Semua lokasi</option>{locations.map((row) => <option key={row}>{row}</option>)}</select><select className="field" value={owner} onChange={(e) => setOwner(e.target.value)}><option value="">Semua penanggung jawab</option>{owners.map((row) => <option key={row}>{row}</option>)}</select><label className="flex h-11 items-center gap-3 rounded-xl border border-slate-200 px-3 text-sm font-medium"><input type="checkbox" className="h-4 w-4 accent-brand" checked={showArchived} onChange={(e) => setShowArchived(e.target.checked)} /><Archive className="h-4 w-4 text-slate-400" />Tampilkan arsip</label></div>}
        </div>
      </section>

      <div className="mt-4 hidden md:block table-shell"><table className="table-base"><thead><tr><th><SortHeader label="Barang" field="name" sort={sort} direction={direction} onSort={onSort} /></th><th>Kategori</th><th><SortHeader label="Stok" field="current_stock" sort={sort} direction={direction} onSort={onSort} /></th><th>Kondisi / Lokasi</th><th><SortHeader label="Terakhir Dipakai" field="last_movement_at" sort={sort} direction={direction} onSort={onSort} /></th><th className="text-right">Aksi</th></tr></thead><tbody>{visible.map((item) => <tr key={item.id} className="cursor-pointer" onClick={() => setDetail(item)}><td><p className="font-semibold text-ink">{item.name}</p><p className="mt-0.5 text-xs font-medium text-slate-400">{item.code}</p></td><td><p>{item.category}</p>{item.owner_division && <p className="mt-0.5 text-xs text-slate-400">{item.owner_division}</p>}</td><td><p className="font-bold text-ink">{formatQty(item.current_stock, item.unit)}</p><div className="mt-1">{getStockBadge(item)}</div></td><td><div>{getConditionBadge(item.condition)}</div><p className="mt-1 flex items-center gap-1 text-xs text-slate-500"><MapPin className="h-3 w-3" />{item.location || "Belum diisi"}</p></td><td><p>{formatDateID(item.last_movement_at)}</p>{Number(item.outstanding) > 0 && <p className="mt-1 text-xs font-semibold text-blue-700">{formatQty(item.outstanding, item.unit)} dipinjam</p>}</td><td><div className="flex justify-end gap-2" onClick={(e) => e.stopPropagation()}><button className="btn-secondary min-h-9 px-3 py-1.5" onClick={() => setTxModal({ open: true, item })}><ClipboardPlus className="h-4 w-4" />Catat</button>{user.role === "admin" && <button className="grid h-9 w-9 place-items-center rounded-lg border border-slate-200 hover:bg-slate-50" onClick={() => setItemModal({ open: true, item })} aria-label={`Ubah ${item.name}`}><Pencil className="h-4 w-4" /></button>}</div></td></tr>)}</tbody></table>{visible.length === 0 && <NoResults />}</div>

      <div className="mt-4 grid gap-3 md:hidden">{visible.map((item) => <article key={item.id} onClick={() => setDetail(item)} className="panel cursor-pointer p-4"><div className="flex items-start justify-between gap-3"><div><p className="text-xs font-bold uppercase tracking-wide text-brand">{item.code}</p><h2 className="mt-1 font-bold">{item.name}</h2><p className="mt-1 text-sm text-slate-500">{item.category}</p></div>{getStockBadge(item)}</div><div className="mt-4 flex items-end justify-between border-t border-slate-100 pt-4"><div><p className="text-xs text-slate-400">Stok tersedia</p><p className="mt-1 text-xl font-bold">{formatQty(item.current_stock, item.unit)}</p></div><div className="flex gap-2" onClick={(e) => e.stopPropagation()}><button className="btn-secondary min-h-10 px-3" onClick={() => setTxModal({ open: true, item })}><ClipboardPlus className="h-4 w-4" />Catat</button>{user.role === "admin" && <button className="grid h-10 w-10 place-items-center rounded-xl border border-slate-200" onClick={() => setItemModal({ open: true, item })}><Pencil className="h-4 w-4" /></button>}</div></div>{item.expiry_date && <div className="mt-3">{getExpiryBadge(item.expiry_date)}</div>}</article>)}{visible.length === 0 && <NoResults />}</div>

      {filtered.length > 0 && <div className="mt-4 flex flex-col items-center justify-between gap-3 text-sm text-slate-500 sm:flex-row"><p>Menampilkan {(page - 1) * PAGE_SIZE + 1}–{Math.min(page * PAGE_SIZE, filtered.length)} dari {filtered.length} barang</p><div className="flex gap-2"><button className="btn-secondary min-h-9 px-3 py-1.5" disabled={page <= 1} onClick={() => setPage((v) => v - 1)}>Sebelumnya</button><span className="grid min-h-9 place-items-center px-2 font-semibold text-slate-700">{page} / {pageCount}</span><button className="btn-secondary min-h-9 px-3 py-1.5" disabled={page >= pageCount} onClick={() => setPage((v) => v + 1)}>Berikutnya</button></div></div>}

      {user.role === "admin" && <InventoryItemModal open={itemModal.open} item={itemModal.item} onClose={() => setItemModal({ open: false, item: null })} />}
      <InventoryTransactionModal open={txModal.open} initialItem={txModal.item} initialType={txModal.type} onClose={() => setTxModal({ open: false, item: null })} />
      <InventoryItemDetailModal item={detail ? items.find((row) => row.id === detail.id) ?? detail : null} onClose={() => setDetail(null)} onEdit={(item) => { setDetail(null); setItemModal({ open: true, item }); }} onCorrect={(item) => { setDetail(null); setTxModal({ open: true, item, type: "Penyesuaian" }); }} />
      {user.role === "admin" && <InventoryImportModal open={importOpen} onClose={() => setImportOpen(false)} />}
      <BarcodeScannerModal open={scannerOpen} onClose={closeScanner} onDetected={handleScan} />
    </div>
  );
}

function Summary({ icon, label, value, note, color }: { icon: React.ReactNode; label: string; value: string; note: string; color: string }) { const colors: Record<string, string> = { blue: "bg-blue-50 text-blue-700", violet: "bg-violet-50 text-violet-700", amber: "bg-amber-50 text-amber-700", cyan: "bg-cyan-50 text-cyan-700" }; return <div className="panel p-4 sm:p-5"><div className={`grid h-10 w-10 place-items-center rounded-xl [&>svg]:h-5 [&>svg]:w-5 ${colors[color]}`}>{icon}</div><p className="mt-4 text-xs font-semibold uppercase tracking-wide text-slate-400">{label}</p><p className="mt-1 truncate text-xl font-bold sm:text-2xl">{value}</p><p className="mt-1 hidden text-xs text-slate-400 sm:block">{note}</p></div>; }
function AlertButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) { return <button onClick={onClick} className={`rounded-xl border px-3 py-2 text-sm font-semibold transition ${active ? "border-amber-400 bg-amber-400 text-amber-950" : "border-amber-200 bg-white/80 text-amber-800 hover:border-amber-300"}`}>{children}</button>; }
function NoResults() { return <div className="p-10 text-center"><Search className="mx-auto h-7 w-7 text-slate-300" /><p className="mt-3 font-semibold text-slate-600">Barang tidak ditemukan</p><p className="mt-1 text-sm text-slate-400">Coba ubah kata pencarian atau filter.</p></div>; }
function PageLoading() { return <div className="mx-auto max-w-[1600px] animate-pulse p-4 sm:p-8"><div className="h-9 w-52 rounded-lg bg-slate-200" /><div className="mt-8 grid grid-cols-2 gap-3 xl:grid-cols-4">{[1,2,3,4].map((row) => <div key={row} className="h-36 rounded-2xl bg-white" />)}</div><div className="mt-5 h-16 rounded-2xl bg-white" /><div className="mt-4 h-80 rounded-2xl bg-white" /></div>; }
