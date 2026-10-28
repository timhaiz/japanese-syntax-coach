-- Protect Apple entitlement ownership and apply only newer signed transactions.
-- This migration is intentionally not applied automatically by the application.

alter table public.profiles
  add column if not exists apple_transaction_id text,
  add column if not exists apple_purchase_date timestamptz,
  add column if not exists apple_signed_date timestamptz;

create table if not exists public.apple_entitlement_owners (
  original_transaction_id text primary key,
  user_id uuid not null,
  created_at timestamptz not null default now()
);

alter table public.apple_entitlement_owners enable row level security;
revoke all on public.apple_entitlement_owners from public, anon, authenticated;
do $$
begin
  if exists (
    select apple_original_transaction_id
    from public.profiles
    where apple_original_transaction_id is not null
    group by apple_original_transaction_id
    having count(distinct id) > 1
  ) then
    raise exception 'Conflicting Apple transaction ownership exists; resolve profiles before applying this migration';
  end if;
end;
$$;
insert into public.apple_entitlement_owners (original_transaction_id, user_id)
select apple_original_transaction_id, id
from public.profiles
where apple_original_transaction_id is not null
on conflict (original_transaction_id) do nothing;

-- Clients may inspect their own profile but must not grant themselves membership.
drop policy if exists "own profile" on public.profiles;
drop policy if exists "own profile read" on public.profiles;
create policy "own profile read" on public.profiles
  for select using (auth.uid() = id);
revoke all on public.profiles from public, anon, authenticated;
grant select on public.profiles to authenticated;

create or replace function public.apply_apple_entitlement(
  p_user_id uuid,
  p_original_transaction_id text,
  p_transaction_id text,
  p_product_id text,
  p_membership_status text,
  p_expires_at timestamptz,
  p_purchase_date timestamptz,
  p_signed_date timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
  v_profile_original_transaction_id text;
  v_updated_id uuid;
begin
  if p_user_id is null
     or p_original_transaction_id is null or btrim(p_original_transaction_id) = ''
     or p_transaction_id is null or btrim(p_transaction_id) = ''
     or p_product_id is null or btrim(p_product_id) = ''
     or p_membership_status is null or p_membership_status not in ('active', 'expired')
     or p_purchase_date is null or p_signed_date is null then
    return jsonb_build_object('updated', false, 'reason', 'invalid-transaction-data');
  end if;

  -- Serialize first-time account binding as well as this subscription chain.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_original_transaction_id, 1));

  select profile.apple_original_transaction_id
    into v_profile_original_transaction_id
    from public.profiles as profile
    where profile.id = p_user_id
    for update;

  if v_profile_original_transaction_id is not null
     and v_profile_original_transaction_id <> p_original_transaction_id then
    return jsonb_build_object('updated', false, 'reason', 'account-already-bound-to-another-transaction');
  end if;

  select owner.user_id
    into v_owner
    from public.apple_entitlement_owners as owner
    where owner.original_transaction_id = p_original_transaction_id
    for update;

  if v_owner is not null and v_owner <> p_user_id then
    return jsonb_build_object('updated', false, 'reason', 'transaction-owned-by-another-user');
  end if;

  insert into public.apple_entitlement_owners (original_transaction_id, user_id)
  values (p_original_transaction_id, p_user_id)
  on conflict (original_transaction_id) do nothing;

  insert into public.profiles (
    id,
    membership_status,
    membership_ends_at,
    apple_original_transaction_id,
    apple_product_id,
    apple_transaction_id,
    apple_purchase_date,
    apple_signed_date
  ) values (
    p_user_id,
    p_membership_status,
    p_expires_at,
    p_original_transaction_id,
    p_product_id,
    p_transaction_id,
    p_purchase_date,
    p_signed_date
  )
  on conflict (id) do update set
    membership_status = excluded.membership_status,
    membership_ends_at = excluded.membership_ends_at,
    apple_original_transaction_id = excluded.apple_original_transaction_id,
    apple_product_id = excluded.apple_product_id,
    apple_transaction_id = excluded.apple_transaction_id,
    apple_purchase_date = excluded.apple_purchase_date,
    apple_signed_date = excluded.apple_signed_date
  where (public.profiles.apple_original_transaction_id is null
         or public.profiles.apple_original_transaction_id = p_original_transaction_id)
    and (public.profiles.apple_signed_date is null
         or p_signed_date > public.profiles.apple_signed_date
         or (p_signed_date = public.profiles.apple_signed_date
             and p_purchase_date > coalesce(public.profiles.apple_purchase_date, '-infinity'::timestamptz)))
  returning id into v_updated_id;

  if v_updated_id is null then
    return jsonb_build_object('updated', false, 'reason', 'stale-or-conflicting-transaction');
  end if;

  return jsonb_build_object('updated', true, 'status', p_membership_status, 'user_id', p_user_id);
end;
$$;

revoke all on function public.apply_apple_entitlement(uuid, text, text, text, text, timestamptz, timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.apply_apple_entitlement(uuid, text, text, text, text, timestamptz, timestamptz, timestamptz)
  to service_role;
