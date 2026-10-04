-- Custom textbooks may contain more than the built-in 24 lessons.
-- Keep lesson IDs positive while removing the built-in course upper bound.
do $$
declare
  table_name text;
  constraint_name text;
begin
  for table_name, constraint_name in
    select rel.relname, con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace ns on ns.oid = rel.relnamespace
    where ns.nspname = 'public'
      and rel.relname in ('question_review_state', 'lesson_progress')
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%lesson_id%'
      and pg_get_constraintdef(con.oid) ilike '%24%'
  loop
    execute format('alter table public.%I drop constraint if exists %I', table_name, constraint_name);
  end loop;
end;
$$;

alter table public.question_review_state
  drop constraint if exists question_review_state_lesson_id_check;
alter table public.lesson_progress
  drop constraint if exists lesson_progress_lesson_id_check;

alter table public.question_review_state
  add constraint question_review_state_lesson_id_positive check (lesson_id > 0);
alter table public.lesson_progress
  add constraint lesson_progress_lesson_id_positive check (lesson_id > 0);
