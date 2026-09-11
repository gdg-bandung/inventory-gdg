-- 003_inventory_rpc.sql
-- Semua akses data inventaris dilakukan melalui function SECURITY DEFINER ini.

create or replace function public.secure_get_inventory_items(p_token text)
returns table(
  id uuid, name text, category text, code text, unit text, initial_stock numeric,
  min_stock numeric, condition text, location text, purchase_price numeric,
  purchase_date date, expiry_date date, owner_division text, penanggung_jawab text,
  notes text, is_archived boolean, created_at timestamptz, updated_at timestamptz,
  current_stock numeric, outstanding numeric, last_movement_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.validate_session_token(p_token) is null then
    raise exception 'Unauthorized or expired session';
  end if;

  return query
  select i.id, i.name, i.category, i.code, i.unit, i.initial_stock, i.min_stock,
    i.condition, i.location, i.purchase_price, i.purchase_date, i.expiry_date,
    i.owner_division, i.penanggung_jawab, i.notes, i.is_archived, i.created_at, i.updated_at,
    i.initial_stock + coalesce(sum(public.inventory_movement_delta(t.type, t.quantity)), 0) as current_stock,
    greatest(0::numeric, coalesce(sum(case
      when t.type = 'Keluar' and t.is_returnable then t.quantity
      when t.type in ('Kembali', 'Rusak', 'Hilang') then -abs(t.quantity)
      else 0 end), 0)) as outstanding,
    max(t.transaction_date::timestamptz) as last_movement_at
  from public.inventory_items i
  left join public.inventory_transactions t on t.item_id = i.id
  group by i.id
  order by i.is_archived, i.category, i.name;
end;
$$;

create or replace function public.secure_get_inventory_transactions(p_token text)
returns table(
  id uuid, item_id uuid, type text, quantity numeric, transaction_date date,
  is_returnable boolean, expected_return_date date, activity_name text, handled_by text,
  recorded_by text, notes text, created_at timestamptz, item_name text,
  item_code text, item_category text, item_unit text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.validate_session_token(p_token) is null then
    raise exception 'Unauthorized or expired session';
  end if;

  return query
  select t.id, t.item_id, t.type, t.quantity, t.transaction_date, t.is_returnable,
    t.expected_return_date, t.activity_name, t.handled_by, t.recorded_by, t.notes,
    t.created_at, i.name, i.code, i.category, i.unit
  from public.inventory_transactions t
  join public.inventory_items i on i.id = t.item_id
  order by t.transaction_date desc, t.created_at desc;
end;
$$;

create or replace function public.secure_save_inventory_item(
  p_token text, p_id uuid, p_name text, p_category text, p_code text, p_unit text,
  p_initial_stock numeric, p_min_stock numeric, p_condition text, p_location text,
  p_purchase_price numeric, p_purchase_date date, p_expiry_date date,
  p_owner_division text, p_penanggung_jawab text, p_notes text, p_is_archived boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if public.validate_session_token(p_token) is null then return null; end if;
  if btrim(coalesce(p_name, '')) = '' then raise exception 'Nama barang wajib diisi'; end if;
  if btrim(coalesce(p_code, '')) = '' then raise exception 'Kode/SKU wajib diisi'; end if;

  if p_id is null then
    insert into public.inventory_items(name, category, code, unit, initial_stock, min_stock,
      condition, location, purchase_price, purchase_date, expiry_date, owner_division,
      penanggung_jawab, notes, is_archived)
    values (btrim(p_name), p_category, btrim(p_code), coalesce(nullif(btrim(p_unit), ''), 'pcs'),
      coalesce(p_initial_stock, 0), coalesce(p_min_stock, 0), nullif(btrim(p_condition), ''),
      nullif(btrim(p_location), ''), p_purchase_price, p_purchase_date, p_expiry_date,
      nullif(btrim(p_owner_division), ''), nullif(btrim(p_penanggung_jawab), ''),
      nullif(btrim(p_notes), ''), coalesce(p_is_archived, false))
    returning id into v_id;
  else
    update public.inventory_items set name = btrim(p_name), category = p_category,
      code = btrim(p_code), unit = coalesce(nullif(btrim(p_unit), ''), 'pcs'),
      initial_stock = coalesce(p_initial_stock, 0), min_stock = coalesce(p_min_stock, 0),
      condition = nullif(btrim(p_condition), ''), location = nullif(btrim(p_location), ''),
      purchase_price = p_purchase_price, purchase_date = p_purchase_date, expiry_date = p_expiry_date,
      owner_division = nullif(btrim(p_owner_division), ''),
      penanggung_jawab = nullif(btrim(p_penanggung_jawab), ''), notes = nullif(btrim(p_notes), ''),
      is_archived = coalesce(p_is_archived, false), updated_at = now()
    where id = p_id
    returning id into v_id;
    if v_id is null then raise exception 'Barang tidak ditemukan'; end if;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'Kode/SKU "%" sudah dipakai barang lain', btrim(p_code);
end;
$$;

create or replace function public.secure_delete_inventory_item(p_token text, p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_count integer;
begin
  if public.validate_session_token(p_token) is null then return false; end if;
  delete from public.inventory_items where id = p_id;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

create or replace function public.secure_save_inventory_transaction(
  p_token text, p_id uuid, p_item_id uuid, p_type text, p_quantity numeric,
  p_transaction_date date, p_is_returnable boolean, p_expected_return_date date,
  p_activity_name text, p_handled_by text, p_notes text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_username text;
  v_id uuid;
  v_existing_item_id uuid;
  v_initial numeric;
  v_stock_before numeric;
  v_stock_after numeric;
  v_outstanding_before numeric;
  v_outstanding_after numeric;
  v_returnable boolean := case when p_type = 'Keluar' then coalesce(p_is_returnable, false) else false end;
  v_return_date date := case when p_type = 'Keluar' and coalesce(p_is_returnable, false) then p_expected_return_date else null end;
begin
  v_username := public.validate_session_token(p_token);
  if v_username is null then return null; end if;

  if p_id is not null then
    select item_id into v_existing_item_id
    from public.inventory_transactions
    where id = p_id;
    if v_existing_item_id is null then raise exception 'Catatan tidak ditemukan'; end if;
    if v_existing_item_id <> p_item_id then raise exception 'Barang pada catatan tidak dapat diganti'; end if;
  end if;

  -- Serialisasi perubahan per barang agar dua tab tidak bisa melewati guard stok.
  select initial_stock into v_initial from public.inventory_items where id = p_item_id for update;
  if v_initial is null then raise exception 'Barang tidak ditemukan'; end if;

  if p_type = 'Penyesuaian' and coalesce(p_quantity, 0) = 0 then raise exception 'Nilai koreksi tidak boleh nol'; end if;
  if p_type <> 'Penyesuaian' and coalesce(p_quantity, 0) <= 0 then raise exception 'Jumlah harus lebih dari nol'; end if;

  select v_initial + coalesce(sum(public.inventory_movement_delta(t.type, t.quantity)), 0),
    coalesce(sum(case when t.type = 'Keluar' and t.is_returnable then t.quantity when t.type in ('Kembali','Rusak','Hilang') then -abs(t.quantity) else 0 end), 0)
  into v_stock_before, v_outstanding_before
  from public.inventory_transactions t
  where t.item_id = p_item_id and (p_id is null or t.id <> p_id);

  v_stock_after := v_stock_before + public.inventory_movement_delta(p_type, p_quantity);
  v_outstanding_after := v_outstanding_before + case
    when p_type = 'Keluar' and v_returnable then p_quantity
    when p_type in ('Kembali','Rusak','Hilang') then -abs(p_quantity)
    else 0 end;

  if v_stock_after < 0 then
    raise exception 'Stok tidak mencukupi: tersisa %, diminta %', v_stock_before, abs(p_quantity);
  end if;
  if v_outstanding_after < 0 then
    raise exception 'Jumlah kembali melebihi yang sedang dipinjam: tersisa %', greatest(v_outstanding_before, 0);
  end if;

  if p_id is null then
    insert into public.inventory_transactions(item_id, type, quantity, transaction_date,
      is_returnable, expected_return_date, activity_name, handled_by, recorded_by, notes)
    values (p_item_id, p_type, p_quantity, coalesce(p_transaction_date, current_date),
      v_returnable, v_return_date, nullif(btrim(p_activity_name), ''),
      nullif(btrim(p_handled_by), ''), v_username, nullif(btrim(p_notes), ''))
    returning id into v_id;
  else
    update public.inventory_transactions set item_id = p_item_id, type = p_type,
      quantity = p_quantity, transaction_date = coalesce(p_transaction_date, current_date),
      is_returnable = v_returnable, expected_return_date = v_return_date,
      activity_name = nullif(btrim(p_activity_name), ''), handled_by = nullif(btrim(p_handled_by), ''),
      recorded_by = v_username, notes = nullif(btrim(p_notes), '')
    where id = p_id returning id into v_id;
    if v_id is null then raise exception 'Catatan tidak ditemukan'; end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.secure_delete_inventory_transaction(p_token text, p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
  v_item_id uuid;
  v_initial numeric;
  v_stock_after numeric;
  v_outstanding_after numeric;
begin
  if public.validate_session_token(p_token) is null then return false; end if;

  select item_id into v_item_id from public.inventory_transactions where id = p_id;
  if v_item_id is null then return false; end if;
  select initial_stock into v_initial from public.inventory_items where id = v_item_id for update;

  select v_initial + coalesce(sum(public.inventory_movement_delta(t.type, t.quantity)), 0),
    coalesce(sum(case when t.type = 'Keluar' and t.is_returnable then t.quantity when t.type in ('Kembali','Rusak','Hilang') then -abs(t.quantity) else 0 end), 0)
  into v_stock_after, v_outstanding_after
  from public.inventory_transactions t
  where t.item_id = v_item_id and t.id <> p_id;

  if v_stock_after < 0 then
    raise exception 'Catatan tidak dapat dihapus karena akan membuat stok negatif';
  end if;
  if v_outstanding_after < 0 then
    raise exception 'Catatan tidak dapat dihapus karena urutan pinjaman menjadi tidak valid';
  end if;

  delete from public.inventory_transactions where id = p_id;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

revoke all on function public.secure_get_inventory_items(text) from public;
revoke all on function public.secure_get_inventory_transactions(text) from public;
revoke all on function public.secure_save_inventory_item(text, uuid, text, text, text, text, numeric, numeric, text, text, numeric, date, date, text, text, text, boolean) from public;
revoke all on function public.secure_delete_inventory_item(text, uuid) from public;
revoke all on function public.secure_save_inventory_transaction(text, uuid, uuid, text, numeric, date, boolean, date, text, text, text) from public;
revoke all on function public.secure_delete_inventory_transaction(text, uuid) from public;

grant execute on function public.secure_get_inventory_items(text) to anon, authenticated;
grant execute on function public.secure_get_inventory_transactions(text) to anon, authenticated;
grant execute on function public.secure_save_inventory_item(text, uuid, text, text, text, text, numeric, numeric, text, text, numeric, date, date, text, text, text, boolean) to anon, authenticated;
grant execute on function public.secure_delete_inventory_item(text, uuid) to anon, authenticated;
grant execute on function public.secure_save_inventory_transaction(text, uuid, uuid, text, numeric, date, boolean, date, text, text, text) to anon, authenticated;
grant execute on function public.secure_delete_inventory_transaction(text, uuid) to anon, authenticated;
