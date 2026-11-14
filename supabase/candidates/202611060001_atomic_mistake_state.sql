-- Candidate only. Built-in textbook state is authoritative after initialization.
-- No client timestamp participates in conflict resolution.
create table public.mistake_state (
  user_id uuid not null references auth.users(id) on delete cascade,
  textbook_id text not null check (textbook_id = 'builtin-japanese-syntax'),
  question_id text not null check (question_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'),
  is_mistake boolean not null,
  version bigint not null check (version > 0),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, textbook_id, question_id)
);
alter table public.mistake_state enable row level security;
create policy mistake_state_select_own on public.mistake_state for select to authenticated using (auth.uid() = user_id);
revoke all on public.mistake_state from public, anon, authenticated;
grant select on public.mistake_state to authenticated;

-- Private once-only migration authority. User metadata is client-writable and is
-- never treated as a migration marker.
create table public.mistake_state_migrations (
  user_id uuid not null references auth.users(id) on delete cascade,
  textbook_id text not null check (textbook_id = 'builtin-japanese-syntax'),
  migrated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, textbook_id)
);
alter table public.mistake_state_migrations enable row level security;
revoke all on public.mistake_state_migrations from public, anon, authenticated;

create table public.mistake_state_operations (
  user_id uuid not null references auth.users(id) on delete cascade,
  operation_id text not null check (operation_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'),
  payload jsonb not null,
  result jsonb,
  created_at timestamptz not null default clock_timestamp(),
  primary key (user_id, operation_id)
);
alter table public.mistake_state_operations enable row level security;
create policy mistake_state_operations_select_own on public.mistake_state_operations for select to authenticated using (auth.uid() = user_id);
revoke all on public.mistake_state_operations from public, anon, authenticated;
grant select on public.mistake_state_operations to authenticated;

-- Internal initializer. The auth.users row lock serializes concurrent first reads.
create function public._initialize_mistake_state(p_user uuid)
returns void language plpgsql security definer set search_path = pg_catalog, public, auth as $$
declare
  u auth.users%rowtype;
  root jsonb;
  metadata jsonb;
  scoped jsonb;
  snap jsonb;
  item jsonb;
  qid text;
  seen text[] := '{}';
begin
  select * into u from auth.users where id = p_user for no key update;
  if not found then raise exception 'Unknown user' using errcode='22023'; end if;
  if exists (select 1 from public.mistake_state_migrations where user_id=p_user and textbook_id='builtin-japanese-syntax') then return; end if;
  metadata := coalesce(u.raw_user_meta_data, '{}'::jsonb);
  root := metadata->'learning_progress';
  if metadata ? 'learning_progress' and jsonb_typeof(root) is distinct from 'object' then
    raise exception 'Unsupported legacy mistake snapshot' using errcode='22023';
  end if;
  if root is null then root := metadata; end if;
  if root ? 'byTextbook' then
    if jsonb_typeof(root->'byTextbook') is distinct from 'object' then
      raise exception 'Unsupported legacy mistake snapshot' using errcode='22023';
    end if;
    scoped := root #> '{byTextbook,builtin-japanese-syntax}';
  elsif metadata ? 'learning_progress'
    and not (root ?| array['lessonDone','lessonCorrect','completedLessons','mistakes','updatedAt','version'])
    and exists (select 1 from jsonb_object_keys(root)) then
    raise exception 'Unsupported legacy mistake snapshot' using errcode='22023';
  end if;
  if scoped is not null then
    snap := scoped;
  elsif root ?| array['lessonDone','lessonCorrect','completedLessons','mistakes','updatedAt','version'] then
    -- Matches the existing client fallback: use root snapshot if no scoped value.
    snap := root;
  else
    snap := null;
  end if;
  if snap is not null then
    if jsonb_typeof(snap) is distinct from 'object'
       or jsonb_typeof(snap->'version') is distinct from 'number'
       or snap->>'version' not in ('2','3')
       or jsonb_typeof(snap->'lessonDone') is distinct from 'object'
       or jsonb_typeof(snap->'lessonCorrect') is distinct from 'object'
       or jsonb_typeof(snap->'completedLessons') is distinct from 'array'
       or jsonb_typeof(snap->'mistakes') is distinct from 'array'
       or jsonb_typeof(snap->'updatedAt') is distinct from 'string' then
      raise exception 'Unsupported legacy mistake snapshot' using errcode='22023';
    end if;
    for item in select value from jsonb_array_elements(snap->'mistakes') loop
      if jsonb_typeof(item) is distinct from 'object' or jsonb_typeof(item->'id') is distinct from 'string' then
        raise exception 'Unsupported legacy mistake entry' using errcode='22023';
      end if;
      qid := item->>'id';
      if qid !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' or qid = any(seen) then
        raise exception 'Unsupported legacy mistake entry' using errcode='22023';
      end if;
      seen := array_append(seen, qid);
    end loop;
    foreach qid in array seen loop
      insert into public.mistake_state(user_id,textbook_id,question_id,is_mistake,version)
      values (p_user,'builtin-japanese-syntax',qid,true,1) on conflict do nothing;
    end loop;
  end if;
  insert into public.mistake_state_migrations(user_id,textbook_id) values(p_user,'builtin-japanese-syntax') on conflict do nothing;
end $$;
revoke all on function public._initialize_mistake_state(uuid) from public, anon, authenticated;

create function public.get_textbook_mistake_state_v1(p_textbook_id text default 'builtin-japanese-syntax')
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'Not authenticated'; end if;
  if p_textbook_id is distinct from 'builtin-japanese-syntax' then raise exception 'Unsupported textbook'; end if;
  perform public._initialize_mistake_state(u);
  return coalesce((select jsonb_agg(jsonb_build_object('questionId',question_id,'isMistake',is_mistake,'version',version) order by question_id)
    from public.mistake_state where user_id=u and textbook_id=p_textbook_id), '[]'::jsonb);
end $$;

-- p_expected_version is 0 for a question with no row. State transitions are CAS.
-- mode is the existing learning-attempt mode; p_correct=false always adds, while
-- correct only removes in mistakes/lesson_replay. Other correct answers preserve state.
create function public.record_textbook_answer_with_mistakes_v1(
  p_operation_id text, p_textbook_id text, p_question_id text,
  p_expected_version bigint, p_correct boolean, p_mode text,
  p_lesson_id integer, p_answer text, p_error_tags text[] default '{}',
  p_knowledge_tags text[] default '{}', p_verdict text default null,
  p_lesson_question_limit integer default 20
) returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  u uuid := auth.uid(); payload jsonb; prior jsonb; prior_result jsonb;
  current_version bigint := 0; next_mistake boolean; answer_result jsonb;
begin
  if u is null then raise exception 'Not authenticated'; end if;
  if p_textbook_id is distinct from 'builtin-japanese-syntax' then raise exception 'Unsupported textbook'; end if;
  if p_question_id is null or p_question_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then raise exception 'Invalid question ID'; end if;
  if p_operation_id is null or p_operation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then raise exception 'Invalid operation ID'; end if;
  if p_expected_version is null or p_expected_version < 0 then raise exception 'Invalid expected version'; end if;
  if p_mode is null or p_mode not in ('new','review','mistakes','lesson','lesson_replay') then raise exception 'Invalid mode'; end if;
  if p_correct is null then raise exception 'Invalid correctness value'; end if;
  if length(coalesce(p_answer,'')) > 4096 or coalesce(cardinality(p_error_tags),0) > 64 or coalesce(cardinality(p_knowledge_tags),0) > 64 then raise exception 'Input limit exceeded'; end if;
  if exists(select 1 from unnest(coalesce(p_error_tags,'{}') || coalesce(p_knowledge_tags,'{}')) as t(tag) where length(tag) > 128) then raise exception 'Tag limit exceeded'; end if;
  payload := jsonb_build_object('textbookId',p_textbook_id,'questionId',p_question_id,'expectedVersion',p_expected_version,'correct',p_correct,'mode',p_mode,'lessonId',p_lesson_id,'answer',p_answer,'errorTags',coalesce(to_jsonb(p_error_tags),'[]'::jsonb),'knowledgeTags',coalesce(to_jsonb(p_knowledge_tags),'[]'::jsonb),'verdict',p_verdict,'lessonQuestionLimit',p_lesson_question_limit);
  insert into public.mistake_state_operations(user_id,operation_id,payload) values (u,p_operation_id,payload) on conflict do nothing;
  if not found then
    select o.payload,o.result into prior,prior_result from public.mistake_state_operations as o where o.user_id=u and o.operation_id=p_operation_id for update;
    if prior <> payload then raise exception 'Operation ID reused with different payload'; end if;
    if prior_result is null then raise exception 'Operation is incomplete'; end if;
    return prior_result || jsonb_build_object('duplicate',true);
  end if;
  perform public._initialize_mistake_state(u);
  select version,is_mistake into current_version,next_mistake from public.mistake_state where user_id=u and textbook_id=p_textbook_id and question_id=p_question_id for update;
  current_version := coalesce(current_version,0);
  if current_version <> p_expected_version then raise exception 'Version conflict: expected %, current %',p_expected_version,current_version using errcode='40001'; end if;
  answer_result := public.record_textbook_learning_attempt(p_textbook_id,p_question_id,p_lesson_id,p_answer,p_correct,p_error_tags,p_knowledge_tags,p_mode,p_verdict,p_lesson_question_limit);
  next_mistake := case when not p_correct then true when p_mode in ('mistakes','lesson_replay') then false else coalesce(next_mistake,false) end;
  insert into public.mistake_state(user_id,textbook_id,question_id,is_mistake,version)
  values(u,p_textbook_id,p_question_id,next_mistake,current_version+1)
  on conflict(user_id,textbook_id,question_id) do update set is_mistake=excluded.is_mistake,version=excluded.version,updated_at=clock_timestamp();
  prior_result := jsonb_build_object('duplicate',false,'answer',answer_result,'questionId',p_question_id,'isMistake',next_mistake,'version',current_version+1);
  update public.mistake_state_operations set result=prior_result where user_id=u and operation_id=p_operation_id;
  return prior_result;
end $$;

revoke all on function public.get_textbook_mistake_state_v1(text) from public, anon;
revoke all on function public.record_textbook_answer_with_mistakes_v1(text,text,text,bigint,boolean,text,integer,text,text[],text[],text,integer) from public, anon;
grant execute on function public.get_textbook_mistake_state_v1(text) to authenticated;
grant execute on function public.record_textbook_answer_with_mistakes_v1(text,text,text,bigint,boolean,text,integer,text,text[],text[],text,integer) to authenticated;
