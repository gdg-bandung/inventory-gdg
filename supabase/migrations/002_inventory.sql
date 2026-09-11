-- 002_inventory.sql

create table if not exists public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null,
  code text not null,
  unit text not null default 'pcs',
  initial_stock numeric not null default 0,
  min_stock numeric not null default 0,
  condition text,
  location text,
  purchase_price numeric,
  purchase_date date,
  expiry_date date,
  owner_division text,
  penanggung_jawab text,
  notes text,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint inventory_items_name_not_blank check (btrim(name) <> ''),
  constraint inventory_items_code_not_blank check (btrim(code) <> ''),
  constraint inventory_items_category_check check (category in ('Barang Habis Pakai', 'Barang Tetap', 'Konsumsi', 'Lainnya')),
  constraint inventory_items_initial_stock_check check (initial_stock >= 0),
  constraint inventory_items_min_stock_check check (min_stock >= 0),
  constraint inventory_items_purchase_price_check check (purchase_price is null or purchase_price >= 0)
);

create unique index if not exists inventory_items_code_lower_uidx
  on public.inventory_items(lower(code));
create index if not exists inventory_items_category_idx on public.inventory_items(category);
create index if not exists inventory_items_archived_idx on public.inventory_items(is_archived);

create table if not exists public.inventory_transactions (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.inventory_items(id) on delete cascade,
  type text not null,
  quantity numeric not null,
  transaction_date date not null default current_date,
  is_returnable boolean not null default false,
  expected_return_date date,
  activity_name text,
  handled_by text,
  recorded_by text not null,
  notes text,
  created_at timestamptz not null default now(),
  constraint inventory_transactions_type_check check (type in ('Masuk', 'Keluar', 'Kembali', 'Rusak', 'Hilang', 'Penyesuaian')),
  constraint inventory_transactions_quantity_check check (
    (type = 'Penyesuaian' and quantity <> 0)
    or (type <> 'Penyesuaian' and quantity > 0)
  )
);

create index if not exists inventory_transactions_item_id_idx on public.inventory_transactions(item_id);
create index if not exists inventory_transactions_date_idx on public.inventory_transactions(transaction_date desc, created_at desc);
create index if not exists inventory_transactions_activity_idx on public.inventory_transactions(activity_name) where activity_name is not null;

alter table public.inventory_items enable row level security;
alter table public.inventory_transactions enable row level security;
revoke all on table public.inventory_items, public.inventory_transactions from anon, authenticated;

create or replace function public.inventory_movement_delta(p_type text, p_quantity numeric)
returns numeric
language sql
immutable
security invoker
set search_path = ''
as $$
  select case
    when p_type in ('Masuk', 'Kembali', 'Penyesuaian') then p_quantity
    when p_type in ('Keluar', 'Rusak', 'Hilang') then -abs(p_quantity)
    else 0::numeric
  end;
$$;

revoke all on function public.inventory_movement_delta(text, numeric) from public;
