-- M4: durable per-question review, lesson progress and daily goals.
-- Apply in Supabase SQL Editor before deploying the API routes that use these RPCs.

create table if not exists public.question_review_state (
  user_id uuid not null references auth.users(id) on delete cascade,
  question_id text not null,
  lesson_id integer not null check (lesson_id between 1 and 24),
  repetitions integer not null default 0 check (repetitions between 0 and 5),
  lapses integer not null default 0,
  interval_days integer not null default 0,
  next_review_at timestamptz not null default now(),
  last_answered_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, question_id)
);

create index if not exists question_review_state_due_idx on public.question_review_state (user_id, next_review_at);

create table if not exists public.lesson_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  lesson_id integer not null check (lesson_id between 1 and 24),
  answered_count integer not null default 0 check (answered_count between 0 and 10),
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, lesson_id)
);

create table if not exists public.daily_learning_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  study_date date not null default (now() at time zone 'Asia/Tokyo')::date,
  new_done integer not null default 0 check (new_done between 0 and 10),
  review_done integer not null default 0 check (review_done between 0 and 5),
  minutes integer not null default 0 check (minutes between 0 and 20),
  claimed_new boolean not null default false,
  claimed_review boolean not null default false,
  claimed_time boolean not null default false,
  claimed_bonus boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, study_date)
);

alter table public.answer_attempts alter column exercise_id type text using exercise_id::text;

alter table public.question_review_state enable row level security;
alter table public.lesson_progress enable row level security;
alter table public.daily_learning_progress enable row level security;

create policy "own question review state" on public.question_review_state for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own lesson progress" on public.lesson_progress for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own daily learning progress" on public.daily_learning_progress for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.record_learning_attempt(
  p_question_id text, p_lesson_id integer, p_answer text, p_correct boolean, p_error_tags text[] default '{}', p_mode text default 'new'
) returns jsonb language plpgsql security invoker set search_path = public as $$
declare
  v_repetitions integer := 0;
  v_lapses integer := 0;
  v_interval integer := 0;
  v_next_review timestamptz := now();
  v_answered integer := 0;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  insert into public.answer_attempts (user_id, lesson_id, exercise_id, answer, verdict, error_tags)
  values (auth.uid(), p_lesson_id, p_question_id, p_answer, case when p_correct then 'correct' else 'incorrect' end, coalesce(p_error_tags,'{}'));

  select repetitions, lapses into v_repetitions, v_lapses
  from public.question_review_state where user_id = auth.uid() and question_id = p_question_id;

  if p_correct then
    v_repetitions := least(coalesce(v_repetitions, 0) + 1, 5);
    v_interval := (array[0,1,3,7,14,30])[v_repetitions + 1];
  else
    v_repetitions := 0;
    v_lapses := coalesce(v_lapses, 0) + 1;
    v_interval := 0;
  end if;
  v_next_review := now() + make_interval(days => v_interval);

  insert into public.question_review_state (user_id, question_id, lesson_id, repetitions, lapses, interval_days, next_review_at, last_answered_at, updated_at)
  values (auth.uid(), p_question_id, p_lesson_id, v_repetitions, coalesce(v_lapses,0), v_interval, v_next_review, now(), now())
  on conflict (user_id, question_id) do update set
    lesson_id = excluded.lesson_id, repetitions = excluded.repetitions, lapses = excluded.lapses,
    interval_days = excluded.interval_days, next_review_at = excluded.next_review_at,
    last_answered_at = excluded.last_answered_at, updated_at = excluded.updated_at;

  if p_mode = 'new' then
    insert into public.lesson_progress (user_id, lesson_id, answered_count, updated_at)
    values (auth.uid(), p_lesson_id, 1, now())
    on conflict (user_id, lesson_id) do update set
      answered_count = least(10, public.lesson_progress.answered_count + 1),
      completed_at = case when public.lesson_progress.answered_count + 1 >= 10 then coalesce(public.lesson_progress.completed_at, now()) else public.lesson_progress.completed_at end,
      updated_at = now()
    returning answered_count into v_answered;
  end if;

  if p_mode in ('new','review') then
    insert into public.daily_learning_progress (user_id, study_date) values (auth.uid(), (now() at time zone 'Asia/Tokyo')::date) on conflict do nothing;
    update public.daily_learning_progress set
      new_done = case when p_mode = 'new' then least(10, new_done + 1) else new_done end,
      review_done = case when p_mode = 'review' then least(5, review_done + 1) else review_done end,
      updated_at = now()
    where user_id = auth.uid() and study_date = (now() at time zone 'Asia/Tokyo')::date;
  end if;

  return jsonb_build_object('questionId',p_question_id,'repetitions',v_repetitions,'intervalDays',v_interval,'nextReviewAt',v_next_review,'lessonAnsweredCount',v_answered);
end;
$$;

create or replace function public.update_daily_learning_progress(
  p_new_delta integer default 0, p_review_delta integer default 0, p_minute_delta integer default 0, p_claim text default null
) returns jsonb language plpgsql security invoker set search_path = public as $$
declare v_row public.daily_learning_progress; v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  insert into public.daily_learning_progress (user_id, study_date) values (auth.uid(), v_today) on conflict do nothing;
  update public.daily_learning_progress set
    new_done = least(10, new_done + greatest(0,coalesce(p_new_delta,0))),
    review_done = least(5, review_done + greatest(0,coalesce(p_review_delta,0))),
    minutes = least(20, minutes + greatest(0,coalesce(p_minute_delta,0))),
    claimed_new = claimed_new or (p_claim = 'new' and new_done >= 10),
    claimed_review = claimed_review or (p_claim = 'review' and review_done >= 5),
    claimed_time = claimed_time or (p_claim = 'time' and minutes >= 20),
    claimed_bonus = claimed_bonus or (p_claim = 'bonus' and new_done >= 10 and review_done >= 5 and minutes >= 20),
    updated_at = now()
  where user_id = auth.uid() and study_date = v_today
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

grant execute on function public.record_learning_attempt(text,integer,text,boolean,text[],text) to authenticated;
grant execute on function public.update_daily_learning_progress(integer,integer,integer,text) to authenticated;
