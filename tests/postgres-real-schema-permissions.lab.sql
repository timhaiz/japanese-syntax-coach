-- ONE-OFF LAB ONLY: use an EMPTY, disposable, isolated PostgreSQL database.
-- NEVER run against production or a database with valuable data. This is NOT a migration.
-- Requires psql, a superuser (to create a BYPASSRLS role), PL/pgSQL, and unused
-- cluster-wide role names. Existing auth/schema objects or role names must not be reused.
-- The auth.users and auth.uid() below are FICTIONAL: the session setting can be
-- forged and provides no authentication. This does not test real Supabase auth.
-- Run this whole file in one psql session. ON_ERROR_STOP prevents continuing after
-- failure; on error or interruption explicitly ROLLBACK or disconnect. Do not
-- commit the transaction. Successful completion ends with ROLLBACK.
\set ON_ERROR_STOP on
BEGIN;

CREATE ROLE jsc_real_lab_client NOLOGIN;
CREATE ROLE jsc_real_lab_service NOLOGIN BYPASSRLS;
CREATE SCHEMA auth;
CREATE TABLE auth.users (id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('jsc_real_lab.user_id', true), '')::uuid
$$;
GRANT USAGE ON SCHEMA auth, public TO jsc_real_lab_client, jsc_real_lab_service;
GRANT EXECUTE ON FUNCTION auth.uid() TO jsc_real_lab_client, jsc_real_lab_service;

\ir ../supabase/schema.sql
\ir ../supabase/migrations/202610050002_voice_generation_membership.sql
\ir ../supabase/migrations/202610050003_apple_subscription_fields.sql

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000002'),
  ('00000000-0000-0000-0000-000000000003');
GRANT SELECT, INSERT, UPDATE ON public.profiles TO jsc_real_lab_client;
SELECT set_config('jsc_real_lab.user_id', '00000000-0000-0000-0000-000000000001', true);

-- Under broad grants the real own-profile policy permits membership writes.
SET LOCAL ROLE jsc_real_lab_client;
INSERT INTO public.profiles (id, display_name, membership_status, membership_ends_at,
                             apple_original_transaction_id, apple_product_id)
VALUES (auth.uid(), 'Broad', 'active', '2030-01-01T00:00:00Z', 'broad-original', 'broad-product');
UPDATE public.profiles SET membership_status = 'trialing', membership_ends_at = '2031-01-01T00:00:00Z',
  apple_original_transaction_id = 'broad-updated', apple_product_id = 'broad-updated-product'
WHERE id = auth.uid();
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()
    AND membership_status = 'trialing' AND membership_ends_at = '2031-01-01T00:00:00Z'
    AND apple_original_transaction_id = 'broad-updated' AND apple_product_id = 'broad-updated-product') THEN
    RAISE EXCEPTION 'broad membership insert/update failed';
  END IF;
END $$;
RESET ROLE;

-- This models a proposed restricted grant, not a change to the real schema.
-- Remove PUBLIC access as well; the fresh client has no inherited roles.
REVOKE INSERT, UPDATE ON public.profiles FROM PUBLIC, jsc_real_lab_client;
GRANT INSERT (id, display_name, daily_goal), UPDATE (display_name, daily_goal)
  ON public.profiles TO jsc_real_lab_client;
DO $$
DECLARE col text; operation text;
BEGIN
  FOREACH col IN ARRAY ARRAY['membership_status', 'membership_ends_at',
    'apple_original_transaction_id', 'apple_product_id'] LOOP
    FOREACH operation IN ARRAY ARRAY['INSERT', 'UPDATE'] LOOP
      IF has_column_privilege('jsc_real_lab_client', 'public.profiles', col, operation) THEN
        RAISE EXCEPTION 'unexpected % privilege on %', operation, col;
      END IF;
    END LOOP;
  END LOOP;
END $$;

SET LOCAL ROLE jsc_real_lab_client;
-- A matching, existing row proves ordinary updates pass RLS.
UPDATE public.profiles SET display_name = 'Normal update', daily_goal = 15 WHERE id = auth.uid();
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()
                 AND display_name = 'Normal update' AND daily_goal = 15) THEN
    RAISE EXCEPTION 'ordinary profile update failed';
  END IF;
END $$;
-- Check each field separately against an existing own row, and against an unused
-- own auth.users ID. Both identities exist, so neither RLS nor the FK masks errors.
DO $$
DECLARE col text; value_sql text; denied boolean;
BEGIN
  FOR col, value_sql IN SELECT * FROM (VALUES
    ('membership_status', quote_literal('active')),
    ('membership_ends_at', quote_literal('2032-01-01T00:00:00Z')),
    ('apple_original_transaction_id', quote_literal('original')),
    ('apple_product_id', quote_literal('product'))
  ) AS fields(name, val) LOOP
    PERFORM set_config('jsc_real_lab.user_id', '00000000-0000-0000-0000-000000000001', true);
    denied := false;
    BEGIN
      EXECUTE format('UPDATE public.profiles SET %I = %s WHERE id = auth.uid()', col, value_sql);
    EXCEPTION WHEN insufficient_privilege THEN denied := true;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'membership UPDATE unexpectedly succeeded: %', col; END IF;

    PERFORM set_config('jsc_real_lab.user_id', '00000000-0000-0000-0000-000000000002', true);
    denied := false;
    BEGIN
      EXECUTE format('INSERT INTO public.profiles (id, display_name, %I) VALUES (auth.uid(), %L, %s)',
                     col, 'Denied insert', value_sql);
    EXCEPTION WHEN insufficient_privilege THEN denied := true;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'membership INSERT unexpectedly succeeded: %', col; END IF;
  END LOOP;
END $$;
-- The very same unused identity can insert ordinary columns under the same RLS policy.
INSERT INTO public.profiles (id, display_name, daily_goal) VALUES (auth.uid(), 'Normal insert', 12);
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND display_name = 'Normal insert') THEN
    RAISE EXCEPTION 'ordinary profile insert failed';
  END IF;
END $$;
RESET ROLE;

-- Simulate a privileged service with real BYPASSRLS, not the table owner.
GRANT SELECT, INSERT, UPDATE ON public.profiles TO jsc_real_lab_service;
SET LOCAL ROLE jsc_real_lab_service;
-- Identity remains user 2, while both targets differ: RLS bypass is required.
INSERT INTO public.profiles (id, membership_status, membership_ends_at,
                             apple_original_transaction_id, apple_product_id)
VALUES ('00000000-0000-0000-0000-000000000003', 'active',
        '2033-01-01T00:00:00Z', 'service-insert-original', 'service-insert-product')
ON CONFLICT (id) DO UPDATE SET membership_status = EXCLUDED.membership_status,
  membership_ends_at = EXCLUDED.membership_ends_at,
  apple_original_transaction_id = EXCLUDED.apple_original_transaction_id,
  apple_product_id = EXCLUDED.apple_product_id;
INSERT INTO public.profiles (id, membership_status, membership_ends_at,
                             apple_original_transaction_id, apple_product_id)
VALUES ('00000000-0000-0000-0000-000000000001', 'expired',
        '2034-01-01T00:00:00Z', 'service-update-original', 'service-update-product')
ON CONFLICT (id) DO UPDATE SET membership_status = EXCLUDED.membership_status,
  membership_ends_at = EXCLUDED.membership_ends_at,
  apple_original_transaction_id = EXCLUDED.apple_original_transaction_id,
  apple_product_id = EXCLUDED.apple_product_id;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = '00000000-0000-0000-0000-000000000003'
      AND membership_status = 'active' AND membership_ends_at = '2033-01-01T00:00:00Z'
      AND apple_original_transaction_id = 'service-insert-original' AND apple_product_id = 'service-insert-product')
    OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = '00000000-0000-0000-0000-000000000001'
      AND membership_status = 'expired' AND membership_ends_at = '2034-01-01T00:00:00Z'
      AND apple_original_transaction_id = 'service-update-original' AND apple_product_id = 'service-update-product') THEN
    RAISE EXCEPTION 'service upsert insert/update failed';
  END IF;
END $$;
RESET ROLE;
ROLLBACK;
