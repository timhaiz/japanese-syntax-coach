\set ON_ERROR_STOP on
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create schema auth;
create table auth.users(id uuid primary key, raw_user_meta_data jsonb);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to public;
grant execute on function auth.uid() to public;
grant select,update on auth.users to public;
create table public.answer_attempts(user_id uuid,textbook_id text,lesson_id integer,exercise_id text,answer text,verdict text,error_tags text[]);
create table public.question_review_state(user_id uuid,textbook_id text,question_id text,repetitions integer,lapses integer,interval_days integer,next_review_at timestamptz,last_answered_at timestamptz,updated_at timestamptz,lesson_id integer,primary key(user_id,textbook_id,question_id));
create table public.lesson_progress(user_id uuid,textbook_id text,lesson_id integer,answered_count integer default 0,correct_count integer default 0,completed_at timestamptz,updated_at timestamptz,primary key(user_id,textbook_id,lesson_id));
create table public.knowledge_point_mastery(user_id uuid,textbook_id text,knowledge_point text,attempts integer default 0,correct_attempts integer default 0,mastery numeric,last_answered_at timestamptz,updated_at timestamptz,primary key(user_id,textbook_id,knowledge_point));
create table public.daily_learning_progress(user_id uuid,study_date date,textbook_id text,new_done integer default 0,review_done integer default 0,minutes integer default 0,claimed_new boolean default false,claimed_review boolean default false,claimed_time boolean default false,claimed_bonus boolean default false,updated_at timestamptz,primary key(user_id,study_date,textbook_id));
create function public.record_textbook_learning_attempt(text,text,integer,text,boolean,text[],text[],text,text,integer) returns jsonb language plpgsql as $$ begin if current_setting('lab.fail',true)='yes' then raise exception 'stub failure'; end if; insert into answer_attempts values(auth.uid(),$1,$3,$2,$4,coalesce($9,case when $5 then 'correct' else 'incorrect' end),coalesce($6,'{}')); return jsonb_build_object('questionId',$2); end $$;
\ir /tmp/mistake-state-candidate.sql
insert into auth.users values
('00000000-0000-0000-0000-000000000001','{"learning_progress":{"version":3,"lessonDone":{},"lessonCorrect":{},"completedLessons":[],"mistakes":[{"id":"q-legacy"}],"updatedAt":"x"},"keep":7}'),
('00000000-0000-0000-0000-000000000002','{}'),
('00000000-0000-0000-0000-000000000003','{"learning_progress":{"version":99,"lessonDone":{},"lessonCorrect":{},"completedLessons":[],"mistakes":[{"id":"q-protected"}],"updatedAt":"x"},"keep":9}'),
('00000000-0000-0000-0000-000000000004','{"learning_progress":{"version":3,"lessonDone":[],"lessonCorrect":{},"completedLessons":[],"mistakes":[{"id":"q-malformed"}],"updatedAt":"x"},"keep":11}'),
('00000000-0000-0000-0000-000000000005','{"learning_progress":{"version":3,"lessonDone":{},"lessonCorrect":{},"completedLessons":[],"mistakes":[{"id":"q-root-fallback"}],"updatedAt":"x","byTextbook":{"other-textbook":{"version":3}}}}'),
('00000000-0000-0000-0000-000000000006','{"learning_progress":{"unexpected":"shape"}}');
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
select public.get_textbook_mistake_state_v1();
do $$ begin
  if not exists(select 1 from public.mistake_state where question_id='q-legacy' and is_mistake) then raise exception 'legacy import failed'; end if;
  if not exists(select 1 from public.mistake_state_migrations where user_id=auth.uid()) then raise exception 'migration marker missing'; end if;
end $$;
select public.record_textbook_answer_with_mistakes_v1('op-legacy-clear','builtin-japanese-syntax','q-legacy',1,true,'mistakes',1,'ok');
do $$ begin if (select is_mistake from public.mistake_state where question_id='q-legacy') then raise exception 'legacy tombstone missing'; end if; end $$;
update auth.users set raw_user_meta_data=jsonb_set(raw_user_meta_data,'{learning_progress,mistakes}','[{"id":"q-legacy"},{"id":"q-resurrect"}]'::jsonb,true) where id=auth.uid();
select public.get_textbook_mistake_state_v1();
do $$ begin
  if (select is_mistake from public.mistake_state where question_id='q-legacy') then raise exception 'legacy snapshot resurrected tombstone'; end if;
  if exists(select 1 from public.mistake_state where question_id='q-resurrect') then raise exception 'legacy snapshot re-imported'; end if;
end $$;
select public.record_textbook_answer_with_mistakes_v1('op1','builtin-japanese-syntax','q-a',0,false,'new',1,'bad');
select public.record_textbook_answer_with_mistakes_v1('op1','builtin-japanese-syntax','q-a',0,false,'new',1,'bad');
do $$ begin
  if (select count(*) from public.answer_attempts where exercise_id='q-a')<>1 then raise exception 'idempotency failed'; end if;
  if (select version from public.mistake_state where question_id='q-a')<>1 then raise exception 'version failed'; end if;
  begin perform public.record_textbook_answer_with_mistakes_v1('op1','builtin-japanese-syntax','q-a',0,true,'new',1,'different'); raise exception 'payload reuse accepted'; exception when raise_exception then if sqlerrm='payload reuse accepted' then raise; end if; end;
  begin perform public.record_textbook_answer_with_mistakes_v1('op2','builtin-japanese-syntax','q-a',0,true,'new',1,'ok'); raise exception 'stale version accepted'; exception when serialization_failure then null; end;
end $$;
select public.record_textbook_answer_with_mistakes_v1('op3','builtin-japanese-syntax','q-a',1,true,'new',1,'ok');
do $$ begin if not (select is_mistake from public.mistake_state where question_id='q-a') then raise exception 'ordinary correct removed mistake'; end if; end $$;
select public.record_textbook_answer_with_mistakes_v1('op4','builtin-japanese-syntax','q-a',2,true,'mistakes',1,'ok');
do $$ begin if (select is_mistake from public.mistake_state where question_id='q-a') then raise exception 'mistake replay did not remove'; end if; end $$;
select set_config('lab.fail','yes',false);
do $$ begin begin perform public.record_textbook_answer_with_mistakes_v1('op5','builtin-japanese-syntax','q-b',0,false,'new',1,'bad'); raise exception 'failure stub did not fail'; exception when others then if sqlerrm='failure stub did not fail' then raise; end if; end; end $$;
do $$ begin if exists(select 1 from public.mistake_state where question_id='q-b') or exists(select 1 from public.mistake_state_operations where operation_id='op5') or exists(select 1 from public.answer_attempts where exercise_id='q-b') then raise exception 'transaction did not rollback'; end if; end $$;
select set_config('lab.fail','no',false);
select public.record_textbook_answer_with_mistakes_v1('op5','builtin-japanese-syntax','q-b',0,false,'new',1,'corrected payload');
do $$ begin
  if (select count(*) from public.answer_attempts where exercise_id='q-b') <> 1 then raise exception 'retry after rollback did not record'; end if;
  if (select count(*) from public.mistake_state_operations where operation_id='op5') <> 1 then raise exception 'retry operation was not committed'; end if;
end $$;
reset request.jwt.claim.sub;
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
do $$ begin if exists(select 1 from public.mistake_state where user_id='00000000-0000-0000-0000-000000000001') then raise exception 'RLS leaked another account'; end if; end $$;
reset role;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
select public.get_textbook_mistake_state_v1();
do $$ begin if exists(select 1 from public.get_textbook_mistake_state_v1() as x where x->>'questionId'='q-a') then raise exception 'cross-account leak'; end if; end $$;
reset request.jwt.claim.sub;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000003';
do $$ begin
  begin perform public.get_textbook_mistake_state_v1(); raise exception 'unknown snapshot was accepted';
  exception when sqlstate '22023' then null; end;
  if exists(select 1 from public.mistake_state where user_id=auth.uid()) then raise exception 'unknown snapshot imported'; end if;
  if exists(select 1 from public.mistake_state_migrations where user_id=auth.uid()) then raise exception 'unknown snapshot marked migrated'; end if;
  if (select raw_user_meta_data->'learning_progress'->>'version' from auth.users where id=auth.uid()) <> '99' then raise exception 'unknown snapshot modified'; end if;
end $$;
reset request.jwt.claim.sub;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000004';
do $$ begin
  begin perform public.get_textbook_mistake_state_v1(); raise exception 'malformed snapshot was accepted';
  exception when sqlstate '22023' then null; end;
  if exists(select 1 from public.mistake_state_migrations where user_id=auth.uid()) then raise exception 'malformed snapshot marked migrated'; end if;
  if exists(select 1 from public.mistake_state where user_id=auth.uid()) then raise exception 'malformed snapshot imported'; end if;
end $$;
reset request.jwt.claim.sub;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000005';
select public.get_textbook_mistake_state_v1();
do $$ begin
  if not exists(select 1 from public.mistake_state where user_id=auth.uid() and question_id='q-root-fallback' and is_mistake) then raise exception 'root fallback snapshot not imported'; end if;
end $$;
reset request.jwt.claim.sub;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000006';
do $$ begin
  begin perform public.get_textbook_mistake_state_v1(); raise exception 'unsupported legacy shape was accepted';
  exception when sqlstate '22023' then null; end;
  if exists(select 1 from public.mistake_state_migrations where user_id=auth.uid()) then raise exception 'unsupported shape marked migrated'; end if;
end $$;
