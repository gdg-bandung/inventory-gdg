import type { InventoryItem, InventoryTransaction, TransactionType } from "./types";

export function movementDelta(type: TransactionType, quantity: number, relatedLoanId?: string | null) {
  if (type === "Masuk" || type === "Kembali" || type === "Penyesuaian") return quantity;
  if ((type === "Rusak" || type === "Hilang") && relatedLoanId) return 0;
  return -Math.abs(quantity);
}

export function calculateRunningBalances(item: InventoryItem, transactions: InventoryTransaction[]) {
  let balance = Number(item.initial_stock);
  return [...transactions]
    .filter((transaction) => !transaction.reversed_at)
    .sort((a, b) => a.transaction_date.localeCompare(b.transaction_date) || a.created_at.localeCompare(b.created_at))
    .map((transaction) => {
      balance += movementDelta(transaction.type, Number(transaction.quantity), transaction.related_loan_id);
      return { ...transaction, balance };
    })
    .reverse();
}

export function outstandingLoans(itemId: string, transactions: InventoryTransaction[]) {
  const rows = transactions
    .filter((row) => row.item_id === itemId && !row.reversed_at)
    .sort((a, b) => a.transaction_date.localeCompare(b.transaction_date) || a.created_at.localeCompare(b.created_at));
  const openings = rows
    .filter((row) => row.type === "Keluar" && row.is_returnable)
    .map((row) => ({ ...row, remaining: Number(row.quantity) }));
  for (const loan of openings) {
    const explicitClosing = rows
      .filter((row) => row.related_loan_id === loan.id && ["Kembali", "Rusak", "Hilang"].includes(row.type))
      .reduce((sum, row) => sum + Math.abs(Number(row.quantity)), 0);
    loan.remaining -= explicitClosing;
  }

  return openings.filter((row) => row.remaining > 0);
}

export function isLowStock(item: InventoryItem) {
  return !item.is_archived && Number(item.current_stock) <= Number(item.min_stock);
}

export function isExpiring(item: InventoryItem, days = 30) {
  if (!item.expiry_date || item.is_archived) return false;
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const end = new Date(today);
  end.setDate(end.getDate() + days);
  const expiry = new Date(`${item.expiry_date}T00:00:00`);
  return expiry >= today && expiry <= end;
}

export function isLoanOverdue(row: InventoryTransaction) {
  if (!row.expected_return_date) return false;
  return new Date(`${row.expected_return_date}T23:59:59`) < new Date();
}

export function csvDownload(filename: string, headers: string[], rows: Array<Array<string | number | null | undefined>>) {
  const escape = (value: string | number | null | undefined) => {
    const text = String(value ?? "");
    return `"${text.replaceAll('"', '""')}"`;
  };
  const csv = `\ufeff${[headers, ...rows].map((row) => row.map(escape).join(",")).join("\r\n")}`;
  const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}
