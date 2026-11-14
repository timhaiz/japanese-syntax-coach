-- NOT READY FOR DEPLOYMENT: review-only candidate; do not apply or remove guard.
-- Depends on the equally disabled Apple ledger foundation candidate.
begin;
do $$
begin
  raise exception 'Apple notification deduplication is intentionally disabled';
end;
$$;

-- Signature verification and authorization are the caller's responsibility;
-- only independently verified input may be submitted. A duplicate does not mean
-- the notification was processed: reconciliation remains required. A conflict
-- requires investigation, never an overwrite. Deduplication lasts only while
-- the original row is retained. Errors must propagate; callers must fail closed.
-- This function does not establish ordering, processing or entitlement state.
create function public.apple_notification_dedup(
  p_environment text,
  p_notification_uuid text,
  p_notification_type text,
  p_signed_at timestamptz,
  p_identity_scope text,
  p_original_transaction_id text,
  p_transaction_id text,
  p_payload_sha256 bytea,
  p_retain_until timestamptz
) returns text
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_digest bytea;
begin
  if p_payload_sha256 is null or octet_length(p_payload_sha256) <> 32 then
    raise exception 'invalid notification digest';
  end if;

  insert into public.apple_ledger_notifications (
    environment, notification_uuid, notification_type, signed_at, identity_scope,
    original_transaction_id, transaction_id, payload_sha256, retain_until
  ) values (
    p_environment, p_notification_uuid, p_notification_type, p_signed_at, p_identity_scope,
    p_original_transaction_id, p_transaction_id, p_payload_sha256, p_retain_until
  ) on conflict (environment, notification_uuid) do nothing;

  if found then
    return 'inserted';
  end if;

  -- A separate statement gets a fresh READ COMMITTED snapshot after any
  -- concurrent inserter commits. Lock the row against deletion while comparing.
  -- Other isolation levels may raise serialization errors, which propagate.
  select payload_sha256 into v_digest
    from public.apple_ledger_notifications
    where environment = p_environment and notification_uuid = p_notification_uuid
    for update;
  if not found then
    raise exception 'notification conflict row unavailable';
  end if;
  if v_digest = p_payload_sha256 then
    return 'duplicate';
  else
    return 'conflict';
  end if;
end;
$$;

revoke all on function public.apple_notification_dedup(text, text, text, timestamptz, text, text, text, bytea, timestamptz) from public, anon, authenticated;
grant execute on function public.apple_notification_dedup(text, text, text, timestamptz, text, text, text, bytea, timestamptz) to service_role;
commit;
