-- Review candidate only: do not apply without a validated rollout and recovery plan.
-- Requires the operation-store schema. Existing duplicate identities cause index
-- creation to fail; do not discard or merge records to make this succeed.
-- This deliberately permits only one operation per identity for all time. A
-- new operation with another ID fails, including after completion. Recovery,
-- identity reuse, and any future release of this fence need a separate protocol.
-- The CAS RPC currently reports an identity uniqueness conflict as an error;
-- callers must treat that outcome as indeterminate, never as permission to run.
create unique index account_deletion_operations_identity_fence
  on public.account_deletion_operations ((record->>'identity'));

-- Server-only lookup primitive, not an authorization mechanism. The caller must
-- independently authenticate and authorize the exact identity; never expose this
-- RPC or accept a request-supplied identity as proof. It returns no state or data.
create function public.account_deletion_operation_find_by_identity(p_identity text)
returns text
language sql
security definer
set search_path = pg_catalog, public
as $$
  select operation_id from public.account_deletion_operations
  where record->>'identity' = p_identity
$$;

revoke all on function public.account_deletion_operation_find_by_identity(text) from public, anon, authenticated;
grant execute on function public.account_deletion_operation_find_by_identity(text) to service_role;
