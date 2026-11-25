-- AMID Offgrid: username accounts; no real email address is collected.
-- Applied as an auditable remote migration. No credentials belong in this file.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to service_role, authenticated;

create table public.offgrid_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 username text not null unique check (username ~ '^[a-z0-9_]{3,32}$'),
 display_name text not null default '' check (char_length(display_name) <= 80),
 created_at timestamptz not null default now()
);
alter table public.offgrid_profiles enable row level security;
revoke all on public.offgrid_profiles from anon, authenticated;
grant select, update(display_name) on public.offgrid_profiles to authenticated;
grant all on public.offgrid_profiles to service_role;

create table private.signup_tickets (
 email text primary key, nonce_hash text not null, expires_at timestamptz not null
);
create table private.auth_limits (
 bucket text primary key check (length(bucket) <= 160),
 hits integer not null, expires_at timestamptz not null
);
create table private.auth_proofs (
 proof_hash text primary key, expires_at timestamptz not null
);
create table private.recovery_codes (
 user_id uuid not null references auth.users(id) on delete cascade,
 code_hash text primary key, created_at timestamptz not null default now()
);
alter table private.signup_tickets enable row level security;
alter table private.auth_limits enable row level security;
alter table private.auth_proofs enable row level security;
alter table private.recovery_codes enable row level security;
grant all on all tables in schema private to service_role;

-- A random, short-lived server ticket is required even if someone calls
-- Supabase /signup directly. User-editable metadata never grants permissions.
create function private.guard_offgrid_signup() returns trigger
 language plpgsql security definer set search_path = '' as $$
begin
 delete from private.signup_tickets
 where email = new.email and expires_at > now()
   and nonce_hash = encode(extensions.digest(
     convert_to(coalesce(new.raw_user_meta_data->>'registration_nonce',''), 'UTF8'), 'sha256'), 'hex');
 if not found then raise exception 'Registration requires the AMID account service'; end if;
 new.raw_user_meta_data = coalesce(new.raw_user_meta_data,'{}'::jsonb) - 'registration_nonce';
 return new;
end $$;
revoke all on function private.guard_offgrid_signup() from public, anon, authenticated;
create trigger offgrid_signup_guard before insert on auth.users
 for each row execute function private.guard_offgrid_signup();

create function public.offgrid_auth_limit(p_bucket text, p_limit integer, p_seconds integer)
 returns boolean language plpgsql security invoker set search_path = '' as $$
declare n integer;
begin
 if length(p_bucket)>160 or p_limit not between 1 and 10000 or p_seconds not between 1 and 86400
 then raise exception 'Invalid limiter parameters'; end if;
 delete from private.auth_limits where expires_at < now();
 delete from private.auth_proofs where expires_at < now();
 delete from private.signup_tickets where expires_at < now();
 insert into private.auth_limits(bucket,hits,expires_at)
 values(p_bucket,1,now()+make_interval(secs=>p_seconds))
 on conflict(bucket) do update set
 hits=case when private.auth_limits.expires_at <= now() then 1 else private.auth_limits.hits+1 end,
 expires_at=case when private.auth_limits.expires_at <= now() then excluded.expires_at else private.auth_limits.expires_at end
 returning hits into n;
 return n <= p_limit;
end $$;
revoke all on function public.offgrid_auth_limit(text,integer,integer) from public, anon, authenticated;
grant execute on function public.offgrid_auth_limit(text,integer,integer) to service_role;

create function public.offgrid_auth_prepare(p_email text,p_nonce_hash text)
 returns void language sql security invoker set search_path = '' as $$
 insert into private.signup_tickets(email,nonce_hash,expires_at)
 values(p_email,p_nonce_hash,now()+interval '2 minutes');
$$;
create function public.offgrid_auth_consume_proof(p_hash text)
 returns boolean language plpgsql security invoker set search_path = '' as $$
begin
 insert into private.auth_proofs(proof_hash,expires_at) values(p_hash,now()+interval '5 minutes') on conflict do nothing;
 return found;
end $$;
revoke all on function public.offgrid_auth_prepare(text,text) from public, anon, authenticated;
revoke all on function public.offgrid_auth_consume_proof(text) from public, anon, authenticated;
grant execute on function public.offgrid_auth_prepare(text,text) to service_role;
grant execute on function public.offgrid_auth_consume_proof(text) to service_role;

-- Session revocation is checked in RLS, not just the JWT expiration time.
create function private.offgrid_session_ok() returns boolean
 language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and auth.jwt()->>'aal' = 'aal2'
 and exists(select 1 from auth.sessions s where s.user_id=auth.uid()
   and s.id::text=auth.jwt()->>'session_id' and (s.not_after is null or s.not_after > now()));
$$;
revoke all on function private.offgrid_session_ok() from public, anon;
grant execute on function private.offgrid_session_ok() to authenticated, service_role;
create function public.offgrid_session_ok() returns boolean
 language sql stable security invoker set search_path = '' as $$select private.offgrid_session_ok();$$;
revoke all on function public.offgrid_session_ok() from public, anon;
grant execute on function public.offgrid_session_ok() to authenticated, service_role;
create policy own_verified_profile_read on public.offgrid_profiles for select to authenticated
 using ((select auth.uid())=user_id and (select public.offgrid_session_ok()));
create policy own_verified_profile_update on public.offgrid_profiles for update to authenticated
 using ((select auth.uid())=user_id and (select public.offgrid_session_ok()))
 with check ((select auth.uid())=user_id and (select public.offgrid_session_ok()));

create function private.offgrid_revoke_sessions(p_user uuid) returns void
 language sql security definer set search_path = '' as $$delete from auth.sessions where user_id=p_user;$$;
revoke all on function private.offgrid_revoke_sessions(uuid) from public, anon, authenticated;
grant execute on function private.offgrid_revoke_sessions(uuid) to service_role;
create function public.offgrid_revoke_sessions(p_user uuid) returns void
 language sql security invoker set search_path = '' as $$select private.offgrid_revoke_sessions(p_user);$$;
revoke all on function public.offgrid_revoke_sessions(uuid) from public, anon, authenticated;
grant execute on function public.offgrid_revoke_sessions(uuid) to service_role;

create function public.offgrid_replace_codes(p_user uuid,p_hashes text[]) returns void
 language plpgsql security invoker set search_path = '' as $$
begin
 if array_length(p_hashes,1) != 8 then raise exception 'Eight codes required'; end if;
 delete from private.recovery_codes where user_id=p_user;
 insert into private.recovery_codes(user_id,code_hash) select p_user,unnest(p_hashes);
end $$;
create function public.offgrid_consume_code(p_user uuid,p_hash text) returns boolean
 language plpgsql security invoker set search_path = '' as $$
begin
 delete from private.recovery_codes where user_id=p_user and code_hash=p_hash;
 return found;
end $$;
revoke all on function public.offgrid_replace_codes(uuid,text[]) from public, anon, authenticated;
revoke all on function public.offgrid_consume_code(uuid,text) from public, anon, authenticated;
grant execute on function public.offgrid_replace_codes(uuid,text[]) to service_role;
grant execute on function public.offgrid_consume_code(uuid,text) to service_role;
