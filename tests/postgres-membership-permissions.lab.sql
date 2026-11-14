-- PostgreSQL permissions experiment ONLY: use a disposable, isolated database;
-- NEVER run on production or any database containing valuable data. Not a migration.
-- Requires a superuser, PL/pgSQL, and unused lab schema/role names. Roles are
-- cluster-wide: name collisions intentionally fail rather than reuse objects.
-- Run the entire file as one session, with autocommit disabled or as written.
-- On any error, stop execution and explicitly ROLLBACK or disconnect; do not
-- assume a runner, an interrupted session, or previously committed work rolls back.
-- Some runners continue after errors: check their error status and all assertions.

BEGIN;

CREATE ROLE jsc_lab_client NOLOGIN;
CREATE ROLE jsc_lab_service NOLOGIN;
CREATE ROLE jsc_lab_inherited NOLOGIN;
CREATE SCHEMA jsc_membership_lab;
CREATE TABLE jsc_membership_lab.profiles (
  id integer PRIMARY KEY,
  display_name text NOT NULL,
  membership_status text NOT NULL DEFAULT 'free'
    CHECK (membership_status IN ('free', 'active'))
);
ALTER TABLE jsc_membership_lab.profiles ENABLE ROW LEVEL SECURITY;

GRANT USAGE ON SCHEMA jsc_membership_lab TO jsc_lab_client, jsc_lab_service;
-- This setting stands in for a trusted request identity, not authentication.
-- Real clients must not be able to choose their own identity this way.
CREATE POLICY client_rows ON jsc_membership_lab.profiles
  TO jsc_lab_client
  USING (id = current_setting('jsc_lab.user_id', true)::integer)
  WITH CHECK (id = current_setting('jsc_lab.user_id', true)::integer);
CREATE POLICY service_rows ON jsc_membership_lab.profiles
  TO jsc_lab_service USING (true) WITH CHECK (true);

GRANT SELECT ON jsc_membership_lab.profiles TO jsc_lab_client, jsc_lab_service;
GRANT INSERT (id, display_name), UPDATE (display_name)
  ON jsc_membership_lab.profiles TO jsc_lab_client;
GRANT INSERT, UPDATE ON jsc_membership_lab.profiles TO jsc_lab_service;
SELECT set_config('jsc_lab.user_id', '1', true);

SET LOCAL ROLE jsc_lab_client;
INSERT INTO jsc_membership_lab.profiles (id, display_name) VALUES (1, 'Initial');
UPDATE jsc_membership_lab.profiles SET display_name = 'Updated' WHERE id = 1;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM jsc_membership_lab.profiles
                 WHERE id = 1 AND display_name = 'Updated' AND membership_status = 'free') THEN
    RAISE EXCEPTION 'normal client profile insert/update failed';
  END IF;
  -- Use a matching, unused identity so RLS cannot mask the column privilege test.
  PERFORM set_config('jsc_lab.user_id', '3', true);
  BEGIN
    INSERT INTO jsc_membership_lab.profiles (id, display_name, membership_status)
      VALUES (3, 'Escalation', 'active');
    RAISE EXCEPTION 'client membership insert unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('jsc_lab.user_id', '1', true);
  BEGIN
    UPDATE jsc_membership_lab.profiles SET membership_status = 'active' WHERE id = 1;
    RAISE EXCEPTION 'client membership update unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    INSERT INTO jsc_membership_lab.profiles (id, display_name) VALUES (2, 'Other');
    RAISE EXCEPTION 'client inserted another identity';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

RESET ROLE;
SET LOCAL ROLE jsc_lab_service;
-- Both branches of the service upsert must work with RLS enabled.
INSERT INTO jsc_membership_lab.profiles (id, display_name, membership_status)
  VALUES (2, 'Service insert', 'active')
  ON CONFLICT (id) DO UPDATE SET membership_status = EXCLUDED.membership_status;
INSERT INTO jsc_membership_lab.profiles (id, display_name, membership_status)
  VALUES (1, 'Ignored', 'active')
  ON CONFLICT (id) DO UPDATE SET membership_status = EXCLUDED.membership_status;
DO $$
BEGIN
  IF (SELECT count(*) FROM jsc_membership_lab.profiles
      WHERE id IN (1, 2) AND membership_status = 'active') <> 2 THEN
    RAISE EXCEPTION 'service upsert insert/update failed';
  END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE jsc_lab_client;
DO $$
DECLARE affected integer;
BEGIN
  IF EXISTS (SELECT 1 FROM jsc_membership_lab.profiles WHERE id = 2) THEN
    RAISE EXCEPTION 'client can see another identity';
  END IF;
  UPDATE jsc_membership_lab.profiles SET display_name = 'Unauthorized' WHERE id = 2;
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 0 THEN RAISE EXCEPTION 'client updated another identity'; END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE jsc_lab_service;
DO $$ BEGIN
  IF (SELECT display_name FROM jsc_membership_lab.profiles WHERE id = 2) <> 'Service insert' THEN
    RAISE EXCEPTION 'another identity was modified';
  END IF;
END $$;
RESET ROLE;
-- An empty identity must fail closed; a never-set setting is not covered here.
SET LOCAL ROLE jsc_lab_client;
SELECT set_config('jsc_lab.user_id', '', true);
DO $$ BEGIN
  BEGIN
    PERFORM 1 FROM jsc_membership_lab.profiles;
    RAISE EXCEPTION 'empty identity unexpectedly accepted';
  EXCEPTION WHEN invalid_text_representation THEN NULL;
  END;
END $$;
RESET ROLE;
SELECT set_config('jsc_lab.user_id', '1', true);

-- PostgreSQL 16 table-level REVOKE also removes this direct column grant.
GRANT UPDATE (membership_status) ON jsc_membership_lab.profiles TO jsc_lab_client;
DO $$
BEGIN
  IF NOT has_column_privilege('jsc_lab_client', 'jsc_membership_lab.profiles',
                              'membership_status', 'UPDATE') THEN
    RAISE EXCEPTION 'expected direct column grant before revoke';
  END IF;
END $$;
REVOKE UPDATE ON jsc_membership_lab.profiles FROM jsc_lab_client;
DO $$
BEGIN
  IF has_column_privilege('jsc_lab_client', 'jsc_membership_lab.profiles',
                          'membership_status', 'UPDATE') THEN
    RAISE EXCEPTION 'direct column grant unexpectedly survived table revoke';
  END IF;
END $$;

-- A grant inherited through another role also survives a direct revoke.
GRANT USAGE ON SCHEMA jsc_membership_lab TO jsc_lab_inherited;
GRANT UPDATE (membership_status) ON jsc_membership_lab.profiles TO jsc_lab_inherited;
GRANT jsc_lab_inherited TO jsc_lab_client;
REVOKE UPDATE (membership_status) ON jsc_membership_lab.profiles FROM jsc_lab_client;
DO $$
BEGIN
  IF NOT has_column_privilege('jsc_lab_client', 'jsc_membership_lab.profiles',
                              'membership_status', 'UPDATE') THEN
    RAISE EXCEPTION 'expected inherited column grant';
  END IF;
END $$;
SET LOCAL ROLE jsc_lab_client;
DO $$
DECLARE affected integer;
BEGIN
  UPDATE jsc_membership_lab.profiles SET membership_status = 'free' WHERE id = 1;
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 1 OR (SELECT membership_status FROM jsc_membership_lab.profiles WHERE id = 1) <> 'free' THEN
    RAISE EXCEPTION 'inherited privilege did not update exactly one row';
  END IF;
END $$;
RESET ROLE;
REVOKE jsc_lab_inherited FROM jsc_lab_client;

-- PUBLIC privileges are another independent source of effective access.
GRANT UPDATE (membership_status) ON jsc_membership_lab.profiles TO PUBLIC;
REVOKE UPDATE (membership_status) ON jsc_membership_lab.profiles FROM jsc_lab_client;
DO $$
BEGIN
  IF NOT has_column_privilege('jsc_lab_client', 'jsc_membership_lab.profiles',
                              'membership_status', 'UPDATE') THEN
    RAISE EXCEPTION 'expected PUBLIC column grant';
  END IF;
END $$;
SET LOCAL ROLE jsc_lab_client;
DO $$
DECLARE affected integer;
BEGIN
  UPDATE jsc_membership_lab.profiles SET membership_status = 'active' WHERE id = 1;
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 1 OR (SELECT membership_status FROM jsc_membership_lab.profiles WHERE id = 1) <> 'active' THEN
    RAISE EXCEPTION 'PUBLIC privilege did not update exactly one row';
  END IF;
END $$;
RESET ROLE;
REVOKE UPDATE (membership_status) ON jsc_membership_lab.profiles FROM PUBLIC;
DO $$
BEGIN
  IF has_column_privilege('jsc_lab_client', 'jsc_membership_lab.profiles',
                          'membership_status', 'UPDATE') THEN
    RAISE EXCEPTION 'unexpected effective client membership update privilege';
  END IF;
END $$;

ROLLBACK;
