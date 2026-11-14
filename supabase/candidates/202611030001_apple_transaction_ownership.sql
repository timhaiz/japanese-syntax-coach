-- NOT READY FOR DEPLOYMENT: retained candidate source only; never apply directly.
-- Subscription ordering and cross-subscription projection are unresolved.
-- Existing profile fields are not a trustworthy ownership ledger. Stop and
-- require operator reconciliation instead of silently treating legacy rows as empty.
begin;

do $$
begin
  raise exception 'Apple ownership migration is intentionally disabled';
end;
$$;

create table public.apple_transaction_ownership (
  original_transaction_id text primary key check (length(btrim(original_transaction_id)) > 0),
  user_id uuid not null references auth.users(id) on delete cascade,
  latest_transaction_id text not null check (length(btrim(latest_transaction_id)) > 0),
  product_id text not null check (length(btrim(product_id)) > 0),
  membership_ends_at timestamptz,
  revoked boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.apple_transaction_ownership enable row level security;

create or replace function public.apply_apple_transaction(
  p_user_id uuid,
  p_original_transaction_id text,
  p_transaction_id text,
  p_product_id text,
  p_membership_ends_at timestamptz,
  p_is_active boolean,
  p_is_revoked boolean
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_owner public.apple_transaction_ownership%rowtype;
  v_status text;
begin
  if p_user_id is null
     or p_original_transaction_id is null or length(btrim(p_original_transaction_id)) = 0
     or p_transaction_id is null or length(btrim(p_transaction_id)) = 0
     or p_product_id is null or length(btrim(p_product_id)) = 0
     or p_is_active is null or p_is_revoked is null then
    raise exception 'Required Apple transaction identity is missing';
  end if;

  insert into public.apple_transaction_ownership (
    original_transaction_id, user_id, latest_transaction_id,
    product_id, membership_ends_at, revoked
  ) values (
    p_original_transaction_id, p_user_id, p_transaction_id,
    p_product_id, p_membership_ends_at, p_is_revoked
  ) on conflict (original_transaction_id) do nothing;

  select * into v_owner
  from public.apple_transaction_ownership
  where original_transaction_id = p_original_transaction_id
  for update;

  if v_owner.user_id <> p_user_id then
    raise exception 'Apple ownership conflict';
  end if;

  -- Revocation is sticky: without a trusted event sequence, an older active
  -- transaction must never restore access after a refund/revoke was recorded.
  update public.apple_transaction_ownership
  set latest_transaction_id = p_transaction_id,
      product_id = p_product_id,
      membership_ends_at = p_membership_ends_at,
      revoked = revoked or p_is_revoked,
      updated_at = now()
  where original_transaction_id = p_original_transaction_id
  returning * into v_owner;

  v_status := case when p_is_active and not v_owner.revoked then 'active' else 'expired' end;
  update public.profiles
  set membership_status = v_status,
      membership_ends_at = p_membership_ends_at,
      apple_original_transaction_id = p_original_transaction_id,
      apple_product_id = p_product_id
  where id = p_user_id;

  if not found then
    raise exception 'Apple profile does not exist';
  end if;

  return jsonb_build_object('updated', true, 'status', v_status, 'userId', p_user_id);
end;
$$;

revoke all on public.apple_transaction_ownership from public, anon, authenticated;
revoke all on function public.apply_apple_transaction(uuid, text, text, text, timestamptz, boolean, boolean) from public, anon, authenticated;
grant execute on function public.apply_apple_transaction(uuid, text, text, text, timestamptz, boolean, boolean) to service_role;

commit;
