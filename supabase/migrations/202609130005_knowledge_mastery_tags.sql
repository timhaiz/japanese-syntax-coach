-- Upgrade existing installations without relying on edits to an older migration.
drop function if exists public.record_knowledge_point_attempt(boolean, text[]);
create or replace function public.record_knowledge_point_attempt(
  p_question_correct boolean,
  p_error_tags text[] default '{}',
  p_knowledge_tags text[] default '{}'
) returns void language plpgsql security invoker set search_path = public as $$
declare tag text; v_correct integer;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  p_error_tags := array(select distinct value from unnest(coalesce(p_error_tags,'{}') || coalesce(p_knowledge_tags,'{}')) value);
  if coalesce(array_length(p_error_tags, 1), 0) = 0 then p_error_tags := array['句型']; end if;
  foreach tag in array p_error_tags loop
    v_correct := case when p_question_correct then 1 else 0 end;
    insert into public.knowledge_point_mastery(user_id, knowledge_point, attempts, correct_attempts, mastery, last_answered_at, updated_at)
    values (auth.uid(), tag, 1, v_correct, round(v_correct::numeric * 100, 2), now(), now())
    on conflict (user_id, knowledge_point) do update set
      attempts = public.knowledge_point_mastery.attempts + 1,
      correct_attempts = public.knowledge_point_mastery.correct_attempts + excluded.correct_attempts,
      mastery = round(((public.knowledge_point_mastery.correct_attempts + excluded.correct_attempts)::numeric * 100) / greatest(1, public.knowledge_point_mastery.attempts + 1), 2),
      last_answered_at = now(), updated_at = now();
  end loop;
end; $$;
grant execute on function public.record_knowledge_point_attempt(boolean, text[], text[]) to authenticated;
