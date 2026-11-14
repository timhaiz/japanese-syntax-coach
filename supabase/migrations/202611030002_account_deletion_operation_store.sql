-- Durable state storage only. This does not perform account or user-data deletion.
-- Migration source for review; do not apply against production as part of this task.
create table public.account_deletion_operations (
  operation_id text primary key check (operation_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'),
  record jsonb not null,
  version bigint not null check (version >= 0),
  constraint account_deletion_operation_record_matches check (
    (record->>'operationId') is not distinct from operation_id
    and jsonb_typeof(record->'version') is not distinct from 'number'
    and (record->>'version')::numeric is not distinct from version::numeric
    and jsonb_typeof(record->'identity') is not distinct from 'string'
    and length(record->>'identity') > 0
    and jsonb_typeof(record->'steps') is not distinct from 'array'
  )
);

alter table public.account_deletion_operations enable row level security;
revoke all on table public.account_deletion_operations from public, anon, authenticated, service_role;

create function public.account_deletion_operation_get(p_operation_id text)
returns jsonb
language sql
security definer
set search_path = pg_catalog, public
as $$
  select record from public.account_deletion_operations where operation_id = p_operation_id
$$;

create function public.account_deletion_operation_cas(
  p_operation_id text,
  p_expected_version bigint,
  p_record jsonb
) returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_version bigint;
begin
  if p_operation_id is null or p_operation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then
    raise exception 'Invalid operation ID';
  end if;
  if p_record is null
     or (p_record->>'operationId') is distinct from p_operation_id
     or jsonb_typeof(p_record->'version') is distinct from 'number'
     or jsonb_typeof(p_record->'identity') is distinct from 'string'
     or length(p_record->>'identity') = 0
     or jsonb_typeof(p_record->'steps') is distinct from 'array' then
    raise exception 'Invalid operation record';
  end if;
  v_version := (p_record->>'version')::bigint;
  if v_version < 0 or (p_expected_version is null and v_version <> 0)
     or (p_expected_version is not null and v_version <> p_expected_version + 1) then
    raise exception 'Invalid operation version transition';
  end if;

  if p_expected_version is null then
    insert into public.account_deletion_operations(operation_id, record, version)
    values (p_operation_id, p_record, v_version)
    on conflict (operation_id) do nothing;
    return found;
  end if;

  update public.account_deletion_operations
  set record = p_record, version = v_version
  where operation_id = p_operation_id
    and version = p_expected_version
    and record->'identity' = p_record->'identity';
  return found;
end;
$$;

revoke all on function public.account_deletion_operation_get(text) from public, anon, authenticated;
grant execute on function public.account_deletion_operation_get(text) to service_role;
revoke all on function public.account_deletion_operation_cas(text, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.account_deletion_operation_cas(text, bigint, jsonb) to service_role;
