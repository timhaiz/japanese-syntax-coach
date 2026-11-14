-- NOT READY FOR DEPLOYMENT: isolated design candidate, not a migration.
-- No ingestion or projection is implemented. Never remove the guard to deploy.
-- A failed guard aborts the entire transaction even if the client continues.
begin;
do $$
begin
  raise exception 'Apple ledger foundation is intentionally disabled';
end;
$$;

-- Environment is part of every identity: sandbox and production must not collide.
-- Restrict deletion so account removal cannot silently release an Apple identity.
create table public.apple_ledger_owners (
  environment text not null check (environment in ('Sandbox', 'Production')),
  original_transaction_id text not null check (length(btrim(original_transaction_id)) > 0 and original_transaction_id !~ '[[:space:][:cntrl:]]'),
  user_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (environment, original_transaction_id)
);

-- Only independently verified events may enter this table; this schema does not
-- verify signatures. UUID plus digest detects conflicting retries only while the
-- row is retained. Transaction identity is independent of ownership, so a claim
-- can locate earlier events. Other events cannot be linked to a claim this way.
-- IDs are lookup keys, not proof of ownership or complete replay data: trusted
-- Apple reconciliation and atomic conflict handling remain unimplemented.
-- Do not retain raw signed payloads here. The 90-day maximum is a candidate
-- privacy ceiling, not an approved retention period: choose a shorter deadline
-- when justified. An audited purge process, expiry monitoring, deletion/legal
-- policy and post-expiry reconciliation must be designed before any activation;
-- this constraint alone does not delete expired rows or guarantee deduplication.
create table public.apple_ledger_notifications (
  environment text not null check (environment in ('Sandbox', 'Production')),
  notification_uuid text not null check (length(btrim(notification_uuid)) > 0 and notification_uuid !~ '[[:space:][:cntrl:]]'),
  notification_type text not null check (length(btrim(notification_type)) > 0 and notification_type !~ '[[:space:][:cntrl:]]'),
  signed_at timestamptz not null,
  identity_scope text not null check (identity_scope in ('transaction', 'other')),
  original_transaction_id text check (length(btrim(original_transaction_id)) > 0 and original_transaction_id !~ '[[:space:][:cntrl:]]'),
  transaction_id text check (length(btrim(transaction_id)) > 0 and transaction_id !~ '[[:space:][:cntrl:]]'),
  payload_sha256 bytea not null check (octet_length(payload_sha256) = 32),
  received_at timestamptz not null default now(),
  retain_until timestamptz not null,
  reconciliation_required boolean not null default true,
  primary key (environment, notification_uuid),
  check ((identity_scope = 'transaction' and original_transaction_id is not null and transaction_id is not null)
      or (identity_scope = 'other' and original_transaction_id is null and transaction_id is null)),
  check (retain_until > received_at and retain_until <= received_at + interval '90 days')
);
create index apple_ledger_notifications_chain_idx
  on public.apple_ledger_notifications (environment, original_transaction_id)
  where identity_scope = 'transaction';

-- Revocation belongs to one transaction, never to its whole subscription chain.
-- Rows are not a current entitlement until trusted ordering and reconciliation
-- have been implemented; this schema does not define a merge policy.
create table public.apple_ledger_transactions (
  environment text not null check (environment in ('Sandbox', 'Production')),
  transaction_id text not null check (length(btrim(transaction_id)) > 0 and transaction_id !~ '[[:space:][:cntrl:]]'),
  original_transaction_id text not null check (length(btrim(original_transaction_id)) > 0 and original_transaction_id !~ '[[:space:][:cntrl:]]'),
  product_id text not null check (length(btrim(product_id)) > 0 and product_id !~ '[[:space:][:cntrl:]]'),
  expires_at timestamptz,
  revoked_at timestamptz,
  reconciliation_required boolean not null default true,
  primary key (environment, transaction_id),
  foreign key (environment, original_transaction_id)
    references public.apple_ledger_owners (environment, original_transaction_id) on delete restrict
);

alter table public.apple_ledger_owners enable row level security;
alter table public.apple_ledger_notifications enable row level security;
alter table public.apple_ledger_transactions enable row level security;
revoke all on public.apple_ledger_owners from public, anon, authenticated;
revoke all on public.apple_ledger_notifications from public, anon, authenticated;
revoke all on public.apple_ledger_transactions from public, anon, authenticated;
commit;
