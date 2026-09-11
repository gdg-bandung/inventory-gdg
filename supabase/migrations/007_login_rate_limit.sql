-- 007_login_rate_limit.sql
-- Maksimum 5 kegagalan per username dalam jendela 15 menit.

create table if not exists public.app_login_attempts(
  username_key text primary key,
  failed_count integer not null default 0,
  first_failed_at timestamptz not null default now(),
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.app_login_attempts enable row level security;
revoke all on table public.app_login_attempts from anon,authenticated;

do $migration$
declare v_crypto_schema text;
begin
  select n.nspname into v_crypto_schema from pg_catalog.pg_extension e join pg_catalog.pg_namespace n on n.oid=e.extnamespace where e.extname='pgcrypto';
  if v_crypto_schema is null then raise exception 'Ekstensi pgcrypto belum aktif'; end if;
  execute format($function$
    create or replace function public.secure_login(p_username text,p_password text)
    returns table(token text,username text,full_name text,expires_at timestamptz)
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
      return query select v_token,v_user.username,v_user.full_name,v_expires;
    end $body$;
  $function$,v_crypto_schema);
end $migration$;
revoke all on function public.secure_login(text,text) from public;
grant execute on function public.secure_login(text,text) to anon,authenticated;
notify pgrst,'reload schema';
