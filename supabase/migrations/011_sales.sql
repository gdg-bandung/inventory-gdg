-- 011_sales.sql
-- Penjualan tercatat sebagai dokumen tersendiri dan selalu mempunyai transaksi stok Keluar.

create table if not exists public.inventory_sales (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null unique references public.inventory_transactions(id) on delete restrict,
  item_id uuid not null references public.inventory_items(id) on delete restrict,
  quantity numeric not null check (quantity > 0),
  unit_price numeric not null check (unit_price >= 0),
  sale_date date not null default current_date,
  customer_name text,
  notes text,
  status text not null default 'active' check (status in ('active', 'cancelled')),
  created_by text not null,
  cancelled_by text,
  cancelled_at timestamptz,
  cancellation_reason text,
  created_at timestamptz not null default now(),
  constraint inventory_sales_customer_not_blank check (customer_name is null or btrim(customer_name) <> ''),
  constraint inventory_sales_cancelled_fields check (
    (status = 'active' and cancelled_by is null and cancelled_at is null and cancellation_reason is null)
    or (status = 'cancelled' and cancelled_by is not null and cancelled_at is not null and cancellation_reason is not null)
  )
);
create index if not exists inventory_sales_date_idx on public.inventory_sales(sale_date desc, created_at desc);
create index if not exists inventory_sales_item_idx on public.inventory_sales(item_id);
alter table public.inventory_sales enable row level security;
revoke all on table public.inventory_sales from anon, authenticated;

-- Penjualan tidak boleh diubah/dibatalkan dari menu pergerakan biasa.
create or replace function public.prevent_direct_sales_transaction_change()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if exists(select 1 from public.inventory_sales s where s.transaction_id=(case when tg_op='INSERT' then new.transaction_id else old.id end) and s.status='active')
    and current_setting('app.cancel_inventory_sale', true) is distinct from 'on' then
    raise exception 'Transaksi penjualan dikelola melalui menu Penjualan';
  end if;
  return case when tg_op='INSERT' then new else old end;
end $$;

drop trigger if exists inventory_sales_transaction_guard_update on public.inventory_transactions;
create trigger inventory_sales_transaction_guard_update before update on public.inventory_transactions
  for each row execute function public.prevent_direct_sales_transaction_change();
drop trigger if exists inventory_sales_transaction_guard_reversal on public.inventory_transaction_reversals;
create trigger inventory_sales_transaction_guard_reversal before insert on public.inventory_transaction_reversals
  for each row execute function public.prevent_direct_sales_transaction_change();

create or replace function public.secure_get_inventory_sales(p_token text)
returns table(
  id uuid, transaction_id uuid, item_id uuid, item_name text, item_code text, item_unit text,
  quantity numeric, unit_price numeric, total_amount numeric, sale_date date, customer_name text,
  notes text, status text, created_by text, cancelled_by text, cancelled_at timestamptz,
  cancellation_reason text, created_at timestamptz
)
language plpgsql stable security definer set search_path='' as $$
begin
  if public.validate_session_token(p_token) is null then raise exception 'Unauthorized or expired session'; end if;
  return query
  select s.id,s.transaction_id,s.item_id,i.name,i.code,i.unit,s.quantity,s.unit_price,
    s.quantity*s.unit_price,s.sale_date,s.customer_name,s.notes,s.status,s.created_by,
    s.cancelled_by,s.cancelled_at,s.cancellation_reason,s.created_at
  from public.inventory_sales s join public.inventory_items i on i.id=s.item_id
  order by s.sale_date desc,s.created_at desc;
end $$;

create or replace function public.secure_create_inventory_sale(
  p_token text,p_item_id uuid,p_quantity numeric,p_unit_price numeric,p_sale_date date,
  p_customer_name text,p_notes text
)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor text; v_item public.inventory_items%rowtype; v_stock numeric; v_tx uuid; v_sale uuid;
begin
  perform pg_catalog.pg_advisory_xact_lock_shared(740011);
  select u.username into v_actor from public.app_sessions s join public.app_users u on u.id=s.user_id
    where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_actor is null then return null; end if;
  if exists(select 1 from public.inventory_stocktakes where status='draft') then raise exception 'Pergerakan stok dibekukan selama stock opname berjalan'; end if;
  if coalesce(p_quantity,0)<=0 then raise exception 'Jumlah jual harus lebih dari nol'; end if;
  if coalesce(p_unit_price,-1)<0 then raise exception 'Harga jual tidak boleh negatif'; end if;
  select * into v_item from public.inventory_items where id=p_item_id for update;
  if v_item.id is null then raise exception 'Barang tidak ditemukan'; end if;
  if v_item.is_archived then raise exception 'Barang yang diarsipkan tidak dapat dijual'; end if;
  select v_item.initial_stock+coalesce(sum(public.inventory_movement_delta(t.type,t.quantity,t.related_loan_id)),0)
    into v_stock from public.inventory_transactions t where t.item_id=p_item_id
      and not exists(select 1 from public.inventory_transaction_reversals r where r.transaction_id=t.id);
  if v_stock<p_quantity then raise exception 'Stok tidak mencukupi: tersisa %, diminta %',v_stock,p_quantity; end if;
  insert into public.inventory_transactions(item_id,type,quantity,transaction_date,is_returnable,activity_name,recorded_by,notes,created_by,updated_by)
    values(p_item_id,'Keluar',p_quantity,coalesce(p_sale_date,current_date),false,'Penjualan',v_actor,nullif(btrim(p_notes),''),v_actor,v_actor)
    returning id into v_tx;
  insert into public.inventory_sales(transaction_id,item_id,quantity,unit_price,sale_date,customer_name,notes,created_by)
    values(v_tx,p_item_id,p_quantity,p_unit_price,coalesce(p_sale_date,current_date),nullif(btrim(p_customer_name),''),nullif(btrim(p_notes),''),v_actor)
    returning id into v_sale;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,new_data)
    values('transaction',v_sale,'Penjualan - '||v_item.name,'create',v_actor,jsonb_build_object('transaction_id',v_tx,'quantity',p_quantity,'unit_price',p_unit_price,'total_amount',p_quantity*p_unit_price));
  return v_sale;
end $$;

create or replace function public.secure_cancel_inventory_sale(p_token text,p_id uuid,p_reason text)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_actor text; v_role text; v_sale public.inventory_sales%rowtype; v_item_name text;
begin
  perform pg_catalog.pg_advisory_xact_lock_shared(740011);
  select u.username,u.role into v_actor,v_role from public.app_sessions s join public.app_users u on u.id=s.user_id
    where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_actor is null then return false; end if;
  if v_role<>'admin' then raise exception 'Hanya admin yang dapat membatalkan penjualan'; end if;
  if exists(select 1 from public.inventory_stocktakes where status='draft') then raise exception 'Pergerakan stok dibekukan selama stock opname berjalan'; end if;
  if btrim(coalesce(p_reason,''))='' then raise exception 'Alasan pembatalan wajib diisi'; end if;
  select * into v_sale from public.inventory_sales where id=p_id for update;
  if v_sale.id is null then raise exception 'Catatan penjualan tidak ditemukan'; end if;
  if v_sale.status='cancelled' then raise exception 'Penjualan sudah dibatalkan'; end if;
  perform set_config('app.cancel_inventory_sale','on',true);
  insert into public.inventory_transaction_reversals(transaction_id,reason,reversed_by)
    values(v_sale.transaction_id,'Pembatalan penjualan: '||btrim(p_reason),v_actor);
  update public.inventory_sales set status='cancelled',cancelled_by=v_actor,cancelled_at=now(),cancellation_reason=btrim(p_reason) where id=p_id;
  select name into v_item_name from public.inventory_items where id=v_sale.item_id;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,old_data,new_data)
    values('transaction',p_id,'Pembatalan penjualan - '||v_item_name,'update',v_actor,jsonb_build_object('status','active'),jsonb_build_object('status','cancelled','reason',btrim(p_reason)));
  return true;
end $$;

revoke all on function public.prevent_direct_sales_transaction_change() from public;
revoke all on function public.secure_get_inventory_sales(text) from public;
revoke all on function public.secure_create_inventory_sale(text,uuid,numeric,numeric,date,text,text) from public;
revoke all on function public.secure_cancel_inventory_sale(text,uuid,text) from public;
grant execute on function public.secure_get_inventory_sales(text) to anon,authenticated;
grant execute on function public.secure_create_inventory_sale(text,uuid,numeric,numeric,date,text,text) to anon,authenticated;
grant execute on function public.secure_cancel_inventory_sale(text,uuid,text) to anon,authenticated;
notify pgrst,'reload schema';
