-- 001_auth.sql
-- Jalankan sekali melalui SQL Editor Supabase.

create extension if not exists pgcrypto with schema public;

create table if not exists public.app_users (
  id uuid primary key default gen_random_uuid(),
  username text not null,
  password_hash text not null,
  full_name text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint app_users_username_not_blank check (btrim(username) <> '')
);

create unique index if not exists app_users_username_lower_uidx
  on public.app_users (lower(username));

create table if not exists public.app_sessions (
  token text primary key,
  user_id uuid not null references public.app_users(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists app_sessions_expires_at_idx on public.app_sessions(expires_at);
create index if not exists app_sessions_user_id_idx on public.app_sessions(user_id);

alter table public.app_users enable row level security;
alter table public.app_sessions enable row level security;

revoke all on table public.app_users, public.app_sessions from anon, authenticated;

create or replace function public.secure_purge_expired_sessions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from public.app_sessions where expires_at <= now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.validate_session_token(p_token text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select u.username
  from public.app_sessions s
  join public.app_users u on u.id = s.user_id
  where s.token = p_token
    and s.expires_at > now()
    and u.is_active = true
  limit 1;
$$;

create or replace function public.secure_login(p_username text, p_password text)
returns table(token text, username text, full_name text, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user public.app_users%rowtype;
  v_token text;
  v_expires timestamptz := now() + interval '7 days';
begin
  perform public.secure_purge_expired_sessions();

  select u.* into v_user
  from public.app_users u
  where lower(u.username) = lower(btrim(p_username))
    and u.is_active = true
    and u.password_hash = public.crypt(p_password, u.password_hash)
  limit 1;

  if v_user.id is null then
    return;
  end if;

  v_token := translate(encode(public.gen_random_bytes(32), 'base64'), '+/=', '-_');
  insert into public.app_sessions(token, user_id, expires_at)
  values (v_token, v_user.id, v_expires);

  return query select v_token, v_user.username, v_user.full_name, v_expires;
end;
$$;

create or replace function public.secure_logout(p_token text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from public.app_sessions where token = p_token;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

create or replace function public.secure_me(p_token text)
returns table(username text, full_name text, expires_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select u.username, u.full_name, s.expires_at
  from public.app_sessions s
  join public.app_users u on u.id = s.user_id
  where s.token = p_token
    and s.expires_at > now()
    and u.is_active = true
  limit 1;
$$;

revoke all on function public.secure_purge_expired_sessions() from public;
revoke all on function public.validate_session_token(text) from public;
revoke all on function public.secure_login(text, text) from public;
revoke all on function public.secure_logout(text) from public;
revoke all on function public.secure_me(text) from public;

grant execute on function public.secure_login(text, text) to anon, authenticated;
grant execute on function public.secure_logout(text) to anon, authenticated;
grant execute on function public.secure_me(text) to anon, authenticated;

-- Hanya dipakai antar-function, tidak diekspos ke anon/authenticated.
-- secure_purge_expired_sessions tetap bisa dipanggil manual oleh postgres/dashboard.



-- u1mfsrm7nPHdh2QI