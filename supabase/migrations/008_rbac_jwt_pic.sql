-- 008_rbac_jwt_pic.sql
-- RBAC sederhana: admin dapat mengelola akun; member tetap punya akses inventaris.
-- PIC transaksi baru selalu username pemilik sesi, bukan input bebas.

alter table public.app_users add column if not exists role text not null default 'member';
do $$ begin
  if not exists(select 1 from pg_catalog.pg_constraint where conname='app_users_role_check') then
    alter table public.app_users add constraint app_users_role_check check(role in ('admin','member'));
  end if;
end $$;

-- Bootstrap aman: jika belum ada admin, akun tertua dijadikan admin.
update public.app_users set role='admin'
where id=(select id from public.app_users where is_active order by created_at,id limit 1)
  and not exists(select 1 from public.app_users where role='admin');

-- Mencegah instalasi baru terkunci bila migration dijalankan sebelum akun awal dibuat.
create or replace function public.app_users_ensure_first_admin()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if not exists(select 1 from public.app_users where role='admin' and is_active=true) then
    new.role := 'admin';
  end if;
  return new;
end $$;
drop trigger if exists app_users_ensure_first_admin on public.app_users;
create trigger app_users_ensure_first_admin before insert on public.app_users
for each row execute function public.app_users_ensure_first_admin();

alter table public.inventory_audit_logs drop constraint if exists inventory_audit_logs_entity_type_check;
alter table public.inventory_audit_logs add constraint inventory_audit_logs_entity_type_check
  check(entity_type in ('item','transaction','photo','user'));

drop function if exists public.secure_me(text);
create function public.secure_me(p_token text)
returns table(username text,full_name text,role text,expires_at timestamptz)
language sql stable security definer set search_path=''
as $$
  select u.username,u.full_name,u.role,s.expires_at
  from public.app_sessions s join public.app_users u on u.id=s.user_id
  where s.token=p_token and s.expires_at>now() and u.is_active=true limit 1;
$$;
revoke all on function public.secure_me(text) from public;
grant execute on function public.secure_me(text) to anon,authenticated;

drop function if exists public.secure_login(text,text);
do $migration$
declare v_crypto_schema text;
begin
  select n.nspname into v_crypto_schema from pg_catalog.pg_extension e join pg_catalog.pg_namespace n on n.oid=e.extnamespace where e.extname='pgcrypto';
  if v_crypto_schema is null then raise exception 'Ekstensi pgcrypto belum aktif'; end if;
  execute format($function$
    create function public.secure_login(p_username text,p_password text)
    returns table(token text,username text,full_name text,role text,expires_at timestamptz)
    language plpgsql security definer set search_path=''
    as $body$
    declare v_user public.app_users%%rowtype; v_token text; v_expires timestamptz:=now()+interval '7 days'; v_key text:=lower(btrim(coalesce(p_username,''))); v_attempt public.app_login_attempts%%rowtype;
    begin
      perform public.secure_purge_expired_sessions();
      delete from public.app_login_attempts where updated_at<now()-interval '1 day';
      select * into v_attempt from public.app_login_attempts where username_key=v_key for update;
      if v_attempt.locked_until is not null and v_attempt.locked_until>now() then return; end if;
      select u.* into v_user from public.app_users u where lower(u.username)=v_key and u.is_active=true and u.password_hash=%1$I.crypt(p_password,u.password_hash) limit 1;
      if v_user.id is null then
        insert into public.app_login_attempts(username_key,failed_count,first_failed_at,locked_until,updated_at)
        values(v_key,1,now(),null,now()) on conflict(username_key) do update set
          failed_count=case when public.app_login_attempts.first_failed_at<now()-interval '15 minutes' then 1 else public.app_login_attempts.failed_count+1 end,
          first_failed_at=case when public.app_login_attempts.first_failed_at<now()-interval '15 minutes' then now() else public.app_login_attempts.first_failed_at end,
          locked_until=case when (case when public.app_login_attempts.first_failed_at<now()-interval '15 minutes' then 1 else public.app_login_attempts.failed_count+1 end)>=5 then now()+interval '15 minutes' else null end,
          updated_at=now();
        return;
      end if;
      delete from public.app_login_attempts where username_key=v_key;
      v_token:=translate(encode(%1$I.gen_random_bytes(32),'base64'),'+/=','-_');
      insert into public.app_sessions(token,user_id,expires_at) values(v_token,v_user.id,v_expires);
      return query select v_token,v_user.username,v_user.full_name,v_user.role,v_expires;
    end $body$;
  $function$,v_crypto_schema);
end $migration$;
revoke all on function public.secure_login(text,text) from public;
grant execute on function public.secure_login(text,text) to anon,authenticated;

create or replace function public.secure_get_app_users(p_token text)
returns table(id uuid,username text,full_name text,role text,is_active boolean,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
declare v_role text;
begin
  select u.role into v_role from public.app_sessions s join public.app_users u on u.id=s.user_id
    where s.token=p_token and s.expires_at>now() and u.is_active=true;
  if v_role is null then raise exception 'Unauthorized or expired session'; end if;
  if v_role<>'admin' then raise exception 'Hanya admin yang dapat mengelola pengguna'; end if;
  return query select u.id,u.username,u.full_name,u.role,u.is_active,u.created_at from public.app_users u order by u.is_active desc,u.full_name nulls last,u.username;
end $$;

do $migration$
declare v_crypto_schema text;
begin
  select n.nspname into v_crypto_schema from pg_catalog.pg_extension e join pg_catalog.pg_namespace n on n.oid=e.extnamespace where e.extname='pgcrypto';
  execute format($function$
    create or replace function public.secure_create_app_user(p_token text,p_username text,p_password text,p_full_name text,p_role text)
    returns uuid language plpgsql security definer set search_path=''
    as $body$
    declare v_admin text; v_admin_role text; v_id uuid;
    begin
      select u.username,u.role into v_admin,v_admin_role from public.app_sessions s join public.app_users u on u.id=s.user_id
        where s.token=p_token and s.expires_at>now() and u.is_active=true;
      if v_admin is null then return null; end if;
      if v_admin_role<>'admin' then raise exception 'Hanya admin yang dapat membuat pengguna'; end if;
      if btrim(coalesce(p_username,''))='' then raise exception 'Username wajib diisi'; end if;
      if length(coalesce(p_password,''))<8 then raise exception 'Password minimal 8 karakter'; end if;
      if coalesce(p_role,'') not in ('admin','member') then raise exception 'Role tidak valid'; end if;
      insert into public.app_users(username,password_hash,full_name,role)
      values(btrim(p_username),%1$I.crypt(p_password,%1$I.gen_salt('bf')),nullif(btrim(p_full_name),''),p_role) returning id into v_id;
      insert into public.inventory_audit_logs(entity_type,entity_id,entity_label,action,changed_by,new_data)
      values('user',v_id,btrim(p_username),'create',v_admin,jsonb_build_object('username',btrim(p_username),'full_name',p_full_name,'role',p_role));
      return v_id;
    exception when unique_violation then raise exception 'Username sudah dipakai';
    end $body$;
  $function$,v_crypto_schema);
end $migration$;

create or replace function public.enforce_inventory_pic()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if tg_op='INSERT' then new.handled_by:=new.recorded_by;
  else new.handled_by:=coalesce(old.handled_by,old.recorded_by); end if;
  return new;
end $$;
drop trigger if exists inventory_transactions_enforce_pic on public.inventory_transactions;
create trigger inventory_transactions_enforce_pic before insert or update on public.inventory_transactions
for each row execute function public.enforce_inventory_pic();

revoke all on function public.secure_get_app_users(text) from public;
revoke all on function public.secure_create_app_user(text,text,text,text,text) from public;
revoke all on function public.app_users_ensure_first_admin() from public;
revoke all on function public.enforce_inventory_pic() from public;
grant execute on function public.secure_get_app_users(text) to anon,authenticated;
grant execute on function public.secure_create_app_user(text,text,text,text,text) to anon,authenticated;
notify pgrst,'reload schema';
