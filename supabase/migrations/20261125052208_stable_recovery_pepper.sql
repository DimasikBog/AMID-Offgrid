-- Keep recovery-code protection independent of API signing-key rotation.
create table private.auth_secrets (
 purpose text primary key,
 value bytea not null check (octet_length(value)=32)
);
alter table private.auth_secrets enable row level security;
grant select on private.auth_secrets to service_role;
insert into private.auth_secrets(purpose,value) values('recovery-pepper',extensions.gen_random_bytes(32));
create or replace function public.offgrid_replace_codes(p_user uuid,p_hashes text[]) returns void
 language plpgsql security invoker set search_path = '' as $$
begin
 if array_length(p_hashes,1) != 8 or exists(select 1 from unnest(p_hashes) code where code !~ '^[a-f0-9]{32}$')
 then raise exception 'Eight random codes required'; end if;
 delete from private.recovery_codes where user_id=p_user;
 insert into private.recovery_codes(user_id,code_hash)
 select p_user,encode(extensions.hmac(convert_to(p_user::text||':'||code,'UTF8'),
   (select value from private.auth_secrets where purpose='recovery-pepper'),'sha256'),'hex')
 from unnest(p_hashes) code;
end $$;
create or replace function public.offgrid_consume_code(p_user uuid,p_hash text) returns boolean
 language plpgsql security invoker set search_path = '' as $$
begin
 if p_hash !~ '^[a-f0-9]{32}$' then return false; end if;
 delete from private.recovery_codes where user_id=p_user and code_hash=
 encode(extensions.hmac(convert_to(p_user::text||':'||p_hash,'UTF8'),
   (select value from private.auth_secrets where purpose='recovery-pepper'),'sha256'),'hex');
 return found;
end $$;
