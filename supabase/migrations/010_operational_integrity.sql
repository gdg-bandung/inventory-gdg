-- 010_operational_integrity.sql
-- Reversal immutable, freeze stock opname, RBAC operasional, dan identitas peminjam.

alter table public.inventory_transactions
  add column if not exists borrower_user_id uuid,
  add column if not exists external_borrower_name text,
  add column if not exists stocktake_id uuid;

do $$ begin
  if not exists(select 1 from pg_catalog.pg_constraint where conname='inventory_transactions_borrower_user_fk') then
    alter table public.inventory_transactions add constraint inventory_transactions_borrower_user_fk
      foreign key(borrower_user_id) references public.app_users(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_catalog.pg_constraint where conname='inventory_transactions_stocktake_fk') then
    alter table public.inventory_transactions add constraint inventory_transactions_stocktake_fk
      foreign key(stocktake_id) references public.inventory_stocktakes(id) on delete restrict;
  end if;
end $$;

create table if not exists public.inventory_transaction_reversals(
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null unique references public.inventory_transactions(id) on delete restrict,
  reason text not null check(btrim(reason)<>''),
  reversed_by text not null,
  created_at timestamptz not null default now()
);
create index if not exists inventory_transaction_reversals_created_idx on public.inventory_transaction_reversals(created_at desc);
create index if not exists inventory_transactions_stocktake_idx on public.inventory_transactions(stocktake_id) where stocktake_id is not null;
create unique index if not exists inventory_one_draft_stocktake_uidx on public.inventory_stocktakes((status)) where status='draft';
alter table public.inventory_transaction_reversals enable row level security;
revoke all on table public.inventory_transaction_reversals from anon,authenticated;

-- Hubungkan adjustment stock opname lama melalui audit metadata migration 009.
update public.inventory_transactions t set stocktake_id=(a.new_data->>'stocktake_id')::uuid
from public.inventory_audit_logs a
where a.entity_type='transaction' and a.entity_id=t.id and t.stocktake_id is null
  and a.new_data ? 'stocktake_id'
  and (a.new_data->>'stocktake_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

-- Data pinjaman lama memakai handled_by sebagai identitas pengguna.
update public.inventory_transactions t set borrower_user_id=u.id
from public.app_users u
where t.type='Keluar' and t.is_returnable and t.borrower_user_id is null
  and t.external_borrower_name is null and lower(t.handled_by)=lower(u.username);
update public.inventory_transactions t set external_borrower_name=t.handled_by
where t.type='Keluar' and t.is_returnable and t.borrower_user_id is null
  and t.external_borrower_name is null and nullif(btrim(t.handled_by),'') is not null;

create or replace function public.secure_get_borrower_options(p_token text)
returns table(id uuid,username text,full_name text)
language plpgsql stable security definer set search_path=''
as $$ begin
  if public.validate_session_token(p_token) is null then raise exception 'Unauthorized or expired session'; end if;
  return query select u.id,u.username,u.full_name from public.app_users u where u.is_active order by u.full_name nulls last,u.username;
end $$;

drop function if exists public.secure_get_inventory_items(text);
create function public.secure_get_inventory_items(p_token text)
returns table(
  id uuid,name text,category text,code text,unit text,initial_stock numeric,min_stock numeric,
  condition text,location text,purchase_price numeric,purchase_date date,expiry_date date,
  owner_division text,penanggung_jawab text,notes text,is_archived boolean,created_at timestamptz,
  updated_at timestamptz,current_stock numeric,outstanding numeric,last_movement_at timestamptz,
  created_by text,updated_by text
)
language plpgsql stable security definer set search_path=''
as $$ begin
  if public.validate_session_token(p_token) is null then raise exception 'Unauthorized or expired session'; end if;
  return query
  select i.id,i.name,i.category,i.code,i.unit,i.initial_stock,i.min_stock,i.condition,i.location,
    i.purchase_price,i.purchase_date,i.expiry_date,i.owner_division,i.penanggung_jawab,i.notes,
    i.is_archived,i.created_at,i.updated_at,
    i.initial_stock+coalesce(sum(public.inventory_movement_delta(t.type,t.quantity,t.related_loan_id)),0),
    greatest(0::numeric,coalesce(sum(case when t.type='Keluar' and t.is_returnable then t.quantity when t.related_loan_id is not null and t.type in ('Kembali','Rusak','Hilang') then -abs(t.quantity) else 0 end),0)),
    max(t.transaction_date::timestamptz),i.created_by,i.updated_by
  from public.inventory_items i
  left join public.inventory_transactions t on t.item_id=i.id
    and not exists(select 1 from public.inventory_transaction_reversals r where r.transaction_id=t.id)
  group by i.id order by i.is_archived,i.category,i.name;
end $$;

drop function if exists public.secure_get_inventory_transactions(text);
create function public.secure_get_inventory_transactions(p_token text)
returns table(
  id uuid,item_id uuid,type text,quantity numeric,transaction_date date,is_returnable boolean,
  expected_return_date date,activity_name text,handled_by text,recorded_by text,notes text,
  created_at timestamptz,item_name text,item_code text,item_category text,item_unit text,
  related_loan_id uuid,created_by text,updated_by text,updated_at timestamptz,
  borrower_user_id uuid,external_borrower_name text,borrower_username text,borrower_full_name text,
  stocktake_id uuid,reversed_at timestamptz,reversed_by text,reversal_reason text
)
language plpgsql stable security definer set search_path=''
as $$ begin
  if public.validate_session_token(p_token) is null then raise exception 'Unauthorized or expired session'; end if;
  return query
  select t.id,t.item_id,t.type,t.quantity,t.transaction_date,t.is_returnable,t.expected_return_date,
    t.activity_name,t.handled_by,t.recorded_by,t.notes,t.created_at,i.name,i.code,i.category,i.unit,
    t.related_loan_id,t.created_by,t.updated_by,t.updated_at,t.borrower_user_id,t.external_borrower_name,
    bu.username,bu.full_name,t.stocktake_id,r.created_at,r.reversed_by,r.reason
  from public.inventory_transactions t join public.inventory_items i on i.id=t.item_id
  left join public.app_users bu on bu.id=t.borrower_user_id
  left join public.inventory_transaction_reversals r on r.transaction_id=t.id
  order by t.transaction_date desc,t.created_at desc;
end $$;

drop function if exists public.secure_save_inventory_item(text,uuid,text,text,text,text,numeric,numeric,text,text,numeric,date,date,text,text,text,boolean);
create function public.secure_save_inventory_item(
  p_token text,p_id uuid,p_name text,p_category text,p_code text,p_unit text,
  p_initial_stock numeric,p_min_stock numeric,p_condition text,p_location text,
  p_purchase_price numeric,p_purchase_date date,p_expiry_date date,p_owner_division text,
  p_penanggung_jawab text,p_notes text,p_is_archived boolean
)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_actor text; v_role text; v_id uuid; v_old public.inventory_items%rowtype; v_new public.inventory_items%rowtype; v_outstanding numeric;
begin
  perform pg_catalog.pg_advisory_xact_lock_shared(740011);
  select u.username,u.role into v_actor,v_role from public.app_sessions s join public.app_users u on u.id=s.user_id
    where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_actor is null then return null; end if;
  if v_role<>'admin' then raise exception 'Hanya admin yang dapat mengelola master barang'; end if;
  if exists(select 1 from public.inventory_stocktakes where status='draft') then raise exception 'Master barang dibekukan selama stock opname berjalan'; end if;
  if btrim(coalesce(p_name,''))='' then raise exception 'Nama barang wajib diisi'; end if;
  if btrim(coalesce(p_code,''))='' then raise exception 'Kode/SKU wajib diisi'; end if;
  if p_category not in ('Barang Habis Pakai','Barang Tetap','Konsumsi','Lainnya') then raise exception 'Kategori barang tidak valid'; end if;
  if coalesce(p_initial_stock,0)<0 or coalesce(p_min_stock,0)<0 then raise exception 'Stok awal dan stok minimum tidak boleh negatif'; end if;
  if p_purchase_price is not null and p_purchase_price<0 then raise exception 'Harga beli tidak boleh negatif'; end if;
  if p_id is null then
    insert into public.inventory_items(name,category,code,unit,initial_stock,min_stock,condition,location,purchase_price,purchase_date,expiry_date,owner_division,penanggung_jawab,notes,is_archived,created_by,updated_by)
    values(btrim(p_name),p_category,btrim(p_code),coalesce(nullif(btrim(p_unit),''),'pcs'),coalesce(p_initial_stock,0),coalesce(p_min_stock,0),nullif(btrim(p_condition),''),nullif(btrim(p_location),''),p_purchase_price,p_purchase_date,p_expiry_date,nullif(btrim(p_owner_division),''),nullif(btrim(p_penanggung_jawab),''),nullif(btrim(p_notes),''),coalesce(p_is_archived,false),v_actor,v_actor)
    returning * into v_new; v_id:=v_new.id;
    insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,new_data) values('item',v_id,v_new.name,'create',v_actor,to_jsonb(v_new));
  else
    select * into v_old from public.inventory_items where id=p_id for update;
    if v_old.id is null then raise exception 'Barang tidak ditemukan'; end if;
    if p_initial_stock<>v_old.initial_stock and (exists(select 1 from public.inventory_transactions where item_id=p_id) or exists(select 1 from public.inventory_stocktake_lines where item_id=p_id)) then
      raise exception 'Stok awal tidak dapat diubah setelah barang memiliki riwayat; gunakan koreksi stok';
    end if;
    if coalesce(p_is_archived,false) and not v_old.is_archived then
      select coalesce(sum(case when t.type='Keluar' and t.is_returnable then t.quantity when t.related_loan_id is not null and t.type in ('Kembali','Rusak','Hilang') then -abs(t.quantity) else 0 end),0)
      into v_outstanding from public.inventory_transactions t where t.item_id=p_id
        and not exists(select 1 from public.inventory_transaction_reversals r where r.transaction_id=t.id);
      if v_outstanding>0 then raise exception 'Barang masih dipinjam dan belum dapat diarsipkan'; end if;
    end if;
    update public.inventory_items set name=btrim(p_name),category=p_category,code=btrim(p_code),unit=coalesce(nullif(btrim(p_unit),''),'pcs'),
      initial_stock=coalesce(p_initial_stock,0),min_stock=coalesce(p_min_stock,0),condition=nullif(btrim(p_condition),''),location=nullif(btrim(p_location),''),
      purchase_price=p_purchase_price,purchase_date=p_purchase_date,expiry_date=p_expiry_date,owner_division=nullif(btrim(p_owner_division),''),
      penanggung_jawab=nullif(btrim(p_penanggung_jawab),''),notes=nullif(btrim(p_notes),''),is_archived=coalesce(p_is_archived,false),updated_at=now(),updated_by=v_actor
      where id=p_id returning * into v_new; v_id:=v_new.id;
    insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,old_data,new_data)
      values('item',v_id,v_new.name,case when not v_old.is_archived and v_new.is_archived then 'archive' when v_old.is_archived and not v_new.is_archived then 'restore' else 'update' end,v_actor,to_jsonb(v_old),to_jsonb(v_new));
  end if;
  return v_id;
exception when unique_violation then raise exception 'Kode/SKU "%" sudah dipakai barang lain',btrim(p_code);
end $$;

drop function if exists public.secure_delete_inventory_item(text,uuid);
create function public.secure_delete_inventory_item(p_token text,p_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_actor text; v_role text; v_old public.inventory_items%rowtype; v_count integer;
begin
  perform pg_catalog.pg_advisory_xact_lock_shared(740011);
  select u.username,u.role into v_actor,v_role from public.app_sessions s join public.app_users u on u.id=s.user_id
    where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_actor is null then return false; end if;
  if v_role<>'admin' then raise exception 'Hanya admin yang dapat menghapus barang'; end if;
  if exists(select 1 from public.inventory_stocktakes where status='draft') then raise exception 'Master barang dibekukan selama stock opname berjalan'; end if;
  select * into v_old from public.inventory_items where id=p_id for update;
  if v_old.id is null then return false; end if;
  if exists(select 1 from public.inventory_transactions where item_id=p_id) or exists(select 1 from public.inventory_stocktake_lines where item_id=p_id) then
    raise exception 'Barang yang memiliki riwayat tidak dapat dihapus; arsipkan barang sebagai gantinya';
  end if;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,old_data) values('item',p_id,v_old.name,'delete',v_actor,to_jsonb(v_old));
  delete from public.inventory_items where id=p_id; get diagnostics v_count=row_count; return v_count>0;
end $$;

create or replace function public.enforce_inventory_pic()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_loan public.inventory_transactions%rowtype; v_borrower text;
begin
  if new.type='Keluar' and new.is_returnable then
    if new.borrower_user_id is not null then select coalesce(u.full_name,u.username) into v_borrower from public.app_users u where u.id=new.borrower_user_id and u.is_active; end if;
    new.handled_by:=coalesce(v_borrower,nullif(btrim(new.external_borrower_name),''));
  elsif new.related_loan_id is not null then
    select * into v_loan from public.inventory_transactions where id=new.related_loan_id;
    new.borrower_user_id:=v_loan.borrower_user_id; new.external_borrower_name:=v_loan.external_borrower_name; new.handled_by:=v_loan.handled_by;
  else
    new.borrower_user_id:=null; new.external_borrower_name:=null; new.handled_by:=new.recorded_by;
  end if;
  return new;
end $$;

drop function if exists public.secure_save_inventory_transaction(text,uuid,uuid,text,numeric,date,boolean,date,text,text,text,uuid);
create function public.secure_save_inventory_transaction(
  p_token text,p_id uuid,p_item_id uuid,p_type text,p_quantity numeric,p_transaction_date date,
  p_is_returnable boolean,p_expected_return_date date,p_activity_name text,p_notes text,
  p_related_loan_id uuid,p_borrower_user_id uuid,p_external_borrower_name text
)
returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_actor text; v_role text; v_id uuid; v_initial numeric; v_stock_before numeric; v_stock_after numeric; v_item_name text; v_item_archived boolean;
  v_existing_item_id uuid; v_returnable boolean:=case when p_type='Keluar' then coalesce(p_is_returnable,false) else false end;
  v_return_date date:=case when p_type='Keluar' and coalesce(p_is_returnable,false) then p_expected_return_date else null end;
  v_loan public.inventory_transactions%rowtype; v_loan_remaining numeric; v_old public.inventory_transactions%rowtype; v_new public.inventory_transactions%rowtype;
  v_borrower_user_id uuid; v_external_name text;
begin
  perform pg_catalog.pg_advisory_xact_lock_shared(740011);
  select u.username,u.role into v_actor,v_role from public.app_sessions s join public.app_users u on u.id=s.user_id
    where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_actor is null then return null; end if;
  if exists(select 1 from public.inventory_stocktakes where status='draft') then raise exception 'Pergerakan stok dibekukan selama stock opname berjalan'; end if;
  if p_type not in ('Masuk','Keluar','Kembali','Rusak','Hilang','Penyesuaian') then raise exception 'Jenis catatan tidak valid'; end if;
  if p_id is not null and v_role<>'admin' then raise exception 'Hanya admin yang dapat mengubah catatan lama'; end if;
  if p_id is null and v_role<>'admin' and p_type not in ('Masuk','Keluar','Kembali') then raise exception 'Jenis catatan ini hanya dapat dibuat admin'; end if;
  if p_id is not null then
    select * into v_old from public.inventory_transactions where id=p_id for update;
    if v_old.id is null then raise exception 'Catatan tidak ditemukan'; end if;
    if v_old.item_id<>p_item_id then raise exception 'Barang pada catatan tidak dapat diganti'; end if;
    if v_old.stocktake_id is not null then raise exception 'Adjustment stock opname bersifat final dan tidak dapat diubah'; end if;
    if exists(select 1 from public.inventory_transaction_reversals where transaction_id=p_id) then raise exception 'Catatan yang sudah dibatalkan tidak dapat diubah'; end if;
    v_existing_item_id:=v_old.item_id;
  end if;
  select initial_stock,name,is_archived into v_initial,v_item_name,v_item_archived from public.inventory_items where id=p_item_id for update;
  if v_initial is null then raise exception 'Barang tidak ditemukan'; end if;
  if v_item_archived then raise exception 'Barang yang diarsipkan tidak dapat menerima pergerakan baru'; end if;
  if p_type='Penyesuaian' and coalesce(p_quantity,0)=0 then raise exception 'Nilai koreksi tidak boleh nol'; end if;
  if p_type<>'Penyesuaian' and coalesce(p_quantity,0)<=0 then raise exception 'Jumlah harus lebih dari nol'; end if;
  if p_type='Kembali' and p_related_loan_id is null then raise exception 'Pilih pinjaman yang dikembalikan'; end if;
  if p_related_loan_id is not null and p_type not in ('Kembali','Rusak','Hilang') then raise exception 'Relasi pinjaman hanya berlaku untuk kembali, rusak, atau hilang'; end if;
  if v_returnable then
    if v_return_date is null then raise exception 'Tanggal rencana kembali wajib diisi'; end if;
    if v_return_date<coalesce(p_transaction_date,current_date) then raise exception 'Tanggal kembali tidak boleh sebelum tanggal keluar'; end if;
    if (p_borrower_user_id is null)=(nullif(btrim(p_external_borrower_name),'') is null) then raise exception 'Pilih satu peminjam akun atau isi nama peminjam eksternal'; end if;
    if p_borrower_user_id is not null and not exists(select 1 from public.app_users where id=p_borrower_user_id and is_active) then raise exception 'Akun peminjam tidak aktif atau tidak ditemukan'; end if;
    v_borrower_user_id:=p_borrower_user_id; v_external_name:=nullif(btrim(p_external_borrower_name),'');
  end if;
  if p_related_loan_id is not null then
    select * into v_loan from public.inventory_transactions where id=p_related_loan_id for update;
    if v_loan.id is null or v_loan.type<>'Keluar' or not v_loan.is_returnable or v_loan.item_id<>p_item_id
       or exists(select 1 from public.inventory_transaction_reversals where transaction_id=v_loan.id) then raise exception 'Pinjaman tidak valid'; end if;
    select v_loan.quantity-coalesce(sum(abs(t.quantity)),0) into v_loan_remaining from public.inventory_transactions t
      where t.related_loan_id=v_loan.id and t.type in ('Kembali','Rusak','Hilang') and (p_id is null or t.id<>p_id)
        and not exists(select 1 from public.inventory_transaction_reversals r where r.transaction_id=t.id);
    if p_quantity>v_loan_remaining then raise exception 'Jumlah kembali melebihi pinjaman: tersisa %',greatest(v_loan_remaining,0); end if;
    v_borrower_user_id:=v_loan.borrower_user_id; v_external_name:=v_loan.external_borrower_name;
  end if;
  if p_id is not null and exists(select 1 from public.inventory_transactions t where t.related_loan_id=p_id and not exists(select 1 from public.inventory_transaction_reversals r where r.transaction_id=t.id)) then
    select coalesce(sum(abs(t.quantity)),0) into v_loan_remaining from public.inventory_transactions t where t.related_loan_id=p_id
      and not exists(select 1 from public.inventory_transaction_reversals r where r.transaction_id=t.id);
    if p_type<>'Keluar' or not v_returnable then raise exception 'Pinjaman yang sudah memiliki penyelesaian tidak dapat diubah menjadi jenis lain'; end if;
    if p_quantity<v_loan_remaining then raise exception 'Jumlah pinjaman tidak boleh lebih kecil dari % yang sudah diselesaikan',v_loan_remaining; end if;
  end if;
  select v_initial+coalesce(sum(public.inventory_movement_delta(t.type,t.quantity,t.related_loan_id)),0) into v_stock_before
    from public.inventory_transactions t where t.item_id=p_item_id and (p_id is null or t.id<>p_id)
      and not exists(select 1 from public.inventory_transaction_reversals r where r.transaction_id=t.id);
  v_stock_after:=v_stock_before+public.inventory_movement_delta(p_type,p_quantity,p_related_loan_id);
  if v_stock_after<0 then raise exception 'Stok tidak mencukupi: tersisa %, diminta %',v_stock_before,abs(p_quantity); end if;
  if p_id is null then
    insert into public.inventory_transactions(item_id,type,quantity,transaction_date,is_returnable,expected_return_date,activity_name,recorded_by,notes,related_loan_id,created_by,updated_by,borrower_user_id,external_borrower_name)
    values(p_item_id,p_type,p_quantity,coalesce(p_transaction_date,current_date),v_returnable,v_return_date,nullif(btrim(p_activity_name),''),v_actor,nullif(btrim(p_notes),''),p_related_loan_id,v_actor,v_actor,v_borrower_user_id,v_external_name)
    returning * into v_new; v_id:=v_new.id;
    insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,new_data) values('transaction',v_id,p_type||' - '||v_item_name,'create',v_actor,to_jsonb(v_new));
  else
    update public.inventory_transactions set type=p_type,quantity=p_quantity,transaction_date=coalesce(p_transaction_date,current_date),is_returnable=v_returnable,
      expected_return_date=v_return_date,activity_name=nullif(btrim(p_activity_name),''),notes=nullif(btrim(p_notes),''),related_loan_id=p_related_loan_id,
      borrower_user_id=v_borrower_user_id,external_borrower_name=v_external_name,updated_by=v_actor,updated_at=now()
      where id=p_id returning * into v_new; v_id:=v_new.id;
    insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,old_data,new_data) values('transaction',v_id,p_type||' - '||v_item_name,'update',v_actor,to_jsonb(v_old),to_jsonb(v_new));
  end if;
  return v_id;
end $$;

create or replace function public.secure_reverse_inventory_transaction(p_token text,p_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_actor text; v_role text; v_tx public.inventory_transactions%rowtype; v_item public.inventory_items%rowtype; v_stock_after numeric; v_id uuid;
begin
  perform pg_catalog.pg_advisory_xact_lock_shared(740011);
  select u.username,u.role into v_actor,v_role from public.app_sessions s join public.app_users u on u.id=s.user_id
    where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_actor is null then return null; end if;
  if v_role<>'admin' then raise exception 'Hanya admin yang dapat membatalkan transaksi'; end if;
  if exists(select 1 from public.inventory_stocktakes where status='draft') then raise exception 'Pergerakan stok dibekukan selama stock opname berjalan'; end if;
  if btrim(coalesce(p_reason,''))='' then raise exception 'Alasan pembatalan wajib diisi'; end if;
  select * into v_tx from public.inventory_transactions where id=p_id for update;
  if v_tx.id is null then raise exception 'Catatan tidak ditemukan'; end if;
  if v_tx.stocktake_id is not null then raise exception 'Adjustment stock opname bersifat final dan tidak dapat dibatalkan'; end if;
  if exists(select 1 from public.inventory_transaction_reversals where transaction_id=p_id) then raise exception 'Catatan sudah dibatalkan'; end if;
  if exists(select 1 from public.inventory_transactions t where t.related_loan_id=p_id and not exists(select 1 from public.inventory_transaction_reversals r where r.transaction_id=t.id)) then
    raise exception 'Batalkan catatan kembali/rusak/hilang terkait terlebih dahulu';
  end if;
  select * into v_item from public.inventory_items where id=v_tx.item_id for update;
  select v_item.initial_stock+coalesce(sum(public.inventory_movement_delta(t.type,t.quantity,t.related_loan_id)),0) into v_stock_after
    from public.inventory_transactions t where t.item_id=v_tx.item_id and t.id<>p_id
      and not exists(select 1 from public.inventory_transaction_reversals r where r.transaction_id=t.id);
  if v_stock_after<0 then raise exception 'Pembatalan akan membuat stok negatif'; end if;
  insert into public.inventory_transaction_reversals(transaction_id,reason,reversed_by) values(p_id,btrim(p_reason),v_actor) returning id into v_id;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,old_data,new_data)
    values('transaction',p_id,'Pembatalan - '||v_tx.type||' - '||v_item.name,'update',v_actor,to_jsonb(v_tx),jsonb_build_object('reversal_id',v_id,'reason',btrim(p_reason)));
  return v_id;
end $$;

-- Hard delete transaksi dinonaktifkan; koreksi histori harus melalui reversal.
revoke all on function public.secure_delete_inventory_transaction(text,uuid) from public,anon,authenticated;

-- Sesi stock opname adalah dokumen operasional; status cancelled tetap dipertahankan sebagai histori.
revoke all on function public.secure_delete_inventory_stocktake(text,uuid) from public,anon,authenticated;

create or replace function public.secure_create_inventory_stocktake(p_token text,p_title text,p_notes text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_actor text; v_role text; v_id uuid; v_count integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(740011);
  select u.username,u.role into v_actor,v_role from public.app_sessions s join public.app_users u on u.id=s.user_id
    where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_actor is null then return null; end if;
  if v_role<>'admin' then raise exception 'Hanya admin yang dapat membuka stock opname'; end if;
  if btrim(coalesce(p_title,''))='' then raise exception 'Judul stock opname wajib diisi'; end if;
  if exists(select 1 from public.inventory_stocktakes where status='draft') then raise exception 'Masih ada stock opname yang belum selesai'; end if;
  insert into public.inventory_stocktakes(title,notes,created_by) values(btrim(p_title),nullif(btrim(p_notes),''),v_actor) returning id into v_id;
  insert into public.inventory_stocktake_lines(stocktake_id,item_id,system_stock)
    select v_id,i.id,i.initial_stock+coalesce(sum(public.inventory_movement_delta(t.type,t.quantity,t.related_loan_id)),0)
    from public.inventory_items i left join public.inventory_transactions t on t.item_id=i.id
      and not exists(select 1 from public.inventory_transaction_reversals r where r.transaction_id=t.id)
    where not i.is_archived group by i.id;
  get diagnostics v_count=row_count; if v_count=0 then raise exception 'Belum ada barang aktif untuk dihitung'; end if;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,new_data) values('stocktake',v_id,btrim(p_title),'create',v_actor,jsonb_build_object('status','draft','stock_frozen',true));
  return v_id;
end $$;

create or replace function public.secure_complete_inventory_stocktake(p_token text,p_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_actor text; v_role text; v_take public.inventory_stocktakes%rowtype; v_line record; v_live numeric; v_diff numeric; v_tx uuid; v_variances integer:=0;
begin
  perform pg_catalog.pg_advisory_xact_lock(740011);
  select u.username,u.role into v_actor,v_role from public.app_sessions s join public.app_users u on u.id=s.user_id
    where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_actor is null then return false; end if;
  if v_role<>'admin' then raise exception 'Hanya admin yang dapat menyelesaikan stock opname'; end if;
  select * into v_take from public.inventory_stocktakes where id=p_id for update;
  if v_take.id is null then raise exception 'Stock opname tidak ditemukan'; end if;
  if v_take.status<>'draft' then raise exception 'Stock opname sudah ditutup'; end if;
  if exists(select 1 from public.inventory_stocktake_lines where stocktake_id=p_id and counted_stock is null) then raise exception 'Semua barang harus dihitung terlebih dahulu'; end if;
  for v_line in select l.*,i.name,i.initial_stock from public.inventory_stocktake_lines l join public.inventory_items i on i.id=l.item_id where l.stocktake_id=p_id order by l.item_id loop
    perform 1 from public.inventory_items where id=v_line.item_id for update;
    select v_line.initial_stock+coalesce(sum(public.inventory_movement_delta(t.type,t.quantity,t.related_loan_id)),0) into v_live
      from public.inventory_transactions t where t.item_id=v_line.item_id
        and not exists(select 1 from public.inventory_transaction_reversals r where r.transaction_id=t.id);
    v_diff:=v_line.counted_stock-v_live;
    update public.inventory_stocktake_lines set system_stock=v_live where stocktake_id=p_id and item_id=v_line.item_id;
    if v_diff<>0 then
      insert into public.inventory_transactions(item_id,type,quantity,transaction_date,is_returnable,activity_name,recorded_by,notes,created_by,updated_by,stocktake_id)
      values(v_line.item_id,'Penyesuaian',v_diff,current_date,false,'Stock opname: '||v_take.title,v_actor,'Selisih stock opname',v_actor,v_actor,p_id)
      returning id into v_tx;
      insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,new_data)
      values('transaction',v_tx,'Penyesuaian - '||v_line.name,'create',v_actor,jsonb_build_object('stocktake_id',p_id,'system_stock',v_live,'counted_stock',v_line.counted_stock,'difference',v_diff,'locked',true));
      v_variances:=v_variances+1;
    end if;
  end loop;
  update public.inventory_stocktakes set status='completed',completed_by=v_actor,completed_at=now(),updated_at=now() where id=p_id;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,old_data,new_data)
    values('stocktake',p_id,v_take.title,'update',v_actor,jsonb_build_object('status','draft'),jsonb_build_object('status','completed','variance_items',v_variances));
  return true;
end $$;

revoke all on function public.secure_get_borrower_options(text) from public;
revoke all on function public.secure_get_inventory_items(text) from public;
revoke all on function public.secure_get_inventory_transactions(text) from public;
revoke all on function public.secure_save_inventory_item(text,uuid,text,text,text,text,numeric,numeric,text,text,numeric,date,date,text,text,text,boolean) from public;
revoke all on function public.secure_delete_inventory_item(text,uuid) from public;
revoke all on function public.secure_save_inventory_transaction(text,uuid,uuid,text,numeric,date,boolean,date,text,text,uuid,uuid,text) from public;
revoke all on function public.secure_reverse_inventory_transaction(text,uuid,text) from public;
revoke all on function public.enforce_inventory_pic() from public;
revoke all on function public.secure_create_inventory_stocktake(text,text,text) from public;
revoke all on function public.secure_complete_inventory_stocktake(text,uuid) from public;
grant execute on function public.secure_get_borrower_options(text) to anon,authenticated;
grant execute on function public.secure_get_inventory_items(text) to anon,authenticated;
grant execute on function public.secure_get_inventory_transactions(text) to anon,authenticated;
grant execute on function public.secure_save_inventory_item(text,uuid,text,text,text,text,numeric,numeric,text,text,numeric,date,date,text,text,text,boolean) to anon,authenticated;
grant execute on function public.secure_delete_inventory_item(text,uuid) to anon,authenticated;
grant execute on function public.secure_save_inventory_transaction(text,uuid,uuid,text,numeric,date,boolean,date,text,text,uuid,uuid,text) to anon,authenticated;
grant execute on function public.secure_reverse_inventory_transaction(text,uuid,text) to anon,authenticated;
grant execute on function public.secure_create_inventory_stocktake(text,text,text) to anon,authenticated;
grant execute on function public.secure_complete_inventory_stocktake(text,uuid) to anon,authenticated;
notify pgrst,'reload schema';
