-- Persist native answer request keys so retries cannot record an attempt twice.
-- This file is a migration source only; apply separately after review.
create table if not exists public.answer_request_idempotency (
  user_id uuid not null references auth.users(id) on delete cascade,
  client_request_id text not null check (client_request_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'),
  record jsonb,
  created_at timestamptz not null default now(),
  primary key (user_id, client_request_id)
);

alter table public.answer_request_idempotency enable row level security;

create policy "own answer request idempotency" on public.answer_request_idempotency
  for select using (auth.uid() = user_id);

revoke all on table public.answer_request_idempotency from public, anon, authenticated;

create or replace function public.record_textbook_learning_attempt_idempotent(
  p_user_id uuid,
  p_client_request_id text,
  p_textbook_id text,
  p_question_id text,
  p_lesson_id integer,
  p_answer text,
  p_correct boolean,
  p_error_tags text[],
  p_knowledge_tags text[],
  p_mode text,
  p_verdict text,
  p_lesson_question_limit integer
) returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_record jsonb;
  v_inserted boolean := false;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_user_id is null or p_user_id <> auth.uid() then raise exception 'User mismatch'; end if;
  if p_client_request_id is null or p_client_request_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then
    raise exception 'Invalid client request ID';
  end if;

  insert into public.answer_request_idempotency (user_id, client_request_id)
  values (auth.uid(), p_client_request_id)
  on conflict (user_id, client_request_id) do nothing
  returning true into v_inserted;

  if not coalesce(v_inserted, false) then
    select record into v_record
    from public.answer_request_idempotency
    where user_id = auth.uid() and client_request_id = p_client_request_id
    for update;
    if v_record is null then
      raise exception 'Answer request is still being recorded';
    end if;
    return jsonb_build_object('duplicate', true, 'record', v_record);
  end if;

  v_record := public.record_textbook_learning_attempt(
    p_textbook_id,
    p_question_id,
    p_lesson_id,
    p_answer,
    p_correct,
    p_error_tags,
    p_knowledge_tags,
    p_mode,
    p_verdict,
    p_lesson_question_limit
  );

  update public.answer_request_idempotency
  set record = v_record
  where user_id = auth.uid() and client_request_id = p_client_request_id;

  return jsonb_build_object('duplicate', false, 'record', v_record);
end;
$$;

revoke all on function public.record_textbook_learning_attempt_idempotent(
  uuid, text, text, text, integer, text, boolean, text[], text[], text, text, integer
) from public, anon, authenticated;
grant execute on function public.record_textbook_learning_attempt_idempotent(
  uuid, text, text, text, integer, text, boolean, text[], text[], text, text, integer
) to authenticated;
