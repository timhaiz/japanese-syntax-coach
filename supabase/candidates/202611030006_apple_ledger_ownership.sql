-- NOT READY FOR DEPLOYMENT: review-only candidate; do not apply or remove guard.
-- Depends on the equally disabled Apple ledger foundation candidate.
begin;
do $$
begin
  raise exception 'Apple ledger ownership is intentionally disabled';
end;
$$;

-- The caller must independently verify the Apple signature, authenticate the
-- user, and prove appAccountToken belongs to that authenticated user and matches
-- the verified transaction. This RPC is not authorization and does not verify
-- any of those facts. Missing proof or any error must fail closed at the caller.
-- A conflict never transfers ownership. No entitlement projection is performed.
create function public.apple_ledger_claim_owner(
  p_environment text,
  p_original_transaction_id text,
  p_user_id uuid
) returns text
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_owner uuid;
begin
  if p_environment is null or p_environment not in ('Sandbox', 'Production')
     or p_original_transaction_id is null
     or length(btrim(p_original_transaction_id)) = 0
     or p_original_transaction_id ~ '[[:space:][:cntrl:]]'
     or p_user_id is null then
    raise exception 'invalid Apple ownership identity';
  end if;

  insert into public.apple_ledger_owners (environment, original_transaction_id, user_id)
  values (p_environment, p_original_transaction_id, p_user_id)
  on conflict (environment, original_transaction_id) do nothing;

  if found then
    return 'inserted';
  end if;

  -- A fresh READ COMMITTED statement snapshot sees a concurrent winner after it
  -- commits. Lock against deletion while comparing. Serialization errors at
  -- stronger isolation levels and all other errors propagate to the caller.
  select user_id into v_owner
    from public.apple_ledger_owners
    where environment = p_environment and original_transaction_id = p_original_transaction_id
    for update;
  if not found then
    raise exception 'Apple ownership conflict row unavailable';
  end if;
  if v_owner = p_user_id then
    return 'duplicate';
  else
    return 'conflict';
  end if;
end;
$$;

revoke all on function public.apple_ledger_claim_owner(text, text, uuid) from public, anon, authenticated;
grant execute on function public.apple_ledger_claim_owner(text, text, uuid) to service_role;
commit;
