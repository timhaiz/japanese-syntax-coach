-- The app uses 20-question lessons; align the legacy constraint from M4.
alter table public.lesson_progress drop constraint if exists lesson_progress_answered_count_check;
alter table public.lesson_progress add constraint lesson_progress_answered_count_check check (answered_count between 0 and 20);
