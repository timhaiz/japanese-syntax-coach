-- Scope durable practice history to a textbook while mapping all existing rows
-- to the built-in course for backward compatibility.
alter table public.answer_attempts
  add column if not exists textbook_id text not null default 'builtin-japanese-syntax';
alter table public.question_review_state
  add column if not exists textbook_id text not null default 'builtin-japanese-syntax';
alter table public.lesson_progress
  add column if not exists textbook_id text not null default 'builtin-japanese-syntax';
alter table public.knowledge_point_mastery
  add column if not exists textbook_id text not null default 'builtin-japanese-syntax';
alter table public.daily_learning_progress
  add column if not exists textbook_id text not null default 'builtin-japanese-syntax';

alter table public.question_review_state drop constraint if exists question_review_state_pkey;
alter table public.question_review_state
  add constraint question_review_state_pkey primary key (user_id, textbook_id, question_id);
alter table public.lesson_progress drop constraint if exists lesson_progress_pkey;
alter table public.lesson_progress
  add constraint lesson_progress_pkey primary key (user_id, textbook_id, lesson_id);
alter table public.knowledge_point_mastery drop constraint if exists knowledge_point_mastery_pkey;
alter table public.knowledge_point_mastery
  add constraint knowledge_point_mastery_pkey primary key (user_id, textbook_id, knowledge_point);
alter table public.daily_learning_progress drop constraint if exists daily_learning_progress_pkey;
alter table public.daily_learning_progress
  add constraint daily_learning_progress_pkey primary key (user_id, study_date, textbook_id);

alter table public.lesson_progress drop constraint if exists lesson_progress_answered_count_check;
alter table public.lesson_progress
  add constraint lesson_progress_answered_count_check check (answered_count >= 0);
alter table public.lesson_progress drop constraint if exists lesson_progress_correct_count_check;
alter table public.lesson_progress
  add constraint lesson_progress_correct_count_check check (correct_count >= 0);

create index if not exists question_review_state_textbook_due_idx
  on public.question_review_state (user_id, textbook_id, next_review_at);
create index if not exists answer_attempts_textbook_created_idx
  on public.answer_attempts (user_id, textbook_id, created_at desc);

create or replace function public.record_textbook_knowledge_point_attempt(
  p_textbook_id text,
  p_question_correct boolean,
  p_error_tags text[] default '{}',
  p_knowledge_tags text[] default '{}'
) returns void language plpgsql security invoker set search_path = public as $$
declare
  tag text;
  v_correct integer;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  p_error_tags := array(
    select distinct value
    from unnest(coalesce(p_error_tags, '{}') || coalesce(p_knowledge_tags, '{}')) value
  );
  if coalesce(array_length(p_error_tags, 1), 0) = 0 then p_error_tags := array['句型']; end if;
  foreach tag in array p_error_tags loop
    v_correct := case when p_question_correct then 1 else 0 end;
    insert into public.knowledge_point_mastery
      (user_id, textbook_id, knowledge_point, attempts, correct_attempts, mastery, last_answered_at, updated_at)
    values
      (auth.uid(), p_textbook_id, tag, 1, v_correct, round(v_correct::numeric * 100, 2), now(), now())
    on conflict (user_id, textbook_id, knowledge_point) do update set
      attempts = public.knowledge_point_mastery.attempts + 1,
      correct_attempts = public.knowledge_point_mastery.correct_attempts + excluded.correct_attempts,
      mastery = round(
        ((public.knowledge_point_mastery.correct_attempts + excluded.correct_attempts)::numeric * 100)
        / greatest(1, public.knowledge_point_mastery.attempts + 1),
        2
      ),
      last_answered_at = now(),
      updated_at = now();
  end loop;
end;
$$;

create or replace function public.record_knowledge_point_attempt(
  p_question_correct boolean,
  p_error_tags text[] default '{}',
  p_knowledge_tags text[] default '{}'
) returns void language plpgsql security invoker set search_path = public as $$
begin
  perform public.record_textbook_knowledge_point_attempt(
    'builtin-japanese-syntax', p_question_correct, p_error_tags, p_knowledge_tags
  );
end;
$$;

create or replace function public.record_textbook_learning_attempt(
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
) returns jsonb language plpgsql security invoker set search_path = public as $$
declare
  v_repetitions integer := 0;
  v_lapses integer := 0;
  v_interval integer := 0;
  v_next_review timestamptz := now();
  v_answered integer := 0;
  v_correct integer := 0;
  v_limit integer := greatest(1, least(100000, coalesce(p_lesson_question_limit, 20)));
  v_verdict text := coalesce(p_verdict, case when p_correct then 'correct' else 'incorrect' end);
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_textbook_id !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' then raise exception 'Invalid textbook ID'; end if;
  if p_mode not in ('new', 'review', 'mistakes', 'lesson', 'lesson_replay') then raise exception 'Invalid learning mode'; end if;
  if v_verdict not in ('correct', 'mostly_correct', 'needs_fix', 'incorrect') then
    v_verdict := case when p_correct then 'correct' else 'incorrect' end;
  end if;

  insert into public.answer_attempts (user_id, textbook_id, lesson_id, exercise_id, answer, verdict, error_tags)
  values (auth.uid(), p_textbook_id, p_lesson_id, p_question_id, p_answer, v_verdict, coalesce(p_error_tags, '{}'));

  select repetitions, lapses into v_repetitions, v_lapses
  from public.question_review_state
  where user_id = auth.uid() and textbook_id = p_textbook_id and question_id = p_question_id;

  if v_verdict = 'correct' then
    v_repetitions := least(coalesce(v_repetitions, 0) + 1, 5);
    v_interval := (array[0, 1, 3, 7, 14, 30])[v_repetitions + 1];
  elsif v_verdict = 'mostly_correct' then
    v_repetitions := least(coalesce(v_repetitions, 0) + 1, 5);
    v_interval := (array[0, 1, 2, 4, 7, 14])[v_repetitions + 1];
  elsif v_verdict = 'needs_fix' then
    v_repetitions := least(coalesce(v_repetitions, 0), 5);
    v_interval := (array[0, 0, 1, 3, 7, 14])[v_repetitions + 1];
  else
    v_repetitions := 0;
    v_lapses := coalesce(v_lapses, 0) + 1;
    v_interval := 0;
  end if;
  v_next_review := now() + make_interval(days => v_interval);

  insert into public.question_review_state
    (user_id, textbook_id, question_id, lesson_id, repetitions, lapses, interval_days, next_review_at, last_answered_at, updated_at)
  values
    (auth.uid(), p_textbook_id, p_question_id, p_lesson_id, v_repetitions, coalesce(v_lapses, 0), v_interval, v_next_review, now(), now())
  on conflict (user_id, textbook_id, question_id) do update set
    lesson_id = excluded.lesson_id,
    repetitions = excluded.repetitions,
    lapses = excluded.lapses,
    interval_days = excluded.interval_days,
    next_review_at = excluded.next_review_at,
    last_answered_at = excluded.last_answered_at,
    updated_at = excluded.updated_at;

  if p_mode in ('new', 'lesson') then
    insert into public.lesson_progress
      (user_id, textbook_id, lesson_id, answered_count, correct_count, updated_at)
    values
      (auth.uid(), p_textbook_id, p_lesson_id, 1, case when p_correct then 1 else 0 end, now())
    on conflict (user_id, textbook_id, lesson_id) do update set
      answered_count = least(v_limit, public.lesson_progress.answered_count + 1),
      correct_count = least(v_limit, public.lesson_progress.correct_count + case when p_correct then 1 else 0 end),
      completed_at = case
        when public.lesson_progress.answered_count + 1 >= v_limit
          and (public.lesson_progress.correct_count + case when p_correct then 1 else 0 end)::numeric
            / greatest(1, public.lesson_progress.answered_count + 1) >= 0.9
        then coalesce(public.lesson_progress.completed_at, now())
        else public.lesson_progress.completed_at
      end,
      updated_at = now()
    returning answered_count, correct_count into v_answered, v_correct;
  elsif p_mode = 'lesson_replay' then
    update public.lesson_progress set
      correct_count = least(v_limit, correct_count + case when p_correct then 1 else 0 end),
      completed_at = case
        when correct_count + case when p_correct then 1 else 0 end >= ceil(v_limit * 0.9)
        then coalesce(completed_at, now())
        else completed_at
      end,
      updated_at = now()
    where user_id = auth.uid() and textbook_id = p_textbook_id and lesson_id = p_lesson_id
    returning answered_count, correct_count into v_answered, v_correct;
  end if;

  if p_mode in ('new', 'review') then
    insert into public.daily_learning_progress (user_id, study_date, textbook_id)
    values (auth.uid(), (now() at time zone 'Asia/Tokyo')::date, p_textbook_id)
    on conflict (user_id, study_date, textbook_id) do nothing;
    update public.daily_learning_progress set
      new_done = case when p_mode = 'new' then least(10, new_done + 1) else new_done end,
      review_done = case when p_mode = 'review' then least(5, review_done + 1) else review_done end,
      updated_at = now()
    where user_id = auth.uid()
      and study_date = (now() at time zone 'Asia/Tokyo')::date
      and textbook_id = p_textbook_id;
  end if;

  perform public.record_textbook_knowledge_point_attempt(
    p_textbook_id, p_correct, p_error_tags, p_knowledge_tags
  );
  return jsonb_build_object(
    'questionId', p_question_id,
    'textbookId', p_textbook_id,
    'repetitions', v_repetitions,
    'intervalDays', v_interval,
    'nextReviewAt', v_next_review,
    'lessonAnsweredCount', v_answered,
    'lessonCorrectCount', v_correct
  );
end;
$$;

drop function if exists public.record_learning_attempt(text, integer, text, boolean, text[], text);
drop function if exists public.record_learning_attempt(text, integer, text, boolean, text[], text, text);
create function public.record_learning_attempt(
  p_question_id text,
  p_lesson_id integer,
  p_answer text,
  p_correct boolean,
  p_error_tags text[] default '{}',
  p_mode text default 'new',
  p_verdict text default null
) returns jsonb language plpgsql security invoker set search_path = public as $$
begin
  return public.record_textbook_learning_attempt(
    'builtin-japanese-syntax',
    p_question_id,
    p_lesson_id,
    p_answer,
    p_correct,
    p_error_tags,
    '{}',
    p_mode,
    p_verdict,
    20
  );
end;
$$;

drop function if exists public.update_daily_learning_progress(integer, integer, integer, text);
create function public.update_daily_learning_progress(
  p_new_delta integer,
  p_review_delta integer,
  p_minute_delta integer,
  p_claim text,
  p_textbook_id text
) returns jsonb language plpgsql security invoker set search_path = public as $$
declare
  v_row public.daily_learning_progress;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  insert into public.daily_learning_progress (user_id, study_date, textbook_id)
  values (auth.uid(), v_today, p_textbook_id)
  on conflict (user_id, study_date, textbook_id) do nothing;
  update public.daily_learning_progress set
    new_done = least(10, new_done + greatest(0, coalesce(p_new_delta, 0))),
    review_done = least(5, review_done + greatest(0, coalesce(p_review_delta, 0))),
    minutes = least(20, minutes + greatest(0, coalesce(p_minute_delta, 0))),
    claimed_new = claimed_new or (p_claim = 'new' and new_done >= 10),
    claimed_review = claimed_review or (p_claim = 'review' and review_done >= 5),
    claimed_time = claimed_time or (p_claim = 'time' and minutes >= 20),
    claimed_bonus = claimed_bonus or (p_claim = 'bonus' and new_done >= 10 and review_done >= 5 and minutes >= 20),
    updated_at = now()
  where user_id = auth.uid() and study_date = v_today and textbook_id = p_textbook_id
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

create function public.update_daily_learning_progress(
  p_new_delta integer default 0,
  p_review_delta integer default 0,
  p_minute_delta integer default 0,
  p_claim text default null
) returns jsonb language plpgsql security invoker set search_path = public as $$
begin
  return public.update_daily_learning_progress(
    p_new_delta, p_review_delta, p_minute_delta, p_claim, 'builtin-japanese-syntax'
  );
end;
$$;

grant execute on function public.record_textbook_learning_attempt(text, text, integer, text, boolean, text[], text[], text, text, integer) to authenticated;
grant execute on function public.record_textbook_knowledge_point_attempt(text, boolean, text[], text[]) to authenticated;
grant execute on function public.record_learning_attempt(text, integer, text, boolean, text[], text, text) to authenticated;
grant execute on function public.update_daily_learning_progress(integer, integer, integer, text, text) to authenticated;
grant execute on function public.update_daily_learning_progress(integer, integer, integer, text) to authenticated;
