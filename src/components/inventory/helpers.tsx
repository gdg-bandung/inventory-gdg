import { clsx } from "clsx";
import type { InventoryItem, TransactionType } from "./types";

export const formatQty = (value: number, unit?: string) =>
  `${new Intl.NumberFormat("id-ID", { maximumFractionDigits: 2 }).format(Number(value))}${unit ? ` ${unit}` : ""}`;

export const formatRupiah = (value: number) =>
  new Intl.NumberFormat("id-ID", { style: "currency", currency: "IDR", maximumFractionDigits: 0 }).format(Number(value));

export const formatDateID = (value?: string | null) =>
  value
    ? new Intl.DateTimeFormat("id-ID", { day: "2-digit", month: "short", year: "numeric" }).format(new Date(`${value.slice(0, 10)}T00:00:00`))
    : "—";

const badge = (label: string, className: string) => (
  <span className={clsx("inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold", className)}>{label}</span>
);

export function getStockBadge(item: InventoryItem) {
  if (item.is_archived) return badge("Diarsipkan", "bg-slate-100 text-slate-600");
  if (Number(item.current_stock) <= 0) return badge("Habis", "bg-rose-50 text-rose-700");
  if (Number(item.current_stock) <= Number(item.min_stock)) return badge("Menipis", "bg-amber-50 text-amber-700");
  return badge("Aman", "bg-emerald-50 text-emerald-700");
}

export function getMovementBadge(type: TransactionType) {
  const map: Record<TransactionType, [string, string]> = {
    Masuk: ["Masuk", "bg-emerald-50 text-emerald-700"],
    Keluar: ["Keluar", "bg-blue-50 text-blue-700"],
    Kembali: ["Kembali", "bg-cyan-50 text-cyan-700"],
    Rusak: ["Rusak", "bg-orange-50 text-orange-700"],
    Hilang: ["Hilang", "bg-rose-50 text-rose-700"],
    Penyesuaian: ["Koreksi", "bg-violet-50 text-violet-700"],
  };
  return badge(...map[type]);
}

export function getConditionBadge(condition?: string | null) {
  if (!condition) return <span className="text-slate-400">—</span>;
  const negative = ["Rusak", "Perlu Perbaikan"].includes(condition);
  return badge(condition, negative ? "bg-orange-50 text-orange-700" : "bg-slate-100 text-slate-700");
}

export function getExpiryBadge(expiry?: string | null) {
  if (!expiry) return <span className="text-slate-400">—</span>;
  const days = Math.ceil((new Date(`${expiry}T00:00:00`).getTime() - Date.now()) / 86400000);
  if (days < 0) return badge("Kadaluarsa", "bg-rose-50 text-rose-700");
  if (days <= 30) return badge(`${days} hari lagi`, "bg-amber-50 text-amber-700");
  return badge(formatDateID(expiry), "bg-slate-100 text-slate-600");
}
