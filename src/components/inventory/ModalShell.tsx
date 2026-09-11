"use client";

import { useEffect } from "react";
import { X } from "lucide-react";

export function ModalShell({ open, onClose, title, description, children, size = "lg" }: { open: boolean; onClose: () => void; title: string; description?: string; children: React.ReactNode; size?: "md" | "lg" | "xl" }) {
  useEffect(() => {
    if (!open) return;
    const handler = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", handler);
    return () => { document.body.style.overflow = ""; window.removeEventListener("keydown", handler); };
  }, [open, onClose]);
  if (!open) return null;
  const width = size === "xl" ? "max-w-5xl" : size === "md" ? "max-w-lg" : "max-w-2xl";
  return (
    <div className="fixed inset-0 z-[70] overflow-y-auto bg-slate-950/55 p-3 backdrop-blur-sm sm:p-6" role="dialog" aria-modal="true">
      <button className="fixed inset-0 cursor-default" onClick={onClose} aria-label="Tutup" />
      <div className={`relative mx-auto my-3 w-full ${width} overflow-hidden rounded-2xl bg-white shadow-2xl sm:my-8`}>
        <header className="flex items-start gap-4 border-b border-slate-100 px-5 py-5 sm:px-6"><div className="flex-1"><h2 className="text-xl font-bold tracking-tight text-ink">{title}</h2>{description && <p className="mt-1 text-sm text-slate-500">{description}</p>}</div><button onClick={onClose} className="grid h-9 w-9 shrink-0 place-items-center rounded-lg text-slate-400 hover:bg-slate-100 hover:text-slate-700" aria-label="Tutup"><X className="h-5 w-5" /></button></header>
        {children}
      </div>
    </div>
  );
}
