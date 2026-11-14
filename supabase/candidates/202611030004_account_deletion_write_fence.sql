-- REVIEW CANDIDATE ONLY: do not apply or enable without an integration, rollout,
-- concurrency verification, authorization and recovery plan. No callers use it.
-- All writers for an identity must register BEFORE any side effect, wait for the
-- transaction commit, and finish only after the external write is definitively
-- quiescent. Unknown outcomes remain unfinished, indefinitely blocking deletion.
-- A database token cannot stop an already-started external write. The epoch is a
-- fencing token only where the destination atomically checks it at mutation time;
-- most external storage does not. Such storage requires a proven drain/quiescence
-- protocol (including retries, queued work and timeouts), or deletion stays disabled.
-- Never infer quiescence from process death, timeout, or a lost acknowledgement.
-- Callers authenticate the identity independently; service-role access is not auth.
-- Never reuse write IDs, even after completion. Retain both tables permanently;
-- deleting or resetting rows would invalidate the fencing and replay guarantees.

-- Keep the exception inside an explicit transaction so clients that continue
-- after errors cannot execute or commit the candidate DDL.
begin;
do $$
begin
  raise exception 'review candidate only: deployment is disabled';
end;
$$;

create table public.account_write_fence_identities (
  identity text primary key check (length(identity) between 1 and 512),
  epoch bigint not null default 0 check (epoch >= 0),
  deletion_id text check (deletion_id is null or length(deletion_id) between 1 and 512)
);

create table public.account_write_fence_writes (
  identity text not null references public.account_write_fence_identities(identity),
  write_id text not null check (length(write_id) between 1 and 512),
  epoch bigint not null check (epoch >= 0),
  finished boolean not null default false,
  primary key (identity, write_id)
);

revoke all on table public.account_write_fence_identities, public.account_write_fence_writes from public, anon, authenticated;

-- Duplicate write IDs fail, including after a lost response: callers must not
-- interpret the error as permission to issue a write or silently retry it.
create function public.account_write_fence_begin_write(p_identity text, p_write_id text)
returns text language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_row public.account_write_fence_identities%rowtype;
begin
  if p_identity is null or length(p_identity) not between 1 and 512 or p_write_id is null or length(p_write_id) not between 1 and 512 then
    raise exception 'invalid fence input';
  end if;
  insert into public.account_write_fence_identities(identity) values (p_identity) on conflict do nothing;
  select * into strict v_row from public.account_write_fence_identities where identity = p_identity for update;
  if v_row.deletion_id is not null then raise exception 'deletion fence closed'; end if;
  insert into public.account_write_fence_writes(identity, write_id, epoch) values (p_identity, p_write_id, v_row.epoch);
  return v_row.epoch::text;
end;
$$;

-- First call closes admission immediately, even if it returns false. The same
-- deletion ID may poll; another ID is rejected forever. True means registered
-- writes finished, not that unregistered or external writes are impossible.
create function public.account_write_fence_begin_deletion(p_identity text, p_deletion_id text)
returns boolean language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_row public.account_write_fence_identities%rowtype;
begin
  if p_identity is null or length(p_identity) not between 1 and 512 or p_deletion_id is null or length(p_deletion_id) not between 1 and 512 then
    raise exception 'invalid fence input';
  end if;
  insert into public.account_write_fence_identities(identity) values (p_identity) on conflict do nothing;
  select * into strict v_row from public.account_write_fence_identities where identity = p_identity for update;
  if v_row.deletion_id is null then
    update public.account_write_fence_identities set deletion_id = p_deletion_id, epoch = epoch + 1 where identity = p_identity;
  elsif v_row.deletion_id is distinct from p_deletion_id then
    raise exception 'different deletion already owns fence';
  end if;
  return not exists (select 1 from public.account_write_fence_writes where identity = p_identity and finished = false);
end;
$$;

-- Only call after definitive quiescence, not merely on timeout or error. The
-- original epoch remains valid for completion after deletion closes admission.
create function public.account_write_fence_finish_write(p_identity text, p_write_id text, p_epoch bigint)
returns boolean language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  perform 1 from public.account_write_fence_identities where identity = p_identity for update;
  if not found then return false; end if;
  update public.account_write_fence_writes set finished = true
    where identity = p_identity and write_id = p_write_id and epoch = p_epoch;
  return found;
end;
$$;

revoke all on function public.account_write_fence_begin_write(text, text) from public, anon, authenticated;
grant execute on function public.account_write_fence_begin_write(text, text) to service_role;
revoke all on function public.account_write_fence_begin_deletion(text, text) from public, anon, authenticated;
grant execute on function public.account_write_fence_begin_deletion(text, text) to service_role;
revoke all on function public.account_write_fence_finish_write(text, text, bigint) from public, anon, authenticated;
grant execute on function public.account_write_fence_finish_write(text, text, bigint) to service_role;

commit;
