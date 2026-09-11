"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import type { InventoryItem, InventoryTransaction, ItemInput, SessionUser, TransactionInput } from "./types";
import { ToastViewport, type ToastData } from "./Toast";
import { authHeaders, clearClientSession } from "@/lib/clientAuth";

type ContextValue = {
  items: InventoryItem[];
  transactions: InventoryTransaction[];
  user: SessionUser;
  loading: boolean;
  error: string | null;
  refetchInventory: () => Promise<void>;
  saveItem: (input: ItemInput) => Promise<string>;
  deleteItem: (id: string) => Promise<void>;
  saveTransaction: (input: TransactionInput) => Promise<string>;
  reverseTransaction: (id: string, reason: string) => Promise<void>;
  toast: (message: string, type?: "success" | "error", retry?: boolean) => void;
};

const InventoryContext = createContext<ContextValue | null>(null);

export function InventoryProvider({ user, children }: { user: SessionUser; children: React.ReactNode }) {
  const router = useRouter();
  const [items, setItems] = useState<InventoryItem[]>([]);
  const [transactions, setTransactions] = useState<InventoryTransaction[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [toasts, setToasts] = useState<ToastData[]>([]);

  const toast = useCallback((message: string, type: "success" | "error" = "success", retry = false) => {
    const id = Date.now() + Math.random();
    setToasts((current) => [...current, { id, message, type, retry }]);
    window.setTimeout(() => setToasts((current) => current.filter((row) => row.id !== id)), 4500);
  }, []);

  const expireSession = useCallback(async () => {
    toast("Sesi berakhir, silakan masuk lagi", "error");
    const headers = authHeaders();
    clearClientSession();
    await fetch("/api/auth/logout", { method: "POST", headers });
    router.replace("/login");
  }, [router, toast]);

  const api = useCallback(async (url: string, options?: RequestInit) => {
    const response = await fetch(url, { ...options, headers: authHeaders({ "Content-Type": "application/json", ...(options?.headers ?? {}) }) });
    const payload = await response.json().catch(() => ({}));
    if (response.status === 401 || String(payload.error ?? "").includes("Unauthorized")) {
      await expireSession();
      throw new Error("Unauthorized or expired session");
    }
    if (!response.ok || payload.ok === false) throw new Error(payload.error || "Terjadi kesalahan");
    return payload;
  }, [expireSession]);

  const refetchInventory = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [itemPayload, txPayload] = await Promise.all([api("/api/inventory/items"), api("/api/inventory/transactions")]);
      setItems(itemPayload.data ?? []);
      setTransactions(txPayload.data ?? []);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Gagal memuat data";
      if (!message.includes("Unauthorized")) {
        setError("Gagal memuat data");
        toast("Gagal memuat data", "error", true);
      }
    } finally { setLoading(false); }
  }, [api, toast]);

  useEffect(() => { void refetchInventory(); }, [refetchInventory]);

  const mutate = useCallback(async (url: string, method: string, body?: unknown) => {
    const payload = await api(url, { method, body: body ? JSON.stringify(body) : undefined });
    await refetchInventory();
    return payload;
  }, [api, refetchInventory]);

  const value = useMemo<ContextValue>(() => ({
    items, transactions, user, loading, error, refetchInventory, toast,
    saveItem: async (input) => (await mutate("/api/inventory/items", "POST", input)).id,
    deleteItem: async (id) => { await mutate(`/api/inventory/items?id=${encodeURIComponent(id)}`, "DELETE"); },
    saveTransaction: async (input) => (await mutate("/api/inventory/transactions", "POST", input)).id,
    reverseTransaction: async (id, reason) => { await mutate(`/api/inventory/transactions?id=${encodeURIComponent(id)}&reason=${encodeURIComponent(reason)}`, "DELETE"); },
  }), [items, transactions, user, loading, error, refetchInventory, toast, mutate]);

  return (
    <InventoryContext.Provider value={value}>
      {children}
      <ToastViewport toasts={toasts} dismiss={(id) => setToasts((current) => current.filter((row) => row.id !== id))} onRetry={() => void refetchInventory()} />
    </InventoryContext.Provider>
  );
}

export function useInventory() {
  const context = useContext(InventoryContext);
  if (!context) throw new Error("useInventory harus dipakai di dalam InventoryProvider");
  return context;
}
