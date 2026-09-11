-- 009_user_management_stocktake.sql
-- Lifecycle pengguna lengkap dan stock opname terkontrol.

alter table public.app_users add column if not exists updated_at timestamptz not null default now();

alter table public.inventory_audit_logs drop constraint if exists inventory_audit_logs_entity_type_check;
alter table public.inventory_audit_logs add constraint inventory_audit_logs_entity_type_check
  check(entity_type in ('item','transaction','photo','user','stocktake'));

drop function if exists public.secure_get_app_users(text);
create function public.secure_get_app_users(p_token text)
returns table(id uuid,username text,full_name text,role text,is_active boolean,created_at timestamptz,updated_at timestamptz,active_sessions bigint)
language plpgsql stable security definer set search_path=''
as $$
declare v_role text;
begin
  select u.role into v_role from public.app_sessions s join public.app_users u on u.id=s.user_id
    where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_role is null then raise exception 'Unauthorized or expired session'; end if;
  if v_role<>'admin' then raise exception 'Hanya admin yang dapat mengelola pengguna'; end if;
  return query
    select u.id,u.username,u.full_name,u.role,u.is_active,u.created_at,u.updated_at,
      count(s.token) filter(where s.expires_at>now())
    from public.app_users u left join public.app_sessions s on s.user_id=u.id
    group by u.id order by u.is_active desc,u.full_name nulls last,u.username;
end $$;

create or replace function public.secure_update_app_user(
  p_token text,p_id uuid,p_full_name text,p_role text,p_is_active boolean
)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_actor text; v_actor_role text; v_old public.app_users%rowtype; v_new public.app_users%rowtype;
begin
  select u.username,u.role into v_actor,v_actor_role from public.app_sessions s join public.app_users u on u.id=s.user_id
    where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_actor is null then return false; end if;
  if v_actor_role<>'admin' then raise exception 'Hanya admin yang dapat mengelola pengguna'; end if;
  if coalesce(p_role,'') not in ('admin','member') then raise exception 'Role tidak valid'; end if;
  select * into v_old from public.app_users where id=p_id for update;
  if v_old.id is null then raise exception 'Pengguna tidak ditemukan'; end if;
  if v_old.username=v_actor and (p_role<>v_old.role or coalesce(p_is_active,true)<>v_old.is_active) then
    raise exception 'Role atau status akun sendiri tidak dapat diubah';
  end if;
  if v_old.role='admin' and v_old.is_active and (p_role<>'admin' or not coalesce(p_is_active,false))
     and (select count(*) from public.app_users where role='admin' and is_active=true)<=1 then
    raise exception 'Admin aktif terakhir tidak dapat dinonaktifkan atau dijadikan member';
  end if;
  update public.app_users set full_name=nullif(btrim(p_full_name),''),role=p_role,
    is_active=coalesce(p_is_active,false),updated_at=now() where id=p_id returning * into v_new;
  if not v_new.is_active then delete from public.app_sessions where user_id=p_id; end if;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,old_data,new_data)
  values('user',p_id,v_old.username,'update',v_actor,
    jsonb_build_object('full_name',v_old.full_name,'role',v_old.role,'is_active',v_old.is_active),
    jsonb_build_object('full_name',v_new.full_name,'role',v_new.role,'is_active',v_new.is_active));
  return true;
end $$;

do $migration$
declare v_crypto_schema text;
begin
  select n.nspname into v_crypto_schema from pg_catalog.pg_extension e join pg_catalog.pg_namespace n on n.oid=e.extnamespace where e.extname='pgcrypto';
  if v_crypto_schema is null then raise exception 'Ekstensi pgcrypto belum aktif'; end if;
  execute format($function$
    create or replace function public.secure_reset_app_user_password(p_token text,p_id uuid,p_password text)
    returns boolean language plpgsql security definer set search_path=''
    as $body$
    declare v_actor text; v_actor_role text; v_target text; v_revoked integer;
    begin
      select u.username,u.role into v_actor,v_actor_role from public.app_sessions s join public.app_users u on u.id=s.user_id
        where s.token=p_token and s.expires_at>now() and u.is_active=true;
      if v_actor is null then return false; end if;
      if v_actor_role<>'admin' then raise exception 'Hanya admin yang dapat mereset password'; end if;
      if length(coalesce(p_password,''))<8 then raise exception 'Password minimal 8 karakter'; end if;
      select username into v_target from public.app_users where id=p_id for update;
      if v_target is null then raise exception 'Pengguna tidak ditemukan'; end if;
      update public.app_users set password_hash=%1$I.crypt(p_password,%1$I.gen_salt('bf')),updated_at=now() where id=p_id;
      delete from public.app_sessions where user_id=p_id; get diagnostics v_revoked=row_count;
      insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,new_data)
      values('user',p_id,v_target,'update',v_actor,jsonb_build_object('password_reset',true,'sessions_revoked',v_revoked));
      return true;
    end $body$;
  $function$,v_crypto_schema);
end $migration$;

create or replace function public.secure_revoke_app_user_sessions(p_token text,p_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_actor text; v_actor_role text; v_target text; v_count integer;
begin
  select u.username,u.role into v_actor,v_actor_role from public.app_sessions s join public.app_users u on u.id=s.user_id
    where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_actor is null then return false; end if;
  if v_actor_role<>'admin' then raise exception 'Hanya admin yang dapat mencabut sesi'; end if;
  select username into v_target from public.app_users where id=p_id;
  if v_target is null then raise exception 'Pengguna tidak ditemukan'; end if;
  delete from public.app_sessions where user_id=p_id; get diagnostics v_count=row_count;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,new_data)
  values('user',p_id,v_target,'update',v_actor,jsonb_build_object('sessions_revoked',v_count));
  return true;
end $$;

create table if not exists public.inventory_stocktakes (
  id uuid primary key default gen_random_uuid(),
  title text not null check(btrim(title)<>''),
  notes text,
  status text not null default 'draft' check(status in ('draft','completed','cancelled')),
  created_by text not null,
  completed_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.inventory_stocktake_lines (
  stocktake_id uuid not null references public.inventory_stocktakes(id) on delete cascade,
  item_id uuid not null references public.inventory_items(id) on delete restrict,
  system_stock numeric not null,
  counted_stock numeric check(counted_stock is null or counted_stock>=0),
  counted_by text,
  counted_at timestamptz,
  primary key(stocktake_id,item_id)
);
create index if not exists inventory_stocktakes_status_idx on public.inventory_stocktakes(status,created_at desc);
alter table public.inventory_stocktakes enable row level security;
alter table public.inventory_stocktake_lines enable row level security;
revoke all on table public.inventory_stocktakes,public.inventory_stocktake_lines from anon,authenticated;

create or replace function public.secure_get_inventory_stocktakes(p_token text)
returns table(id uuid,title text,notes text,status text,created_by text,completed_by text,created_at timestamptz,updated_at timestamptz,completed_at timestamptz,total_items bigint,counted_items bigint,variance_items bigint)
language plpgsql stable security definer set search_path=''
as $$ begin
  if public.validate_session_token(p_token) is null then raise exception 'Unauthorized or expired session'; end if;
  return query select s.id,s.title,s.notes,s.status,s.created_by,s.completed_by,s.created_at,s.updated_at,s.completed_at,
    count(l.item_id),count(l.counted_stock),count(*) filter(where l.counted_stock is not null and l.counted_stock<>l.system_stock)
  from public.inventory_stocktakes s left join public.inventory_stocktake_lines l on l.stocktake_id=s.id
  group by s.id order by s.created_at desc;
end $$;

create or replace function public.secure_get_inventory_stocktake_lines(p_token text,p_stocktake_id uuid)
returns table(stocktake_id uuid,item_id uuid,item_name text,item_code text,item_unit text,system_stock numeric,counted_stock numeric,difference numeric,counted_by text,counted_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$ begin
  if public.validate_session_token(p_token) is null then raise exception 'Unauthorized or expired session'; end if;
  return query select l.stocktake_id,l.item_id,i.name,i.code,i.unit,l.system_stock,l.counted_stock,
    case when l.counted_stock is null then null else l.counted_stock-l.system_stock end,l.counted_by,l.counted_at
  from public.inventory_stocktake_lines l join public.inventory_items i on i.id=l.item_id
  where l.stocktake_id=p_stocktake_id order by i.category,i.name;
end $$;

create or replace function public.secure_create_inventory_stocktake(p_token text,p_title text,p_notes text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_actor text; v_role text; v_id uuid; v_count integer;
begin
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
    where not i.is_archived group by i.id;
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Belum ada barang aktif untuk dihitung'; end if;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,new_data)
    values('stocktake',v_id,btrim(p_title),'create',v_actor,jsonb_build_object('status','draft'));
  return v_id;
end $$;

create or replace function public.secure_update_inventory_stocktake_line(p_token text,p_stocktake_id uuid,p_item_id uuid,p_counted_stock numeric)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_actor text; v_status text; v_count integer;
begin
  v_actor:=public.validate_session_token(p_token); if v_actor is null then return false; end if;
  if p_counted_stock is null or p_counted_stock<0 then raise exception 'Stok fisik tidak valid'; end if;
  select status into v_status from public.inventory_stocktakes where id=p_stocktake_id for update;
  if v_status is null then raise exception 'Stock opname tidak ditemukan'; end if;
  if v_status<>'draft' then raise exception 'Stock opname sudah ditutup'; end if;
  update public.inventory_stocktake_lines set counted_stock=p_counted_stock,counted_by=v_actor,counted_at=now()
    where stocktake_id=p_stocktake_id and item_id=p_item_id;
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Barang tidak termasuk stock opname'; end if;
  update public.inventory_stocktakes set updated_at=now() where id=p_stocktake_id;
  return true;
end $$;

create or replace function public.secure_update_inventory_stocktake_lines(p_token text,p_stocktake_id uuid,p_lines jsonb)
returns integer language plpgsql security definer set search_path=''
as $$
declare v_actor text; v_status text; v_line record; v_count integer:=0;
begin
  v_actor:=public.validate_session_token(p_token); if v_actor is null then return null; end if;
  select status into v_status from public.inventory_stocktakes where id=p_stocktake_id for update;
  if v_status is null then raise exception 'Stock opname tidak ditemukan'; end if;
  if v_status<>'draft' then raise exception 'Stock opname sudah ditutup'; end if;
  if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)>1000 then raise exception 'Data hitungan tidak valid'; end if;
  for v_line in select * from jsonb_to_recordset(p_lines) as x(item_id uuid,counted_stock numeric) loop
    if v_line.counted_stock is null or v_line.counted_stock<0 then raise exception 'Stok fisik tidak valid'; end if;
    update public.inventory_stocktake_lines set counted_stock=v_line.counted_stock,counted_by=v_actor,counted_at=now()
      where stocktake_id=p_stocktake_id and item_id=v_line.item_id;
    if not found then raise exception 'Barang tidak termasuk stock opname'; end if;
    v_count:=v_count+1;
  end loop;
  update public.inventory_stocktakes set updated_at=now() where id=p_stocktake_id;
  return v_count;
end $$;

create or replace function public.secure_complete_inventory_stocktake(p_token text,p_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_actor text; v_role text; v_take public.inventory_stocktakes%rowtype; v_line record; v_live numeric; v_diff numeric; v_tx uuid; v_variances integer:=0;
begin
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
      from public.inventory_transactions t where t.item_id=v_line.item_id;
    v_diff:=v_line.counted_stock-v_live;
    update public.inventory_stocktake_lines set system_stock=v_live where stocktake_id=p_id and item_id=v_line.item_id;
    if v_diff<>0 then
      insert into public.inventory_transactions(item_id,type,quantity,transaction_date,is_returnable,activity_name,handled_by,recorded_by,notes,created_by,updated_by)
      values(v_line.item_id,'Penyesuaian',v_diff,current_date,false,'Stock opname: '||v_take.title,v_actor,v_actor,'Selisih stock opname',v_actor,v_actor)
      returning id into v_tx;
      insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,new_data)
      values('transaction',v_tx,'Penyesuaian - '||v_line.name,'create',v_actor,jsonb_build_object('stocktake_id',p_id,'system_stock',v_live,'counted_stock',v_line.counted_stock,'difference',v_diff));
      v_variances:=v_variances+1;
    end if;
  end loop;
  update public.inventory_stocktakes set status='completed',completed_by=v_actor,completed_at=now(),updated_at=now() where id=p_id;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,old_data,new_data)
    values('stocktake',p_id,v_take.title,'update',v_actor,jsonb_build_object('status','draft'),jsonb_build_object('status','completed','variance_items',v_variances));
  return true;
end $$;

create or replace function public.secure_cancel_inventory_stocktake(p_token text,p_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_actor text; v_role text; v_title text; v_count integer;
begin
  select u.username,u.role into v_actor,v_role from public.app_sessions s join public.app_users u on u.id=s.user_id
    where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_actor is null then return false; end if;
  if v_role<>'admin' then raise exception 'Hanya admin yang dapat membatalkan stock opname'; end if;
  select title into v_title from public.inventory_stocktakes where id=p_id and status='draft' for update;
  if v_title is null then raise exception 'Stock opname aktif tidak ditemukan'; end if;
  update public.inventory_stocktakes set status='cancelled',updated_at=now() where id=p_id; get diagnostics v_count=row_count;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,old_data,new_data)
    values('stocktake',p_id,v_title,'update',v_actor,jsonb_build_object('status','draft'),jsonb_build_object('status','cancelled'));
  return v_count>0;
end $$;

create or replace function public.secure_delete_inventory_stocktake(p_token text,p_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_actor text; v_role text; v_take public.inventory_stocktakes%rowtype; v_count integer;
begin
  select u.username,u.role into v_actor,v_role from public.app_sessions s join public.app_users u on u.id=s.user_id
    where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_actor is null then return false; end if;
  if v_role<>'admin' then raise exception 'Hanya admin yang dapat menghapus stock opname'; end if;
  select * into v_take from public.inventory_stocktakes where id=p_id for update;
  if v_take.id is null then return false; end if;
  if v_take.status='completed' then raise exception 'Stock opname selesai tidak dapat dihapus'; end if;
  insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,old_data)
    values('stocktake',p_id,v_take.title,'delete',v_actor,jsonb_build_object('status',v_take.status));
  delete from public.inventory_stocktakes where id=p_id; get diagnostics v_count=row_count;
  return v_count>0;
end $$;

revoke all on function public.secure_get_app_users(text) from public;
revoke all on function public.secure_update_app_user(text,uuid,text,text,boolean) from public;
revoke all on function public.secure_reset_app_user_password(text,uuid,text) from public;
revoke all on function public.secure_revoke_app_user_sessions(text,uuid) from public;
revoke all on function public.secure_get_inventory_stocktakes(text) from public;
revoke all on function public.secure_get_inventory_stocktake_lines(text,uuid) from public;
revoke all on function public.secure_create_inventory_stocktake(text,text,text) from public;
revoke all on function public.secure_update_inventory_stocktake_line(text,uuid,uuid,numeric) from public;
revoke all on function public.secure_update_inventory_stocktake_lines(text,uuid,jsonb) from public;
revoke all on function public.secure_complete_inventory_stocktake(text,uuid) from public;
revoke all on function public.secure_cancel_inventory_stocktake(text,uuid) from public;
revoke all on function public.secure_delete_inventory_stocktake(text,uuid) from public;
grant execute on function public.secure_get_app_users(text) to anon,authenticated;
grant execute on function public.secure_update_app_user(text,uuid,text,text,boolean) to anon,authenticated;
grant execute on function public.secure_reset_app_user_password(text,uuid,text) to anon,authenticated;
grant execute on function public.secure_revoke_app_user_sessions(text,uuid) to anon,authenticated;
grant execute on function public.secure_get_inventory_stocktakes(text) to anon,authenticated;
grant execute on function public.secure_get_inventory_stocktake_lines(text,uuid) to anon,authenticated;
grant execute on function public.secure_create_inventory_stocktake(text,text,text) to anon,authenticated;
grant execute on function public.secure_update_inventory_stocktake_line(text,uuid,uuid,numeric) to anon,authenticated;
grant execute on function public.secure_update_inventory_stocktake_lines(text,uuid,jsonb) to anon,authenticated;
grant execute on function public.secure_complete_inventory_stocktake(text,uuid) to anon,authenticated;
grant execute on function public.secure_cancel_inventory_stocktake(text,uuid) to anon,authenticated;
grant execute on function public.secure_delete_inventory_stocktake(text,uuid) to anon,authenticated;
notify pgrst,'reload schema';
