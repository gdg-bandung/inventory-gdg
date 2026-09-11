-- 005_fix_pgcrypto_schema.sql
-- Memperbaiki secure_login pada project Supabase yang menempatkan pgcrypto
-- di schema "extensions" (atau schema lain), bukan "public".

do $migration$
declare
  v_crypto_schema text;
begin
  select n.nspname
  into v_crypto_schema
  from pg_catalog.pg_extension e
  join pg_catalog.pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if v_crypto_schema is null then
    raise exception 'Ekstensi pgcrypto belum aktif';
  end if;

  execute format($function$
    create or replace function public.secure_login(p_username text, p_password text)
    returns table(token text, username text, full_name text, expires_at timestamptz)
    language plpgsql
    security definer
    set search_path = ''
    as $body$
    declare
      v_user public.app_users%%rowtype;
      v_token text;
      v_expires timestamptz := now() + interval '7 days';
    begin
      perform public.secure_purge_expired_sessions();

      select u.* into v_user
      from public.app_users u
      where lower(u.username) = lower(btrim(p_username))
        and u.is_active = true
        and u.password_hash = %1$I.crypt(p_password, u.password_hash)
      limit 1;

      if v_user.id is null then
        return;
      end if;

      v_token := translate(encode(%1$I.gen_random_bytes(32), 'base64'), '+/=', '-_');
      insert into public.app_sessions(token, user_id, expires_at)
      values (v_token, v_user.id, v_expires);

      return query select v_token, v_user.username, v_user.full_name, v_expires;
    end;
    $body$;
  $function$, v_crypto_schema);
end;
$migration$;

revoke all on function public.secure_login(text, text) from public;
grant execute on function public.secure_login(text, text) to anon, authenticated;

notify pgrst, 'reload schema';
