-- 012_sale_catalog.sql
-- Katalog menentukan barang yang dapat dijual, harga jual, dan qty bawaan transaksi.

create table if not exists public.inventory_sale_products (
  item_id uuid primary key references public.inventory_items(id) on delete restrict,
  unit_price numeric not null check (unit_price >= 0),
  default_quantity numeric not null default 1 check (default_quantity > 0),
  created_by text not null,
  updated_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.inventory_sale_products enable row level security;
revoke all on table public.inventory_sale_products from anon, authenticated;

create or replace function public.secure_get_inventory_sale_products(p_token text)
returns table(item_id uuid,unit_price numeric,default_quantity numeric,created_by text,updated_by text,created_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
  if public.validate_session_token(p_token) is null then raise exception 'Unauthorized or expired session'; end if;
  return query select p.item_id,p.unit_price,p.default_quantity,p.created_by,p.updated_by,p.created_at,p.updated_at from public.inventory_sale_products p order by p.created_at;
end $$;

create or replace function public.secure_save_inventory_sale_product(p_token text,p_item_id uuid,p_unit_price numeric,p_default_quantity numeric)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor text; v_role text; v_item public.inventory_items%rowtype; v_stock numeric;
begin
  select u.username,u.role into v_actor,v_role from public.app_sessions s join public.app_users u on u.id=s.user_id where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_actor is null then return null; end if;
  if v_role<>'admin' then raise exception 'Hanya admin yang dapat mengatur katalog penjualan'; end if;
  if coalesce(p_unit_price,-1)<0 then raise exception 'Harga jual tidak boleh negatif'; end if;
  if coalesce(p_default_quantity,0)<=0 then raise exception 'Jumlah bawaan harus lebih dari nol'; end if;
  select * into v_item from public.inventory_items where id=p_item_id;
  if v_item.id is null then raise exception 'Barang tidak ditemukan'; end if;
  if v_item.is_archived then raise exception 'Barang yang diarsipkan tidak dapat dimasukkan ke katalog'; end if;
  select v_item.initial_stock+coalesce(sum(public.inventory_movement_delta(t.type,t.quantity,t.related_loan_id)),0)
    into v_stock from public.inventory_transactions t where t.item_id=p_item_id
      and not exists(select 1 from public.inventory_transaction_reversals r where r.transaction_id=t.id);
  if p_default_quantity>v_stock then raise exception 'Jumlah bawaan melebihi stok tersedia: tersisa %',v_stock; end if;
  insert into public.inventory_sale_products(item_id,unit_price,default_quantity,created_by,updated_by)
    values(p_item_id,p_unit_price,p_default_quantity,v_actor,v_actor)
  on conflict(item_id) do update set unit_price=excluded.unit_price,default_quantity=excluded.default_quantity,updated_by=v_actor,updated_at=now();
  return p_item_id;
end $$;

create or replace function public.secure_delete_inventory_sale_product(p_token text,p_item_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_actor text; v_role text;
begin
  select u.username,u.role into v_actor,v_role from public.app_sessions s join public.app_users u on u.id=s.user_id where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_actor is null then return false; end if;
  if v_role<>'admin' then raise exception 'Hanya admin yang dapat mengatur katalog penjualan'; end if;
  delete from public.inventory_sale_products where item_id=p_item_id;
  return found;
end $$;

-- Harga transaksi berasal dari katalog agar petugas hanya mengatur qty ketika menjual.
create or replace function public.secure_create_inventory_sale(
  p_token text,p_item_id uuid,p_quantity numeric,p_unit_price numeric,p_sale_date date,p_customer_name text,p_notes text
)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor text; v_item public.inventory_items%rowtype; v_stock numeric; v_tx uuid; v_sale uuid; v_unit_price numeric;
begin
  perform pg_catalog.pg_advisory_xact_lock_shared(740011);
  select u.username into v_actor from public.app_sessions s join public.app_users u on u.id=s.user_id where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_actor is null then return null; end if;
  if exists(select 1 from public.inventory_stocktakes where status='draft') then raise exception 'Pergerakan stok dibekukan selama stock opname berjalan'; end if;
  if coalesce(p_quantity,0)<=0 then raise exception 'Jumlah jual harus lebih dari nol'; end if;
  select * into v_item from public.inventory_items where id=p_item_id for update;
  if v_item.id is null or v_item.is_archived then raise exception 'Barang tidak tersedia untuk dijual'; end if;
  select unit_price into v_unit_price from public.inventory_sale_products where item_id=p_item_id;
  if v_unit_price is null then raise exception 'Barang belum dimasukkan ke katalog penjualan'; end if;
  select v_item.initial_stock+coalesce(sum(public.inventory_movement_delta(t.type,t.quantity,t.related_loan_id)),0) into v_stock from public.inventory_transactions t where t.item_id=p_item_id and not exists(select 1 from public.inventory_transaction_reversals r where r.transaction_id=t.id);
  if v_stock<p_quantity then raise exception 'Stok tidak mencukupi: tersisa %, diminta %',v_stock,p_quantity; end if;
  insert into public.inventory_transactions(item_id,type,quantity,transaction_date,is_returnable,activity_name,recorded_by,notes,created_by,updated_by) values(p_item_id,'Keluar',p_quantity,coalesce(p_sale_date,current_date),false,'Penjualan',v_actor,nullif(btrim(p_notes),''),v_actor,v_actor) returning id into v_tx;
  insert into public.inventory_sales(transaction_id,item_id,quantity,unit_price,sale_date,customer_name,notes,created_by) values(v_tx,p_item_id,p_quantity,v_unit_price,coalesce(p_sale_date,current_date),nullif(btrim(p_customer_name),''),nullif(btrim(p_notes),''),v_actor) returning id into v_sale;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,new_data) values('transaction',v_sale,'Penjualan - '||v_item.name,'create',v_actor,jsonb_build_object('transaction_id',v_tx,'quantity',p_quantity,'unit_price',v_unit_price,'total_amount',p_quantity*v_unit_price));
  return v_sale;
end $$;

revoke all on function public.secure_get_inventory_sale_products(text) from public;
revoke all on function public.secure_save_inventory_sale_product(text,uuid,numeric,numeric) from public;
revoke all on function public.secure_delete_inventory_sale_product(text,uuid) from public;
revoke all on function public.secure_create_inventory_sale(text,uuid,numeric,numeric,date,text,text) from public;
grant execute on function public.secure_get_inventory_sale_products(text) to anon,authenticated;
grant execute on function public.secure_save_inventory_sale_product(text,uuid,numeric,numeric) to anon,authenticated;
grant execute on function public.secure_delete_inventory_sale_product(text,uuid) to anon,authenticated;
grant execute on function public.secure_create_inventory_sale(text,uuid,numeric,numeric,date,text,text) to anon,authenticated;
notify pgrst,'reload schema';
