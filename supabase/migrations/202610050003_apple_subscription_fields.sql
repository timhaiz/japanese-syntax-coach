-- Add Apple transaction fields separately so already-applied membership
-- migrations receive the fields without being edited or replayed.
alter table public.profiles
  add column if not exists apple_original_transaction_id text,
  add column if not exists apple_product_id text;

create index if not exists profiles_apple_original_transaction_idx
  on public.profiles (apple_original_transaction_id)
  where apple_original_transaction_id is not null;
