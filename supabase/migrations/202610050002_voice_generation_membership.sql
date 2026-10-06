-- Membership is managed by the billing webhook/admin, never by the browser.
alter table public.profiles
  add column if not exists membership_status text not null default 'free',
  add column if not exists membership_ends_at timestamptz,
  add column if not exists apple_original_transaction_id text,
  add column if not exists apple_product_id text;

alter table public.profiles
  drop constraint if exists profiles_membership_status_check;
alter table public.profiles
  add constraint profiles_membership_status_check
  check (membership_status in ('free', 'active', 'trialing', 'paused', 'cancelled', 'expired'));
