"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { Archive, BarChart3, Boxes, ChevronDown, ClipboardCheck, ClipboardList, History, LogOut, Menu, Package, Users, X } from "lucide-react";
import { useInventory } from "./InventoryContext";
import type { InventoryCategory } from "./types";
import { isLowStock } from "./inventoryUtils";
import { authHeaders, clearClientSession } from "@/lib/clientAuth";
import { InactivityGuard } from "./InactivityGuard";

const categories: Array<[InventoryCategory, string]> = [
  ["Barang Habis Pakai", "Habis pakai"], ["Barang Tetap", "Barang tetap"], ["Konsumsi", "Konsumsi"], ["Lainnya", "Lainnya"],
];

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const params = useSearchParams();
  const { items, user } = useInventory();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [expanded, setExpanded] = useState(true);
  const activeCategory = params.get("category");
  const low = items.filter(isLowStock).length;
  const activeItems = items.filter((item) => !item.is_archived).length;

  async function logout() { const headers=authHeaders(); clearClientSession(); await fetch("/api/auth/logout", { method: "POST", headers }); window.location.href = "/login"; }
  const close = () => setMobileOpen(false);

  const sidebar = (
    <aside className="flex h-full w-[276px] flex-col bg-navy text-white">
      <div className="flex h-20 items-center gap-3 border-b border-white/10 px-6">
        <div className="grid h-10 w-10 place-items-center rounded-xl bg-white/10"><Boxes className="h-5 w-5" /></div>
        <div><p className="font-bold tracking-tight">Inventaris</p><p className="text-xs text-blue-200">GDG Bandung</p></div>
      </div>
      <nav className="flex-1 overflow-y-auto p-4">
        <button onClick={() => setExpanded((v) => !v)} className={`flex w-full items-center gap-3 rounded-xl px-3 py-3 text-sm font-semibold ${pathname === "/inventory" ? "bg-white/12 text-white" : "text-blue-100 hover:bg-white/8"}`}>
          <Package className="h-5 w-5" /><span className="flex-1 text-left">Inventaris</span>
          {low > 0 && <span className="rounded-full bg-amber-400 px-2 py-0.5 text-[11px] font-bold text-amber-950">{low}•{activeItems}</span>}
          <ChevronDown className={`h-4 w-4 transition ${expanded ? "rotate-180" : ""}`} />
        </button>
        {expanded && <div className="ml-5 mt-1 border-l border-white/15 pl-3">
          <Link href="/inventory" onClick={close} className={`block rounded-lg px-3 py-2 text-sm ${pathname === "/inventory" && !activeCategory ? "bg-white/10 text-white" : "text-blue-200 hover:text-white"}`}>Semua barang</Link>
          {categories.map(([value, label]) => <Link key={value} href={`/inventory?category=${encodeURIComponent(value)}`} onClick={close} className={`block rounded-lg px-3 py-2 text-sm ${activeCategory === value ? "bg-white/10 text-white" : "text-blue-200 hover:text-white"}`}>{label}</Link>)}
        </div>}
        <div className="my-4 border-t border-white/10" />
        <Link href="/inventory/transactions" onClick={close} className={`flex items-center gap-3 rounded-xl px-3 py-3 text-sm font-semibold ${pathname.includes("transactions") ? "bg-white/12" : "text-blue-100 hover:bg-white/8"}`}><ClipboardList className="h-5 w-5" />Riwayat Keluar-Masuk</Link>
        <Link href="/inventory/stocktakes" onClick={close} className={`flex items-center gap-3 rounded-xl px-3 py-3 text-sm font-semibold ${pathname.includes("stocktakes") ? "bg-white/12" : "text-blue-100 hover:bg-white/8"}`}><ClipboardCheck className="h-5 w-5" />Stock opname</Link>
        <Link href="/inventory/report" onClick={close} className={`flex items-center gap-3 rounded-xl px-3 py-3 text-sm font-semibold ${pathname.includes("report") ? "bg-white/12" : "text-blue-100 hover:bg-white/8"}`}><BarChart3 className="h-5 w-5" />Laporan</Link>
        <Link href="/inventory/audit" onClick={close} className={`flex items-center gap-3 rounded-xl px-3 py-3 text-sm font-semibold ${pathname.includes("audit") ? "bg-white/12" : "text-blue-100 hover:bg-white/8"}`}><History className="h-5 w-5" />Audit aktivitas</Link>
        {user.role==="admin"&&<Link href="/inventory/users" onClick={close} className={`flex items-center gap-3 rounded-xl px-3 py-3 text-sm font-semibold ${pathname.includes("users") ? "bg-white/12" : "text-blue-100 hover:bg-white/8"}`}><Users className="h-5 w-5" />Pengguna</Link>}
        <Link href="/inventory?archived=true" onClick={close} className="mt-1 flex items-center gap-3 rounded-xl px-3 py-3 text-sm font-semibold text-blue-100 hover:bg-white/8"><Archive className="h-5 w-5" />Arsip barang</Link>
      </nav>
      <div className="border-t border-white/10 p-4">
        <div className="mb-3 flex items-center gap-3 px-2"><div className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-blue-400/20 text-sm font-bold">{(user.full_name || user.username).slice(0, 1).toUpperCase()}</div><div className="min-w-0"><p className="truncate text-sm font-semibold">{user.full_name || user.username}</p><p className="truncate text-xs text-blue-200">@{user.username}</p></div></div>
        <button onClick={logout} className="flex w-full items-center justify-center gap-2 rounded-xl border border-white/15 px-3 py-2.5 text-sm font-semibold text-blue-100 hover:bg-white/10"><LogOut className="h-4 w-4" />Keluar</button>
      </div>
    </aside>
  );

  return (
    <div className="min-h-screen">
      <InactivityGuard />
      <div className="fixed inset-y-0 left-0 z-30 hidden lg:block">{sidebar}</div>
      {mobileOpen && <><button className="fixed inset-0 z-40 bg-slate-950/50 lg:hidden" onClick={close} aria-label="Tutup menu" /><div className="fixed inset-y-0 left-0 z-50 lg:hidden">{sidebar}<button onClick={close} className="absolute right-[-46px] top-4 grid h-10 w-10 place-items-center rounded-xl bg-white text-slate-700 shadow"><X className="h-5 w-5" /></button></div></>}
      <header className="sticky top-0 z-20 flex h-16 items-center border-b border-slate-200 bg-white/90 px-4 backdrop-blur lg:hidden"><button onClick={() => setMobileOpen(true)} className="grid h-10 w-10 place-items-center rounded-xl border border-slate-200" aria-label="Buka menu"><Menu className="h-5 w-5" /></button><p className="ml-3 font-bold">Inventaris GDG Bandung</p></header>
      <main className="min-h-screen lg:pl-[276px]">{children}</main>
    </div>
  );
}
