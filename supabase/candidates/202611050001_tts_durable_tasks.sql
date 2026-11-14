-- CANDIDATE ONLY: review/design artifact; do not deploy or copy into migrations.
-- This schema records durable work and object identities; it does not implement
-- job admission, worker execution, publication, or retention cleanup.
begin;

create table public.tts_textbook_guards (
  user_id uuid not null references auth.users(id) on delete restrict,
  textbook_id text not null check (length(btrim(textbook_id)) > 0),
  created_at timestamptz not null default now(),
  primary key (user_id, textbook_id)
);

create table public.tts_generation_counters (
  user_id uuid not null,
  textbook_id text not null,
  generation bigint not null default 0 check (generation >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, textbook_id),
  foreign key (user_id, textbook_id)
    references public.tts_textbook_guards (user_id, textbook_id) on delete restrict
);

create table public.tts_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  textbook_id text not null,
  idempotency_key text not null check (length(btrim(idempotency_key)) > 0),
  request_digest bytea not null check (octet_length(request_digest) = 32),
  schema_version integer not null check (schema_version > 0),
  speaker integer not null check (speaker >= 0),
  engine_version text not null check (length(btrim(engine_version)) > 0),
  sentences jsonb not null check (jsonb_typeof(sentences) = 'array'),
  snapshot_sha256 bytea not null check (octet_length(snapshot_sha256) = 32),
  snapshot_byte_length bigint not null check (snapshot_byte_length >= 0),
  status text not null check (status in ('queued', 'running', 'retry_wait', 'publishing', 'succeeded', 'failed')),
  publisher_lease_owner text,
  publisher_fencing_epoch bigint not null default 0 check (publisher_fencing_epoch >= 0),
  publisher_lease_expires_at timestamptz,
  total integer not null check (total >= 0),
  completed integer not null default 0 check (completed >= 0 and completed <= total),
  diagnostic_error_code text,
  diagnostic_metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(diagnostic_metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  started_at timestamptz,
  terminal_at timestamptz,
  snapshot_retain_until timestamptz,
  idempotency_retain_until timestamptz not null,
  diagnostics_retain_until timestamptz,
  unique (user_id, idempotency_key),
  foreign key (user_id, textbook_id)
    references public.tts_textbook_guards (user_id, textbook_id) on delete restrict,
  check ((status in ('succeeded', 'failed')) = (terminal_at is not null)),
  check ((publisher_lease_owner is null) = (publisher_lease_expires_at is null)),
  check ((status = 'publishing') or publisher_lease_owner is null),
  check ((status in ('succeeded', 'failed')) = (snapshot_retain_until is not null)),
  check (snapshot_retain_until is null or snapshot_retain_until >= terminal_at + interval '30 days'),
  check ((status in ('succeeded', 'failed')) = (diagnostics_retain_until is not null)),
  check (diagnostics_retain_until is null or diagnostics_retain_until >= terminal_at + interval '180 days'),
  check (idempotency_retain_until >= created_at + interval '180 days'),
  check (status not in ('succeeded', 'failed')
      or idempotency_retain_until >= terminal_at + interval '180 days')
);

-- Query: find a user's active job for a textbook; enforces one active job.
create unique index tts_jobs_one_active_per_textbook_idx
  on public.tts_jobs (user_id, textbook_id)
  where status in ('queued', 'running', 'retry_wait', 'publishing');

-- Query: terminal job purge scans after snapshot/diagnostic retention deadlines.
create index tts_jobs_retention_idx
  on public.tts_jobs (snapshot_retain_until, diagnostics_retain_until)
  where status in ('succeeded', 'failed');

create table public.tts_job_chunks (
  job_id uuid not null references public.tts_jobs(id) on delete restrict,
  chunk_index integer not null check (chunk_index >= 0),
  status text not null default 'queued' check (status in ('queued', 'running', 'succeeded', 'failed')),
  attempt integer not null default 0 check (attempt >= 0),
  lease_owner text,
  lease_expires_at timestamptz,
  fencing_epoch bigint not null default 0 check (fencing_epoch >= 0),
  object_key text,
  object_sha256 bytea check (object_sha256 is null or octet_length(object_sha256) = 32),
  object_byte_length bigint check (object_byte_length is null or object_byte_length >= 0),
  object_created_at timestamptz,
  unreferenced_confirmed_at timestamptz,
  unreferenced_at timestamptz,
  object_retain_until timestamptz,
  updated_at timestamptz not null default now(),
  primary key (job_id, chunk_index),
  check ((lease_owner is null) = (lease_expires_at is null)),
  check ((object_key is null and object_sha256 is null and object_byte_length is null)
      or (object_key is not null and object_sha256 is not null and object_byte_length is not null)),
  check (object_key is null or length(btrim(object_key)) > 0),
  check (object_key is null or object_created_at is not null),
  check (unreferenced_confirmed_at is null or object_key is not null),
  check (unreferenced_at is null or (object_key is not null and unreferenced_confirmed_at is not null)),
  check (object_retain_until is null or unreferenced_at is not null),
  check (object_retain_until is null or object_retain_until >= unreferenced_at + interval '30 days')
);

-- Query: recover expired chunk leases and fence stale workers.
create index tts_job_chunks_expired_lease_idx
  on public.tts_job_chunks (lease_expires_at)
  where lease_owner is not null;

-- Query: find confirmed, non-current objects eligible for delayed deletion.
create index tts_job_chunks_object_retention_idx
  on public.tts_job_chunks (object_retain_until)
  where object_key is not null and unreferenced_at is not null;

create table public.tts_outbox (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.tts_jobs(id) on delete restrict,
  dispatch_generation bigint not null check (dispatch_generation >= 0),
  available_at timestamptz not null default now(),
  lease_owner text,
  lease_expires_at timestamptz,
  fencing_epoch bigint not null default 0 check (fencing_epoch >= 0),
  dispatched_at timestamptz,
  created_at timestamptz not null default now(),
  unique (job_id, dispatch_generation),
  check ((lease_owner is null) = (lease_expires_at is null))
);

-- Query: lease the next due Outbox records, ordered by available_at.
create index tts_outbox_due_idx
  on public.tts_outbox (available_at, id)
  where dispatched_at is null;

-- Query: recover expired Outbox leases.
create index tts_outbox_expired_lease_idx
  on public.tts_outbox (lease_expires_at)
  where lease_owner is not null and dispatched_at is null;

create table public.tts_manifest_heads (
  user_id uuid not null references auth.users(id) on delete restrict,
  textbook_id text not null,
  manifest_revision bigint not null check (manifest_revision >= 0),
  job_id uuid not null references public.tts_jobs(id) on delete restrict,
  object_key text not null check (length(btrim(object_key)) > 0),
  object_sha256 bytea not null check (octet_length(object_sha256) = 32),
  object_byte_length bigint not null check (object_byte_length >= 0),
  published_at timestamptz not null default now(),
  retain_until timestamptz,
  primary key (user_id, textbook_id),
  foreign key (user_id, textbook_id)
    references public.tts_textbook_guards (user_id, textbook_id) on delete restrict
);

-- Query: read the current manifest head for a user's textbook.
create index tts_manifest_heads_job_idx
  on public.tts_manifest_heads (user_id, textbook_id, job_id);

alter table public.tts_textbook_guards enable row level security;
alter table public.tts_generation_counters enable row level security;
alter table public.tts_jobs enable row level security;
alter table public.tts_job_chunks enable row level security;
alter table public.tts_outbox enable row level security;
alter table public.tts_manifest_heads enable row level security;

revoke all on table public.tts_textbook_guards, public.tts_generation_counters,
  public.tts_jobs, public.tts_job_chunks, public.tts_outbox, public.tts_manifest_heads
  from public, anon, authenticated;

-- Transaction RPCs are server-only. The authenticated API verifies the bearer token
-- before passing the provider-confirmed user_id; no browser role can execute these.
create or replace function public.tts_create_job(
  p_user_id uuid,
  p_textbook_id text,
  p_idempotency_key text,
  p_request_digest bytea,
  p_schema_version integer,
  p_speaker integer,
  p_engine_version text,
  p_sentences jsonb,
  p_snapshot_sha256 bytea,
  p_snapshot_byte_length bigint,
  p_total integer,
  p_configuration_available boolean
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_job public.tts_jobs%rowtype;
  v_generation bigint;
  v_job_id uuid;
begin
  if p_user_id is null or p_textbook_id is null or length(btrim(p_textbook_id)) = 0
     or p_idempotency_key is null or length(btrim(p_idempotency_key)) = 0
     or p_request_digest is null or octet_length(p_request_digest) <> 32
     or p_schema_version is null or p_schema_version <= 0
     or p_speaker is null or p_speaker < 0
     or p_engine_version is null or length(btrim(p_engine_version)) = 0
     or p_sentences is null or jsonb_typeof(p_sentences) <> 'array'
     or p_snapshot_sha256 is null or octet_length(p_snapshot_sha256) <> 32
     or p_snapshot_byte_length is null or p_snapshot_byte_length < 0
     or p_total is null or p_total < 0 or p_total <> jsonb_array_length(p_sentences)
     or p_configuration_available is null then
    return jsonb_build_object('category', 'invalid_argument');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || p_idempotency_key, 0));

  insert into public.tts_textbook_guards (user_id, textbook_id)
  values (p_user_id, p_textbook_id)
  on conflict (user_id, textbook_id) do nothing;
  perform 1 from public.tts_textbook_guards
   where user_id = p_user_id and textbook_id = p_textbook_id for update;

  select * into v_job from public.tts_jobs
   where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_job.request_digest <> p_request_digest then
      return jsonb_build_object('category', 'key_conflict');
    end if;
    return jsonb_build_object('category', 'replayed', 'job_id', v_job.id,
      'textbook_id', v_job.textbook_id, 'status', v_job.status, 'total', v_job.total,
      'completed', v_job.completed, 'error_code', v_job.diagnostic_error_code,
      'dispatch_generation', (select dispatch_generation from public.tts_outbox
        where job_id = v_job.id order by dispatch_generation desc limit 1));
  end if;

  if not p_configuration_available then
    return jsonb_build_object('category', 'unavailable');
  end if;
  if exists (select 1 from public.tts_jobs
      where user_id = p_user_id and textbook_id = p_textbook_id
        and status in ('queued', 'running', 'retry_wait', 'publishing')) then
    return jsonb_build_object('category', 'active_job');
  end if;

  insert into public.tts_generation_counters (user_id, textbook_id, generation)
  values (p_user_id, p_textbook_id, 1)
  on conflict (user_id, textbook_id) do update
    set generation = public.tts_generation_counters.generation + 1, updated_at = clock_timestamp()
  returning generation into v_generation;

  insert into public.tts_jobs (
    user_id, textbook_id, idempotency_key, request_digest, schema_version, speaker,
    engine_version, sentences, snapshot_sha256, snapshot_byte_length, status, total,
    idempotency_retain_until
  ) values (
    p_user_id, p_textbook_id, p_idempotency_key, p_request_digest, p_schema_version, p_speaker,
    p_engine_version, p_sentences, p_snapshot_sha256, p_snapshot_byte_length, 'queued', p_total,
    clock_timestamp() + interval '180 days'
  ) returning id into v_job_id;

  insert into public.tts_job_chunks (job_id, chunk_index)
    select v_job_id, i from generate_series(0, p_total - 1) as i;
  insert into public.tts_outbox (job_id, dispatch_generation) values (v_job_id, v_generation);
  select * into v_job from public.tts_jobs where id = v_job_id;
  return jsonb_build_object('category', 'created', 'job_id', v_job.id,
    'textbook_id', v_job.textbook_id, 'status', v_job.status, 'total', v_job.total,
    'completed', v_job.completed, 'error_code', v_job.diagnostic_error_code,
    'generation', v_generation);
exception when others then
  return jsonb_build_object('category', 'internal_error');
end;
$function$;

create or replace function public.tts_get_job_for_user(
  p_user_id uuid, p_job_id uuid
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare v_job public.tts_jobs%rowtype;
begin
  if p_user_id is null or p_job_id is null then return null; end if;
  select * into v_job from public.tts_jobs j
    where j.user_id = p_user_id and j.id = p_job_id;
  if not found then return null; end if;
  return jsonb_build_object('job_id', v_job.id, 'textbook_id', v_job.textbook_id,
    'status', v_job.status, 'total', v_job.total, 'completed', v_job.completed,
    'error_code', v_job.diagnostic_error_code);
end;
$function$;

create or replace function public.tts_claim_chunk(
  p_job_id uuid, p_chunk_index integer, p_owner text, p_lease_seconds integer
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare v_chunk public.tts_job_chunks%rowtype;
begin
  if p_job_id is null or p_chunk_index is null or p_chunk_index < 0
     or p_owner is null or length(btrim(p_owner)) = 0
     or p_lease_seconds is null or p_lease_seconds <= 0 or p_lease_seconds > 3600 then
    return jsonb_build_object('category', 'invalid_argument');
  end if;
  update public.tts_job_chunks c set status = 'running', attempt = attempt + 1,
    lease_owner = p_owner, lease_expires_at = clock_timestamp() + make_interval(secs => p_lease_seconds),
    fencing_epoch = fencing_epoch + 1, updated_at = clock_timestamp()
  from public.tts_jobs j
  where c.job_id = p_job_id and c.chunk_index = p_chunk_index and c.job_id = j.id
    and j.status in ('queued', 'running', 'retry_wait')
    and (c.status = 'queued' or (c.status = 'running' and c.lease_expires_at <= clock_timestamp()))
  returning c.* into v_chunk;
  if not found then return jsonb_build_object('category', 'not_claimable'); end if;
  return jsonb_build_object('category', 'claimed', 'job_id', v_chunk.job_id,
    'chunk_index', v_chunk.chunk_index, 'owner', v_chunk.lease_owner,
    'epoch', v_chunk.fencing_epoch, 'lease_expires_at', v_chunk.lease_expires_at);
exception when others then
  return jsonb_build_object('category', 'internal_error');
end;
$function$;

create or replace function public.tts_renew_chunk_lease(
  p_job_id uuid, p_chunk_index integer, p_owner text, p_epoch bigint, p_lease_seconds integer
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare v_expires timestamptz;
begin
  if p_job_id is null or p_chunk_index is null or p_chunk_index < 0
     or p_owner is null or length(btrim(p_owner)) = 0 or p_epoch is null or p_epoch <= 0
     or p_lease_seconds is null or p_lease_seconds <= 0 or p_lease_seconds > 3600 then
    return jsonb_build_object('category', 'invalid_argument');
  end if;
  update public.tts_job_chunks set lease_expires_at = clock_timestamp() + make_interval(secs => p_lease_seconds),
    updated_at = clock_timestamp()
  where job_id = p_job_id and chunk_index = p_chunk_index and status = 'running'
    and lease_owner = p_owner and fencing_epoch = p_epoch and lease_expires_at > clock_timestamp()
  returning lease_expires_at into v_expires;
  if not found then return jsonb_build_object('category', 'stale_lease'); end if;
  return jsonb_build_object('category', 'renewed', 'lease_expires_at', v_expires);
exception when others then
  return jsonb_build_object('category', 'internal_error');
end;
$function$;

create or replace function public.tts_complete_chunk(
  p_job_id uuid, p_chunk_index integer, p_owner text, p_epoch bigint,
  p_object_key text, p_object_sha256 bytea, p_object_byte_length bigint
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare v_rows integer;
begin
  if p_job_id is null or p_chunk_index is null or p_chunk_index < 0
     or p_owner is null or length(btrim(p_owner)) = 0 or p_epoch is null or p_epoch <= 0
     or p_object_key is null or length(btrim(p_object_key)) = 0
     or p_object_sha256 is null or octet_length(p_object_sha256) <> 32
     or p_object_byte_length is null or p_object_byte_length < 0 then
    return jsonb_build_object('category', 'invalid_argument');
  end if;
  update public.tts_job_chunks set status = 'succeeded', object_key = p_object_key,
    object_sha256 = p_object_sha256, object_byte_length = p_object_byte_length,
    object_created_at = clock_timestamp(), lease_owner = null, lease_expires_at = null,
    updated_at = clock_timestamp()
  where job_id = p_job_id and chunk_index = p_chunk_index and status = 'running'
    and lease_owner = p_owner and fencing_epoch = p_epoch and lease_expires_at > clock_timestamp();
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then return jsonb_build_object('category', 'stale_lease'); end if;
  update public.tts_jobs set completed = completed + 1, status = 'running', updated_at = clock_timestamp()
    where id = p_job_id and status in ('queued', 'running', 'retry_wait');
  return jsonb_build_object('category', 'completed');
exception when others then
  return jsonb_build_object('category', 'internal_error');
end;
$function$;

create or replace function public.tts_claim_outbox(
  p_owner text, p_limit integer, p_lease_seconds integer
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare v_rows jsonb;
begin
  if p_owner is null or length(btrim(p_owner)) = 0 or p_limit is null or p_limit <= 0 or p_limit > 100
     or p_lease_seconds is null or p_lease_seconds <= 0 or p_lease_seconds > 3600 then
    return jsonb_build_object('category', 'invalid_argument');
  end if;
  with due as (
    select id from public.tts_outbox
    where dispatched_at is null and available_at <= clock_timestamp()
      and (lease_owner is null or lease_expires_at <= clock_timestamp())
    order by available_at, id for update skip locked limit p_limit
  ), claimed as (
    update public.tts_outbox o set lease_owner = p_owner,
      lease_expires_at = clock_timestamp() + make_interval(secs => p_lease_seconds),
      fencing_epoch = fencing_epoch + 1
    from due where o.id = due.id returning o.id, o.job_id, o.dispatch_generation, o.fencing_epoch, o.lease_expires_at
  ) select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb) into v_rows from claimed;
  return jsonb_build_object('category', 'claimed', 'rows', v_rows);
exception when others then
  return jsonb_build_object('category', 'internal_error');
end;
$function$;

create or replace function public.tts_mark_outbox_sent(
  p_id uuid, p_dispatch_generation bigint, p_owner text, p_epoch bigint
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
begin
  if p_id is null or p_dispatch_generation is null or p_dispatch_generation < 0
     or p_owner is null or length(btrim(p_owner)) = 0 or p_epoch is null or p_epoch <= 0 then
    return jsonb_build_object('category', 'invalid_argument');
  end if;
  update public.tts_outbox set dispatched_at = clock_timestamp(), lease_owner = null, lease_expires_at = null
  where id = p_id and dispatch_generation = p_dispatch_generation and lease_owner = p_owner
    and fencing_epoch = p_epoch and dispatched_at is null and lease_expires_at > clock_timestamp();
  if not found then return jsonb_build_object('category', 'stale_lease'); end if;
  return jsonb_build_object('category', 'sent');
exception when others then
  return jsonb_build_object('category', 'internal_error');
end;
$function$;

create or replace function public.tts_claim_publisher(
  p_job_id uuid, p_owner text, p_lease_seconds integer
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_job public.tts_jobs%rowtype;
  v_chunk_count integer;
  v_now timestamptz;
  v_epoch bigint;
  v_expires timestamptz;
begin
  if p_job_id is null or p_owner is null or length(btrim(p_owner)) = 0
     or p_lease_seconds is null or p_lease_seconds <= 0 or p_lease_seconds > 3600 then
    return jsonb_build_object('category', 'invalid_argument');
  end if;
  select * into v_job from public.tts_jobs where id = p_job_id for update;
  if not found or v_job.status not in ('queued', 'running', 'publishing') then
    return jsonb_build_object('category', 'not_publishable');
  end if;
  select count(*) into v_chunk_count from public.tts_job_chunks
    where job_id = p_job_id and status = 'succeeded';
  if v_chunk_count <> v_job.total or exists (
    select 1 from public.tts_job_chunks where job_id = p_job_id and status <> 'succeeded'
  ) then
    return jsonb_build_object('category', 'not_publishable');
  end if;
  v_now := clock_timestamp();
  if v_job.publisher_lease_owner is not null and v_job.publisher_lease_expires_at > v_now then
    return jsonb_build_object('category', 'publisher_busy');
  end if;
  update public.tts_jobs set status = 'publishing',
    publisher_lease_owner = p_owner,
    publisher_fencing_epoch = publisher_fencing_epoch + 1,
    publisher_lease_expires_at = v_now + make_interval(secs => p_lease_seconds),
    updated_at = v_now
  where id = p_job_id
  returning publisher_fencing_epoch, publisher_lease_expires_at into v_epoch, v_expires;
  return jsonb_build_object('category', 'claimed', 'job_id', p_job_id,
    'owner', p_owner, 'epoch', v_epoch, 'lease_expires_at', v_expires);
exception when others then
  return jsonb_build_object('category', 'internal_error');
end;
$function$;

create or replace function public.tts_renew_publisher_lease(
  p_job_id uuid, p_owner text, p_epoch bigint, p_lease_seconds integer
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare v_expires timestamptz;
begin
  if p_job_id is null or p_owner is null or length(btrim(p_owner)) = 0
     or p_epoch is null or p_epoch <= 0
     or p_lease_seconds is null or p_lease_seconds <= 0 or p_lease_seconds > 3600 then
    return jsonb_build_object('category', 'invalid_argument');
  end if;
  update public.tts_jobs set publisher_lease_expires_at =
      clock_timestamp() + make_interval(secs => p_lease_seconds),
    updated_at = clock_timestamp()
  where id = p_job_id and status = 'publishing'
    and publisher_lease_owner = p_owner and publisher_fencing_epoch = p_epoch
    and publisher_lease_expires_at > clock_timestamp()
  returning publisher_lease_expires_at into v_expires;
  if not found then return jsonb_build_object('category', 'stale_publisher'); end if;
  return jsonb_build_object('category', 'renewed', 'lease_expires_at', v_expires);
exception when others then
  return jsonb_build_object('category', 'internal_error');
end;
$function$;

create or replace function public.tts_publish_manifest(
  p_job_id uuid, p_user_id uuid, p_textbook_id text, p_expected_revision bigint,
  p_publisher_owner text, p_publisher_epoch bigint,
  p_manifest_key text, p_manifest_sha256 bytea, p_manifest_byte_length bigint, p_descriptors jsonb
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_job public.tts_jobs%rowtype;
  v_current bigint;
  v_count integer;
  v_revision bigint;
begin
  if p_job_id is null or p_user_id is null or p_textbook_id is null or length(btrim(p_textbook_id)) = 0
     or p_expected_revision is null or p_expected_revision < 0
     or p_publisher_owner is null or length(btrim(p_publisher_owner)) = 0
     or p_publisher_epoch is null or p_publisher_epoch <= 0
     or p_manifest_key is null or length(btrim(p_manifest_key)) = 0
     or p_manifest_sha256 is null or octet_length(p_manifest_sha256) <> 32
     or p_manifest_byte_length is null or p_manifest_byte_length < 0
     or p_descriptors is null or jsonb_typeof(p_descriptors) <> 'array' then
    return jsonb_build_object('category', 'invalid_argument');
  end if;
  select * into v_job from public.tts_jobs where id = p_job_id for update;
  if not found or v_job.user_id <> p_user_id or v_job.textbook_id <> p_textbook_id then
    return jsonb_build_object('category', 'job_mismatch');
  end if;
  if v_job.status <> 'publishing' then
    return jsonb_build_object('category', 'not_publishable');
  end if;
  if v_job.publisher_lease_owner is distinct from p_publisher_owner
     or v_job.publisher_fencing_epoch <> p_publisher_epoch
     or v_job.publisher_lease_expires_at is null
     or v_job.publisher_lease_expires_at <= clock_timestamp() then
    return jsonb_build_object('category', 'stale_publisher');
  end if;
  perform 1 from public.tts_textbook_guards
    where user_id = p_user_id and textbook_id = p_textbook_id for update;
  if not found then return jsonb_build_object('category', 'job_mismatch'); end if;
  select manifest_revision into v_current from public.tts_manifest_heads
    where user_id = p_user_id and textbook_id = p_textbook_id for update;
  if not found then v_current := 0; end if;
  if v_current <> p_expected_revision then return jsonb_build_object('category', 'cas_conflict'); end if;

  if exists (
    select 1 from jsonb_array_elements(p_descriptors) as descriptors(d)
    where case when jsonb_typeof(d) is distinct from 'object' then true else
      jsonb_object_length(d) <> 4
      or jsonb_typeof(d->'chunk_index') is distinct from 'number'
      or (d->>'chunk_index') !~ '^(0|[1-9][0-9]*)$'
      or (d->>'chunk_index')::numeric > 2147483647
      or jsonb_typeof(d->'object_key') is distinct from 'string'
      or length(btrim(d->>'object_key')) = 0
      or jsonb_typeof(d->'sha256') is distinct from 'string'
      or (d->>'sha256') !~ '^[0-9a-fA-F]{64}$'
      or jsonb_typeof(d->'byte_length') is distinct from 'number'
      or (d->>'byte_length') !~ '^(0|[1-9][0-9]*)$'
      or (d->>'byte_length')::numeric > 9223372036854775807
    end
  ) then
    return jsonb_build_object('category', 'incomplete_manifest');
  end if;

  select count(*) into v_count from public.tts_job_chunks where job_id = p_job_id and status = 'succeeded';
  if v_count <> v_job.total or jsonb_array_length(p_descriptors) <> v_job.total
     or (select count(distinct (d->>'chunk_index')::integer)
           from jsonb_array_elements(p_descriptors) as descriptors(d)) <> v_job.total
     or exists (
       select 1 from public.tts_job_chunks c
       where c.job_id = p_job_id and c.status <> 'succeeded'
     ) or exists (
       select 1 from jsonb_array_elements(p_descriptors) as descriptors(d)
       where not exists (select 1 from public.tts_job_chunks c
         where c.job_id = p_job_id and c.chunk_index = (d->>'chunk_index')::integer
           and c.status = 'succeeded' and c.object_key = d->>'object_key'
           and encode(c.object_sha256, 'hex') = lower(d->>'sha256')
           and c.object_byte_length = (d->>'byte_length')::bigint)
     ) or exists (
       select 1 from public.tts_job_chunks c
       where c.job_id = p_job_id and c.status = 'succeeded'
         and not exists (select 1 from jsonb_array_elements(p_descriptors) as descriptors(d)
           where (d->>'chunk_index')::integer = c.chunk_index
             and c.object_key = d->>'object_key'
             and encode(c.object_sha256, 'hex') = lower(d->>'sha256')
             and c.object_byte_length = (d->>'byte_length')::bigint)
     ) then
    return jsonb_build_object('category', 'incomplete_manifest');
  end if;

  v_revision := v_current + 1;
  insert into public.tts_manifest_heads (user_id, textbook_id, manifest_revision, job_id,
      object_key, object_sha256, object_byte_length, published_at)
    values (p_user_id, p_textbook_id, v_revision, p_job_id, p_manifest_key,
      p_manifest_sha256, p_manifest_byte_length, clock_timestamp())
  on conflict (user_id, textbook_id) do update set manifest_revision = excluded.manifest_revision,
    job_id = excluded.job_id, object_key = excluded.object_key, object_sha256 = excluded.object_sha256,
    object_byte_length = excluded.object_byte_length, published_at = excluded.published_at;
  update public.tts_jobs set status = 'succeeded', terminal_at = clock_timestamp(),
    publisher_lease_owner = null, publisher_lease_expires_at = null,
    snapshot_retain_until = clock_timestamp() + interval '30 days',
    diagnostics_retain_until = clock_timestamp() + interval '180 days',
    idempotency_retain_until = greatest(idempotency_retain_until, clock_timestamp() + interval '180 days'),
    updated_at = clock_timestamp()
  where id = p_job_id;
  return jsonb_build_object('category', 'published', 'revision', v_revision);
exception when others then
  return jsonb_build_object('category', 'internal_error');
end;
$function$;

-- Candidate-only retention selectors: return identifiers for isolated validation;
-- they never mutate or delete user data. Audio uses a mark, then re-check contract.
create or replace function public.tts_snapshot_retention_candidates(p_limit integer default 100)
returns table(job_id uuid)
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'invalid candidate limit';
  end if;
  return query
    select j.id from public.tts_jobs j
    where j.status in ('succeeded', 'failed')
      and j.terminal_at <= clock_timestamp() - interval '30 days'
      and j.snapshot_retain_until <= clock_timestamp()
    order by j.snapshot_retain_until, j.id
    for update skip locked limit p_limit;
end;
$function$;

create or replace function public.tts_job_retention_candidates(p_limit integer default 100)
returns table(job_id uuid)
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'invalid candidate limit';
  end if;
  return query
    select j.id from public.tts_jobs j
    where j.status in ('succeeded', 'failed')
      and j.terminal_at <= clock_timestamp() - interval '180 days'
      and j.diagnostics_retain_until <= clock_timestamp()
      and j.idempotency_retain_until <= clock_timestamp()
    order by j.idempotency_retain_until, j.id
    for update skip locked limit p_limit;
end;
$function$;

create or replace function public.tts_mark_unreferenced_candidates(p_limit integer default 100)
returns table(job_id uuid, chunk_index integer)
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'invalid candidate limit';
  end if;
  return query
    with candidates as (
      select c.job_id, c.chunk_index from public.tts_job_chunks c
      where c.object_key is not null and c.unreferenced_confirmed_at is null
        and c.object_created_at <= clock_timestamp() - interval '5 minutes'
        and not exists (
          select 1 from public.tts_manifest_heads h
          join public.tts_jobs manifest_job
            on manifest_job.id = h.job_id
           and manifest_job.user_id = h.user_id
           and manifest_job.textbook_id = h.textbook_id
           and manifest_job.status = 'succeeded'
          join public.tts_job_chunks manifest_chunk
            on manifest_chunk.job_id = manifest_job.id
           and manifest_chunk.status = 'succeeded'
           and manifest_chunk.object_key = c.object_key
        )
      order by c.object_created_at, c.job_id, c.chunk_index
      for update skip locked limit p_limit
    ), marked as (
      update public.tts_job_chunks c set
        unreferenced_confirmed_at = clock_timestamp(), unreferenced_at = clock_timestamp(),
        object_retain_until = clock_timestamp() + interval '30 days', updated_at = clock_timestamp()
      from candidates x where c.job_id = x.job_id and c.chunk_index = x.chunk_index
      returning c.job_id, c.chunk_index
    ) select m.job_id, m.chunk_index from marked m;
end;
$function$;

create or replace function public.tts_check_audio_deletion_candidates(p_limit integer default 100)
returns table(job_id uuid, chunk_index integer, object_key text)
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'invalid candidate limit';
  end if;
  return query
    select c.job_id, c.chunk_index, c.object_key from public.tts_job_chunks c
    where c.object_key is not null
      and c.unreferenced_confirmed_at is not null
      and c.unreferenced_at <= clock_timestamp() - interval '30 days'
      and c.object_retain_until <= clock_timestamp()
      and c.object_created_at <= clock_timestamp() - interval '5 minutes'
      and not exists (
        select 1 from public.tts_manifest_heads h
        join public.tts_jobs manifest_job
          on manifest_job.id = h.job_id
         and manifest_job.user_id = h.user_id
         and manifest_job.textbook_id = h.textbook_id
         and manifest_job.status = 'succeeded'
        join public.tts_job_chunks manifest_chunk
          on manifest_chunk.job_id = manifest_job.id
         and manifest_chunk.status = 'succeeded'
         and manifest_chunk.object_key = c.object_key
      )
    order by c.object_retain_until, c.job_id, c.chunk_index
    for update skip locked limit p_limit;
end;
$function$;

revoke all on table public.tts_textbook_guards, public.tts_generation_counters,
  public.tts_jobs, public.tts_job_chunks, public.tts_outbox, public.tts_manifest_heads
  from public, anon, authenticated;

revoke all on function public.tts_snapshot_retention_candidates(integer) from public, anon, authenticated;
revoke all on function public.tts_job_retention_candidates(integer) from public, anon, authenticated;
revoke all on function public.tts_mark_unreferenced_candidates(integer) from public, anon, authenticated;
revoke all on function public.tts_check_audio_deletion_candidates(integer) from public, anon, authenticated;
grant execute on function public.tts_snapshot_retention_candidates(integer) to service_role;
grant execute on function public.tts_job_retention_candidates(integer) to service_role;
grant execute on function public.tts_mark_unreferenced_candidates(integer) to service_role;
grant execute on function public.tts_check_audio_deletion_candidates(integer) to service_role;

revoke all on function public.tts_create_job(uuid, text, text, bytea, integer, integer, text, jsonb, bytea, bigint, integer, boolean) from public, anon, authenticated;
revoke all on function public.tts_get_job_for_user(uuid, uuid) from public, anon, authenticated;
revoke all on function public.tts_claim_chunk(uuid, integer, text, integer) from public, anon, authenticated;
revoke all on function public.tts_renew_chunk_lease(uuid, integer, text, bigint, integer) from public, anon, authenticated;
revoke all on function public.tts_complete_chunk(uuid, integer, text, bigint, text, bytea, bigint) from public, anon, authenticated;
revoke all on function public.tts_claim_publisher(uuid, text, integer) from public, anon, authenticated;
revoke all on function public.tts_renew_publisher_lease(uuid, text, bigint, integer) from public, anon, authenticated;
revoke all on function public.tts_claim_outbox(text, integer, integer) from public, anon, authenticated;
revoke all on function public.tts_mark_outbox_sent(uuid, bigint, text, bigint) from public, anon, authenticated;
revoke all on function public.tts_publish_manifest(uuid, uuid, text, bigint, text, bigint, text, bytea, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.tts_create_job(uuid, text, text, bytea, integer, integer, text, jsonb, bytea, bigint, integer, boolean) to service_role;
grant execute on function public.tts_get_job_for_user(uuid, uuid) to service_role;
grant execute on function public.tts_claim_chunk(uuid, integer, text, integer) to service_role;
grant execute on function public.tts_renew_chunk_lease(uuid, integer, text, bigint, integer) to service_role;
grant execute on function public.tts_complete_chunk(uuid, integer, text, bigint, text, bytea, bigint) to service_role;
grant execute on function public.tts_claim_publisher(uuid, text, integer) to service_role;
grant execute on function public.tts_renew_publisher_lease(uuid, text, bigint, integer) to service_role;
grant execute on function public.tts_claim_outbox(text, integer, integer) to service_role;
grant execute on function public.tts_mark_outbox_sent(uuid, bigint, text, bigint) to service_role;
grant execute on function public.tts_publish_manifest(uuid, uuid, text, bigint, text, bigint, text, bytea, bigint, jsonb) to service_role;

commit;
