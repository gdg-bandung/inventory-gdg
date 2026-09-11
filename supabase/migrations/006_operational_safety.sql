-- 006_operational_safety.sql
-- Relasi pinjaman, audit trail, metadata pencatat, foto kondisi, dan guard arsip.

alter table public.inventory_items
  add column if not exists created_by text,
  add column if not exists updated_by text;

alter table public.inventory_transactions
  add column if not exists related_loan_id uuid,
  add column if not exists created_by text,
  add column if not exists updated_by text,
  add column if not exists updated_at timestamptz not null default now();

update public.inventory_items set created_by = coalesce(created_by, 'system'), updated_by = coalesce(updated_by, created_by, 'system');
update public.inventory_transactions set created_by = coalesce(created_by, recorded_by), updated_by = coalesce(updated_by, recorded_by);

alter table public.inventory_items alter column created_by set not null;
alter table public.inventory_items alter column updated_by set not null;
alter table public.inventory_transactions alter column created_by set not null;
alter table public.inventory_transactions alter column updated_by set not null;

do $$ begin
  if not exists (select 1 from pg_catalog.pg_constraint where conname = 'inventory_transactions_related_loan_fk') then
    alter table public.inventory_transactions
      add constraint inventory_transactions_related_loan_fk
      foreign key (related_loan_id) references public.inventory_transactions(id) on delete restrict;
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint where conname = 'inventory_transactions_related_loan_type_check') then
    alter table public.inventory_transactions
      add constraint inventory_transactions_related_loan_type_check
      check (related_loan_id is null or type in ('Kembali', 'Rusak', 'Hilang'));
  end if;
end $$;

create index if not exists inventory_transactions_related_loan_idx
  on public.inventory_transactions(related_loan_id) where related_loan_id is not null;

create table if not exists public.inventory_audit_logs (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('item', 'transaction', 'photo')),
  entity_id uuid,
  entity_label text not null,
  action text not null check (action in ('create', 'update', 'delete', 'archive', 'restore')),
  changed_by text not null,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);
create index if not exists inventory_audit_logs_created_idx on public.inventory_audit_logs(created_at desc);
create index if not exists inventory_audit_logs_entity_idx on public.inventory_audit_logs(entity_type, entity_id);
alter table public.inventory_audit_logs enable row level security;
revoke all on table public.inventory_audit_logs from anon, authenticated;

create table if not exists public.inventory_item_photos (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.inventory_items(id) on delete cascade,
  data_url text not null,
  caption text,
  recorded_by text not null,
  created_at timestamptz not null default now(),
  constraint inventory_item_photos_image_check check (data_url like 'data:image/%'),
  constraint inventory_item_photos_size_check check (octet_length(data_url) <= 2800000)
);
create index if not exists inventory_item_photos_item_idx on public.inventory_item_photos(item_id, created_at desc);
alter table public.inventory_item_photos enable row level security;
revoke all on table public.inventory_item_photos from anon, authenticated;

create or replace function public.inventory_movement_delta(p_type text, p_quantity numeric, p_related_loan_id uuid)
returns numeric
language sql
immutable
security invoker
set search_path = ''
as $$
  select case
    when p_type in ('Masuk', 'Kembali', 'Penyesuaian') then p_quantity
    when p_type in ('Rusak', 'Hilang') and p_related_loan_id is not null then 0::numeric
    when p_type in ('Keluar', 'Rusak', 'Hilang') then -abs(p_quantity)
    else 0::numeric
  end;
$$;
revoke all on function public.inventory_movement_delta(text, numeric, uuid) from public;

drop function if exists public.secure_get_inventory_items(text);
create function public.secure_get_inventory_items(p_token text)
returns table(
  id uuid, name text, category text, code text, unit text, initial_stock numeric,
  min_stock numeric, condition text, location text, purchase_price numeric,
  purchase_date date, expiry_date date, owner_division text, penanggung_jawab text,
  notes text, is_archived boolean, created_at timestamptz, updated_at timestamptz,
  current_stock numeric, outstanding numeric, last_movement_at timestamptz,
  created_by text, updated_by text
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if public.validate_session_token(p_token) is null then raise exception 'Unauthorized or expired session'; end if;
  return query
  select i.id, i.name, i.category, i.code, i.unit, i.initial_stock, i.min_stock,
    i.condition, i.location, i.purchase_price, i.purchase_date, i.expiry_date,
    i.owner_division, i.penanggung_jawab, i.notes, i.is_archived, i.created_at, i.updated_at,
    i.initial_stock + coalesce(sum(public.inventory_movement_delta(t.type, t.quantity, t.related_loan_id)), 0),
    greatest(0::numeric, coalesce(sum(case when t.type = 'Keluar' and t.is_returnable then t.quantity when t.related_loan_id is not null and t.type in ('Kembali','Rusak','Hilang') then -abs(t.quantity) else 0 end), 0)),
    max(t.transaction_date::timestamptz), i.created_by, i.updated_by
  from public.inventory_items i left join public.inventory_transactions t on t.item_id = i.id
  group by i.id order by i.is_archived, i.category, i.name;
end;
$$;

drop function if exists public.secure_get_inventory_transactions(text);
create function public.secure_get_inventory_transactions(p_token text)
returns table(
  id uuid, item_id uuid, type text, quantity numeric, transaction_date date,
  is_returnable boolean, expected_return_date date, activity_name text, handled_by text,
  recorded_by text, notes text, created_at timestamptz, item_name text,
  item_code text, item_category text, item_unit text, related_loan_id uuid,
  created_by text, updated_by text, updated_at timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if public.validate_session_token(p_token) is null then raise exception 'Unauthorized or expired session'; end if;
  return query
  select t.id, t.item_id, t.type, t.quantity, t.transaction_date, t.is_returnable,
    t.expected_return_date, t.activity_name, t.handled_by, t.recorded_by, t.notes,
    t.created_at, i.name, i.code, i.category, i.unit, t.related_loan_id,
    t.created_by, t.updated_by, t.updated_at
  from public.inventory_transactions t join public.inventory_items i on i.id = t.item_id
  order by t.transaction_date desc, t.created_at desc;
end;
$$;

create or replace function public.secure_save_inventory_item(
  p_token text, p_id uuid, p_name text, p_category text, p_code text, p_unit text,
  p_initial_stock numeric, p_min_stock numeric, p_condition text, p_location text,
  p_purchase_price numeric, p_purchase_date date, p_expiry_date date,
  p_owner_division text, p_penanggung_jawab text, p_notes text, p_is_archived boolean
)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_username text; v_id uuid; v_old public.inventory_items%rowtype; v_new public.inventory_items%rowtype; v_outstanding numeric;
begin
  v_username := public.validate_session_token(p_token); if v_username is null then return null; end if;
  if btrim(coalesce(p_name, '')) = '' then raise exception 'Nama barang wajib diisi'; end if;
  if btrim(coalesce(p_code, '')) = '' then raise exception 'Kode/SKU wajib diisi'; end if;

  if p_id is null then
    insert into public.inventory_items(name, category, code, unit, initial_stock, min_stock, condition, location,
      purchase_price, purchase_date, expiry_date, owner_division, penanggung_jawab, notes, is_archived, created_by, updated_by)
    values (btrim(p_name), p_category, btrim(p_code), coalesce(nullif(btrim(p_unit), ''), 'pcs'), coalesce(p_initial_stock,0),
      coalesce(p_min_stock,0), nullif(btrim(p_condition),''), nullif(btrim(p_location),''), p_purchase_price, p_purchase_date,
      p_expiry_date, nullif(btrim(p_owner_division),''), nullif(btrim(p_penanggung_jawab),''), nullif(btrim(p_notes),''),
      coalesce(p_is_archived,false), v_username, v_username) returning * into v_new;
    v_id := v_new.id;
    insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,new_data)
      values ('item',v_id,v_new.name,'create',v_username,to_jsonb(v_new));
  else
    select * into v_old from public.inventory_items where id = p_id for update;
    if v_old.id is null then raise exception 'Barang tidak ditemukan'; end if;
    if coalesce(p_is_archived,false) and not v_old.is_archived then
      select coalesce(sum(case when t.type='Keluar' and t.is_returnable then t.quantity when t.related_loan_id is not null and t.type in ('Kembali','Rusak','Hilang') then -abs(t.quantity) else 0 end),0)
      into v_outstanding from public.inventory_transactions t where t.item_id=p_id;
      if v_outstanding > 0 then raise exception 'Barang masih dipinjam dan belum dapat diarsipkan'; end if;
    end if;
    update public.inventory_items set name=btrim(p_name), category=p_category, code=btrim(p_code), unit=coalesce(nullif(btrim(p_unit),''),'pcs'),
      initial_stock=coalesce(p_initial_stock,0), min_stock=coalesce(p_min_stock,0), condition=nullif(btrim(p_condition),''),
      location=nullif(btrim(p_location),''), purchase_price=p_purchase_price, purchase_date=p_purchase_date, expiry_date=p_expiry_date,
      owner_division=nullif(btrim(p_owner_division),''), penanggung_jawab=nullif(btrim(p_penanggung_jawab),''), notes=nullif(btrim(p_notes),''),
      is_archived=coalesce(p_is_archived,false), updated_at=now(), updated_by=v_username where id=p_id returning * into v_new;
    v_id := v_new.id;
    insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,old_data,new_data)
      values ('item',v_id,v_new.name,case when not v_old.is_archived and v_new.is_archived then 'archive' when v_old.is_archived and not v_new.is_archived then 'restore' else 'update' end,v_username,to_jsonb(v_old),to_jsonb(v_new));
  end if;
  return v_id;
exception when unique_violation then raise exception 'Kode/SKU "%" sudah dipakai barang lain', btrim(p_code);
end;
$$;

create or replace function public.secure_delete_inventory_item(p_token text, p_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare v_username text; v_old public.inventory_items%rowtype; v_count integer;
begin
  v_username:=public.validate_session_token(p_token); if v_username is null then return false; end if;
  select * into v_old from public.inventory_items where id=p_id for update; if v_old.id is null then return false; end if;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,old_data)
    values ('item',p_id,v_old.name,'delete',v_username,to_jsonb(v_old));
  delete from public.inventory_items where id=p_id; get diagnostics v_count=row_count; return v_count>0;
end;
$$;

drop function if exists public.secure_save_inventory_transaction(text, uuid, uuid, text, numeric, date, boolean, date, text, text, text);
create function public.secure_save_inventory_transaction(
  p_token text, p_id uuid, p_item_id uuid, p_type text, p_quantity numeric,
  p_transaction_date date, p_is_returnable boolean, p_expected_return_date date,
  p_activity_name text, p_handled_by text, p_notes text, p_related_loan_id uuid
)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_username text; v_id uuid; v_initial numeric; v_stock_before numeric; v_stock_after numeric;
  v_existing_item_id uuid; v_returnable boolean:=case when p_type='Keluar' then coalesce(p_is_returnable,false) else false end;
  v_return_date date:=case when p_type='Keluar' and coalesce(p_is_returnable,false) then p_expected_return_date else null end;
  v_loan public.inventory_transactions%rowtype; v_loan_remaining numeric; v_old public.inventory_transactions%rowtype; v_new public.inventory_transactions%rowtype; v_item_name text;
begin
  v_username:=public.validate_session_token(p_token); if v_username is null then return null; end if;
  if p_id is not null then select item_id into v_existing_item_id from public.inventory_transactions where id=p_id;
    if v_existing_item_id is null then raise exception 'Catatan tidak ditemukan'; end if;
    if v_existing_item_id<>p_item_id then raise exception 'Barang pada catatan tidak dapat diganti'; end if;
  end if;
  select initial_stock,name into v_initial,v_item_name from public.inventory_items where id=p_item_id for update;
  if v_initial is null then raise exception 'Barang tidak ditemukan'; end if;
  if p_id is not null then select * into v_old from public.inventory_transactions where id=p_id for update; end if;
  if p_type='Penyesuaian' and coalesce(p_quantity,0)=0 then raise exception 'Nilai koreksi tidak boleh nol'; end if;
  if p_type<>'Penyesuaian' and coalesce(p_quantity,0)<=0 then raise exception 'Jumlah harus lebih dari nol'; end if;
  if p_type='Kembali' and p_related_loan_id is null then raise exception 'Pilih pinjaman yang dikembalikan'; end if;
  if p_related_loan_id is not null then
    select * into v_loan from public.inventory_transactions where id=p_related_loan_id for update;
    if v_loan.id is null or v_loan.type<>'Keluar' or not v_loan.is_returnable or v_loan.item_id<>p_item_id then raise exception 'Pinjaman tidak valid'; end if;
    select v_loan.quantity-coalesce(sum(abs(t.quantity)),0) into v_loan_remaining from public.inventory_transactions t
      where t.related_loan_id=v_loan.id and t.type in ('Kembali','Rusak','Hilang') and (p_id is null or t.id<>p_id);
    if p_quantity>v_loan_remaining then raise exception 'Jumlah kembali melebihi pinjaman: tersisa %',greatest(v_loan_remaining,0); end if;
  end if;
  if p_id is not null and exists(select 1 from public.inventory_transactions where related_loan_id=p_id) then
    select coalesce(sum(abs(t.quantity)),0) into v_loan_remaining from public.inventory_transactions t where t.related_loan_id=p_id;
    if p_type<>'Keluar' or not v_returnable then raise exception 'Pinjaman yang sudah memiliki penyelesaian tidak dapat diubah menjadi jenis lain'; end if;
    if p_quantity<v_loan_remaining then raise exception 'Jumlah pinjaman tidak boleh lebih kecil dari % yang sudah diselesaikan',v_loan_remaining; end if;
  end if;
  select v_initial+coalesce(sum(public.inventory_movement_delta(t.type,t.quantity,t.related_loan_id)),0) into v_stock_before
    from public.inventory_transactions t where t.item_id=p_item_id and (p_id is null or t.id<>p_id);
  v_stock_after:=v_stock_before+public.inventory_movement_delta(p_type,p_quantity,p_related_loan_id);
  if v_stock_after<0 then raise exception 'Stok tidak mencukupi: tersisa %, diminta %',v_stock_before,abs(p_quantity); end if;

  if p_id is null then
    insert into public.inventory_transactions(item_id,type,quantity,transaction_date,is_returnable,expected_return_date,activity_name,handled_by,recorded_by,notes,related_loan_id,created_by,updated_by)
    values(p_item_id,p_type,p_quantity,coalesce(p_transaction_date,current_date),v_returnable,v_return_date,nullif(btrim(p_activity_name),''),nullif(btrim(p_handled_by),''),v_username,nullif(btrim(p_notes),''),p_related_loan_id,v_username,v_username)
    returning * into v_new; v_id:=v_new.id;
    insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,new_data)
      values('transaction',v_id,p_type||' - '||v_item_name,'create',v_username,to_jsonb(v_new));
  else
    update public.inventory_transactions set type=p_type,quantity=p_quantity,transaction_date=coalesce(p_transaction_date,current_date),is_returnable=v_returnable,
      expected_return_date=v_return_date,activity_name=nullif(btrim(p_activity_name),''),handled_by=nullif(btrim(p_handled_by),''),notes=nullif(btrim(p_notes),''),
      related_loan_id=p_related_loan_id,updated_by=v_username,updated_at=now() where id=p_id returning * into v_new; v_id:=v_new.id;
    insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,old_data,new_data)
      values('transaction',v_id,p_type||' - '||v_item_name,'update',v_username,to_jsonb(v_old),to_jsonb(v_new));
  end if;
  return v_id;
end;
$$;

create or replace function public.secure_delete_inventory_transaction(p_token text,p_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_username text; v_old public.inventory_transactions%rowtype; v_initial numeric; v_stock_after numeric; v_count integer; v_item_name text;
begin
  v_username:=public.validate_session_token(p_token); if v_username is null then return false; end if;
  select * into v_old from public.inventory_transactions where id=p_id; if v_old.id is null then return false; end if;
  if exists(select 1 from public.inventory_transactions where related_loan_id=p_id) then raise exception 'Pinjaman tidak dapat dihapus karena sudah memiliki catatan penyelesaian'; end if;
  select initial_stock,name into v_initial,v_item_name from public.inventory_items where id=v_old.item_id for update;
  select v_initial+coalesce(sum(public.inventory_movement_delta(t.type,t.quantity,t.related_loan_id)),0) into v_stock_after
    from public.inventory_transactions t where t.item_id=v_old.item_id and t.id<>p_id;
  if v_stock_after<0 then raise exception 'Catatan tidak dapat dihapus karena akan membuat stok negatif'; end if;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,old_data)
    values('transaction',p_id,v_old.type||' - '||v_item_name,'delete',v_username,to_jsonb(v_old));
  delete from public.inventory_transactions where id=p_id; get diagnostics v_count=row_count; return v_count>0;
end;
$$;

create or replace function public.secure_get_inventory_audit_logs(p_token text)
returns table(id uuid,entity_type text,entity_id uuid,entity_label text,action text,changed_by text,old_data jsonb,new_data jsonb,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$ begin
  if public.validate_session_token(p_token) is null then raise exception 'Unauthorized or expired session'; end if;
  return query select a.id,a.entity_type,a.entity_id,a.entity_label,a.action,a.changed_by,a.old_data,a.new_data,a.created_at from public.inventory_audit_logs a order by a.created_at desc limit 1000;
end $$;

create or replace function public.secure_get_inventory_item_photos(p_token text,p_item_id uuid)
returns table(id uuid,item_id uuid,data_url text,caption text,recorded_by text,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$ begin
  if public.validate_session_token(p_token) is null then raise exception 'Unauthorized or expired session'; end if;
  return query select p.id,p.item_id,p.data_url,p.caption,p.recorded_by,p.created_at from public.inventory_item_photos p where p.item_id=p_item_id order by p.created_at desc;
end $$;

create or replace function public.secure_save_inventory_item_photo(p_token text,p_item_id uuid,p_data_url text,p_caption text)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_username text; v_id uuid; begin
  v_username:=public.validate_session_token(p_token); if v_username is null then return null; end if;
  if not exists(select 1 from public.inventory_items where id=p_item_id) then raise exception 'Barang tidak ditemukan'; end if;
  insert into public.inventory_item_photos(item_id,data_url,caption,recorded_by) values(p_item_id,p_data_url,nullif(btrim(p_caption),''),v_username) returning id into v_id;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,new_data) values('photo',v_id,'Foto kondisi','create',v_username,jsonb_build_object('item_id',p_item_id,'caption',p_caption));
  return v_id;
end $$;

create or replace function public.secure_delete_inventory_item_photo(p_token text,p_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$ declare v_username text; v_row public.inventory_item_photos%rowtype; v_count integer; begin
  v_username:=public.validate_session_token(p_token); if v_username is null then return false; end if;
  select * into v_row from public.inventory_item_photos where id=p_id; if v_row.id is null then return false; end if;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,old_data) values('photo',p_id,'Foto kondisi','delete',v_username,jsonb_build_object('item_id',v_row.item_id,'caption',v_row.caption));
  delete from public.inventory_item_photos where id=p_id; get diagnostics v_count=row_count; return v_count>0;
end $$;

revoke all on function public.secure_get_inventory_items(text) from public;
revoke all on function public.secure_get_inventory_transactions(text) from public;
revoke all on function public.secure_save_inventory_transaction(text,uuid,uuid,text,numeric,date,boolean,date,text,text,text,uuid) from public;
revoke all on function public.secure_get_inventory_audit_logs(text) from public;
revoke all on function public.secure_get_inventory_item_photos(text,uuid) from public;
revoke all on function public.secure_save_inventory_item_photo(text,uuid,text,text) from public;
revoke all on function public.secure_delete_inventory_item_photo(text,uuid) from public;
grant execute on function public.secure_get_inventory_items(text) to anon,authenticated;
grant execute on function public.secure_get_inventory_transactions(text) to anon,authenticated;
grant execute on function public.secure_save_inventory_transaction(text,uuid,uuid,text,numeric,date,boolean,date,text,text,text,uuid) to anon,authenticated;
grant execute on function public.secure_get_inventory_audit_logs(text) to anon,authenticated;
grant execute on function public.secure_get_inventory_item_photos(text,uuid) to anon,authenticated;
grant execute on function public.secure_save_inventory_item_photo(text,uuid,text,text) to anon,authenticated;
grant execute on function public.secure_delete_inventory_item_photo(text,uuid) to anon,authenticated;
notify pgrst,'reload schema';
