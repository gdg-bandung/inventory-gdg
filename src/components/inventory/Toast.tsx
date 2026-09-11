"use client";

import { AlertCircle, CheckCircle2, X } from "lucide-react";

export type ToastData = { id: number; message: string; type: "success" | "error"; retry?: boolean };

export function ToastViewport({ toasts, dismiss, onRetry }: { toasts: ToastData[]; dismiss: (id: number) => void; onRetry: () => void }) {
  return (
    <div className="fixed right-4 top-4 z-[100] flex w-[calc(100%-2rem)] max-w-sm flex-col gap-2" aria-live="polite">
      {toasts.map((toast) => (
        <div key={toast.id} className={`flex items-start gap-3 rounded-xl border bg-white p-4 shadow-xl ${toast.type === "error" ? "border-rose-200" : "border-emerald-200"}`}>
          {toast.type === "error" ? <AlertCircle className="mt-0.5 h-5 w-5 shrink-0 text-rose-600" /> : <CheckCircle2 className="mt-0.5 h-5 w-5 shrink-0 text-emerald-600" />}
          <div className="flex-1"><p className="text-sm font-medium text-slate-700">{toast.message}</p>{toast.retry && <button onClick={() => { dismiss(toast.id); onRetry(); }} className="mt-1.5 text-sm font-bold text-brand hover:underline">Coba lagi</button>}</div>
          <button onClick={() => dismiss(toast.id)} aria-label="Tutup notifikasi"><X className="h-4 w-4 text-slate-400" /></button>
        </div>
      ))}
    </div>
  );
}
