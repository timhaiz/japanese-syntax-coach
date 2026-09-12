-- Retrying a lesson's existing mistakes must not inflate answered_count.
-- It still records the attempt and moves the question's spaced-review schedule.
create or replace function public.record_learning_attempt(
  p_question_id text, p_lesson_id integer, p_answer text, p_correct boolean,
  p_error_tags text[] default '{}', p_mode text default 'new'
) returns jsonb language plpgsql security invoker set search_path = public as $$
declare
  v_repetitions integer := 0;
  v_lapses integer := 0;
  v_interval integer := 0;
  v_next_review timestamptz := now();
  v_answered integer := 0;
  v_correct integer := 0;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_mode not in ('new', 'review', 'mistakes', 'lesson', 'lesson_replay') then
    raise exception 'Invalid learning mode';
  end if;

  insert into public.answer_attempts (user_id, lesson_id, exercise_id, answer, verdict, error_tags)
  values (auth.uid(), p_lesson_id, p_question_id, p_answer,
    case when p_correct then 'correct' else 'incorrect' end, coalesce(p_error_tags, '{}'));

  select repetitions, lapses into v_repetitions, v_lapses
  from public.question_review_state where user_id = auth.uid() and question_id = p_question_id;
  if p_correct then
    v_repetitions := least(coalesce(v_repetitions, 0) + 1, 5);
    v_interval := (array[0, 1, 3, 7, 14, 30])[v_repetitions + 1];
  else
    v_repetitions := 0;
    v_lapses := coalesce(v_lapses, 0) + 1;
    v_interval := 0;
  end if;
  v_next_review := now() + make_interval(days => v_interval);

  insert into public.question_review_state
    (user_id, question_id, lesson_id, repetitions, lapses, interval_days, next_review_at, last_answered_at, updated_at)
  values (auth.uid(), p_question_id, p_lesson_id, v_repetitions, coalesce(v_lapses, 0), v_interval, v_next_review, now(), now())
  on conflict (user_id, question_id) do update set
    lesson_id = excluded.lesson_id, repetitions = excluded.repetitions, lapses = excluded.lapses,
    interval_days = excluded.interval_days, next_review_at = excluded.next_review_at,
    last_answered_at = excluded.last_answered_at, updated_at = excluded.updated_at;

  if p_mode in ('new', 'lesson') then
    insert into public.lesson_progress (user_id, lesson_id, answered_count, correct_count, updated_at)
    values (auth.uid(), p_lesson_id, 1, case when p_correct then 1 else 0 end, now())
    on conflict (user_id, lesson_id) do update set
      answered_count = least(100, public.lesson_progress.answered_count + 1),
      correct_count = least(100, public.lesson_progress.correct_count + case when p_correct then 1 else 0 end),
      completed_at = case
        when public.lesson_progress.answered_count + 1 >= 20
         and (public.lesson_progress.correct_count + case when p_correct then 1 else 0 end)::numeric
             / greatest(1, public.lesson_progress.answered_count + 1) >= 0.9
        then coalesce(public.lesson_progress.completed_at, now())
        else public.lesson_progress.completed_at end,
      updated_at = now()
    returning answered_count, correct_count into v_answered, v_correct;
  elsif p_mode = 'lesson_replay' then
    update public.lesson_progress set
      correct_count = least(answered_count, correct_count + case when p_correct then 1 else 0 end),
      completed_at = case
        when correct_count + case when p_correct then 1 else 0 end >= 18
        then coalesce(completed_at, now())
        else completed_at end,
      updated_at = now()
    where user_id = auth.uid() and lesson_id = p_lesson_id
    returning answered_count, correct_count into v_answered, v_correct;
  end if;

  if p_mode in ('new', 'review') then
    insert into public.daily_learning_progress (user_id, study_date)
      values (auth.uid(), (now() at time zone 'Asia/Tokyo')::date) on conflict do nothing;
    update public.daily_learning_progress set
      new_done = case when p_mode = 'new' then least(10, new_done + 1) else new_done end,
      review_done = case when p_mode = 'review' then least(5, review_done + 1) else review_done end,
      updated_at = now()
    where user_id = auth.uid() and study_date = (now() at time zone 'Asia/Tokyo')::date;
  end if;
  return jsonb_build_object('questionId', p_question_id, 'repetitions', v_repetitions,
    'intervalDays', v_interval, 'nextReviewAt', v_next_review,
    'lessonAnsweredCount', v_answered, 'lessonCorrectCount', v_correct);
end;
$$;

grant execute on function public.record_learning_attempt(text, integer, text, boolean, text[], text) to authenticated;
