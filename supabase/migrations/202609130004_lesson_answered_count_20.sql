-- Course practice is 20 questions; remove any legacy 10-question constraint.
alter table public.lesson_progress drop constraint if exists lesson_progress_answered_count_check;
update public.lesson_progress
set answered_count = least(greatest(coalesce(answered_count, 0), 0), 20),
    correct_count = least(greatest(coalesce(correct_count, 0), 0), least(greatest(coalesce(answered_count, 0), 0), 20)),
    updated_at = now()
where answered_count < 0
   or answered_count > 20
   or correct_count < 0
   or correct_count > answered_count;
alter table public.lesson_progress add constraint lesson_progress_answered_count_check check (answered_count between 0 and 20);
