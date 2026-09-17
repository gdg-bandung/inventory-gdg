export type InventoryCategory =
  | "Barang Habis Pakai"
  | "Barang Tetap"
  | "Konsumsi"
  | "Lainnya";

export type TransactionType =
  | "Masuk"
  | "Keluar"
  | "Kembali"
  | "Rusak"
  | "Hilang"
  | "Penyesuaian";

export interface SessionUser {
  username: string;
  full_name: string | null;
  role: "admin" | "member";
  expires_at?: string;
}

export interface InventoryItem {
  id: string;
  name: string;
  category: InventoryCategory;
  code: string;
  unit: string;
  initial_stock: number;
  min_stock: number;
  condition: string | null;
  location: string | null;
  purchase_price: number | null;
  purchase_date: string | null;
  expiry_date: string | null;
  owner_division: string | null;
  penanggung_jawab: string | null;
  notes: string | null;
  is_archived: boolean;
  created_at: string;
  updated_at: string;
  current_stock: number;
  outstanding: number;
  last_movement_at: string | null;
  created_by: string;
  updated_by: string;
}

export interface InventoryTransaction {
  id: string;
  item_id: string;
  type: TransactionType;
  quantity: number;
  transaction_date: string;
  is_returnable: boolean;
  expected_return_date: string | null;
  activity_name: string | null;
  handled_by: string | null;
  recorded_by: string;
  notes: string | null;
  created_at: string;
  related_loan_id: string | null;
  created_by: string;
  updated_by: string;
  updated_at: string;
  borrower_user_id: string | null;
  external_borrower_name: string | null;
  borrower_username: string | null;
  borrower_full_name: string | null;
  stocktake_id: string | null;
  reversed_at: string | null;
  reversed_by: string | null;
  reversal_reason: string | null;
  item_name: string;
  item_code: string;
  item_category: InventoryCategory;
  item_unit: string;
}

export interface InventorySale {
  id: string;
  transaction_id: string;
  item_id: string;
  item_name: string;
  item_code: string;
  item_unit: string;
  quantity: number;
  unit_price: number;
  total_amount: number;
  sale_date: string;
  customer_name: string | null;
  notes: string | null;
  status: "active" | "cancelled";
  created_by: string;
  cancelled_by: string | null;
  cancelled_at: string | null;
  cancellation_reason: string | null;
  created_at: string;
}

export interface SaleInput {
  item_id: string;
  quantity: number;
  unit_price: number;
  sale_date: string;
  customer_name?: string | null;
  notes?: string | null;
}

export interface InventorySaleProduct {
  item_id: string;
  unit_price: number;
  default_quantity: number;
  created_by: string;
  updated_by: string;
  created_at: string;
  updated_at: string;
}

export interface ItemInput {
  id?: string | null;
  name: string;
  category: InventoryCategory;
  code: string;
  unit: string;
  initial_stock: number;
  min_stock: number;
  condition?: string | null;
  location?: string | null;
  purchase_price?: number | null;
  purchase_date?: string | null;
  expiry_date?: string | null;
  owner_division?: string | null;
  penanggung_jawab?: string | null;
  notes?: string | null;
  is_archived?: boolean;
}

export interface TransactionInput {
  id?: string | null;
  item_id: string;
  type: TransactionType;
  quantity: number;
  transaction_date: string;
  is_returnable?: boolean;
  expected_return_date?: string | null;
  activity_name?: string | null;
  notes?: string | null;
  related_loan_id?: string | null;
  borrower_user_id?: string | null;
  external_borrower_name?: string | null;
}

export interface BorrowerOption {
  id: string;
  username: string;
  full_name: string | null;
}

export interface InventoryAuditLog {
  id: string;
  entity_type: "item" | "transaction" | "photo" | "user" | "stocktake";
  entity_id: string | null;
  entity_label: string;
  action: "create" | "update" | "delete" | "archive" | "restore";
  changed_by: string;
  old_data: Record<string, unknown> | null;
  new_data: Record<string, unknown> | null;
  created_at: string;
}

export interface InventoryPhoto {
  id: string;
  item_id: string;
  data_url: string;
  caption: string | null;
  recorded_by: string;
  created_at: string;
}

export interface AppUser {
  id: string;
  username: string;
  full_name: string | null;
  role: "admin" | "member";
  is_active: boolean;
  created_at: string;
  updated_at: string;
  active_sessions: number;
}

export interface InventoryStocktake {
  id: string;
  title: string;
  notes: string | null;
  status: "draft" | "completed" | "cancelled";
  created_by: string;
  completed_by: string | null;
  created_at: string;
  updated_at: string;
  completed_at: string | null;
  total_items: number;
  counted_items: number;
  variance_items: number;
}

export interface InventoryStocktakeLine {
  stocktake_id: string;
  item_id: string;
  item_name: string;
  item_code: string;
  item_unit: string;
  system_stock: number;
  counted_stock: number | null;
  difference: number | null;
  counted_by: string | null;
  counted_at: string | null;
}
