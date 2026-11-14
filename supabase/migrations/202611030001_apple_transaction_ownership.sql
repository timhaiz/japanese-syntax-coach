-- NOT READY FOR DEPLOYMENT: candidate only; server writes are intentionally disabled.
-- Dangerous DDL is retained outside this directory in supabase/candidates/.
-- Keep this migration fail-closed even if an executor continues after SQL errors.
do $$
begin
  raise exception 'Apple ownership migration is intentionally disabled';
end;
$$;
