#!/usr/bin/env node
import { createHmac, randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import { spawn, spawnSync } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const lab = path.join(root, '.local-dual-lab');
const composeFile = path.join(lab, 'docker-compose.yaml');
const project = 'jsc-dual-loopback-20261106';
const authUrl = 'http://127.0.0.1:54351';
const textbookId = 'builtin-japanese-syntax';
const trackedEnv = ['PATH', 'HOME', 'USER', 'LOGNAME', 'LANG', 'TMPDIR', 'DOCKER_HOST', 'DOCKER_CONTEXT'];
const baseEnv = Object.fromEntries(trackedEnv.filter((key) => process.env[key]).map((key) => [key, process.env[key]]));
const inspectionEnv = {...baseEnv,LOCAL_JWT_SECRET:'inspection-only-placeholder-jwt-secret',LOCAL_DB_PASSWORD:'inspection-only-placeholder-db-password'};
let secrets = [];
let composeEnv;
let started = false;
let webProcess;
let questionMarker;
let raceResultMarker;
let webRaceResultMarker;
let gateServer;
const log = (text) => console.log(`[dual-lab] ${text}`);
function run(command, args, env = baseEnv, input) {
  return spawnSync(command, args, { cwd: root, env, input, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
}
function check(result, phase) {
  if (result.error || result.status !== 0) throw new Error(`${phase} failed${result.error?.code ? ` (${result.error.code})` : ''}; output suppressed`);
}
function compose(args, env = composeEnv ?? baseEnv, input) {
  return run('docker', ['compose', '--env-file', '/dev/null', '--project-name', project, '--file', composeFile, '--file', path.join(root, 'scripts/ios/dual-client-compose-override.yaml'), ...args], env, input);
}
function b64(value) { return Buffer.from(JSON.stringify(value)).toString('base64url'); }
function makeAnonKey(secret) {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${b64({alg:'HS256',typ:'JWT'})}.${b64({iss:'supabase',ref:'jsc-dual-loopback',role:'anon',iat:now,exp:now+86400})}`;
  return `${unsigned}.${createHmac('sha256', secret).update(unsigned).digest('base64url')}`;
}
async function jsonRequest(url, body, headers = {}, method = 'POST') {
  let response;
  try {
    response = await fetch(url, {method, headers:{'content-type':'application/json', ...headers}, ...(body === undefined ? {} : {body:JSON.stringify(body)}), signal:AbortSignal.timeout(12000)});
  } catch (error) {
    if (error.name === 'TimeoutError' && started) {
      const result = compose(['exec','-T','db','psql','-U','postgres','-d','postgres','-Atc',"select count(*) filter (where wait_event_type='Lock'), count(*) filter (where state='active') from pg_stat_activity where datname=current_database()"]);
      if (result.status === 0 && /^\d+\|\d+\s*$/.test(result.stdout)) log(`database lock-wait and active counts: ${result.stdout.trim()}`);
    }
    throw new Error('isolated request timed out or could not connect');
  }
  let data;
  try { data = await response.json(); } catch { throw new Error(`HTTP ${response.status} returned non-JSON`); }
  return {response, data};
}
function psql(sql) {
  const result = compose(['exec','-T','db','psql','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'], composeEnv, sql);
  if (result.status !== 0) {
    const error = (result.stderr ?? '').match(/ERROR:\s+([^\n]+)/)?.[1] ?? '';
    const category = /column .* does not exist/i.test(error) ? 'missing column' : /relation .* does not exist/i.test(error) ? 'missing relation' : /function .* does not exist/i.test(error) ? 'missing function' : /permission denied/i.test(error) ? 'permission denied' : /syntax error/i.test(error) ? 'SQL syntax error' : 'unclassified SQL error';
    const line = (result.stderr ?? '').match(/LINE\s+(\d+)/)?.[1];
    throw new Error(`isolated database setup failed (${category}${line ? `, line ${line}` : ''}); output suppressed`);
  }
  check(result, 'isolated database setup');
  return result.stdout;
}
async function waitFor(url, label) {
  for (let i=0;i<70;i++) {
    try { const r = await fetch(url, {signal:AbortSignal.timeout(1000)}); if (r.ok) return; } catch {}
    await sleep(1000);
  }
  throw new Error(`${label} did not become healthy`);
}
async function startRaceGate() {
  const arrivals = new Map();
  gateServer = createServer((request,response) => {
    const origin = request.headers.origin;
    if (origin === 'http://127.0.0.1:3219') response.setHeader('access-control-allow-origin', origin);
    response.setHeader('access-control-allow-methods', 'POST, OPTIONS');
    response.setHeader('access-control-allow-headers', 'content-type');
    if (request.method === 'OPTIONS') { response.writeHead(204).end(); return; }
    const role = request.url === '/ready/web' ? 'web' : request.url === '/ready/ios' ? 'ios' : null;
    if (request.method !== 'POST' || !role || arrivals.has(role)) { response.writeHead(404).end(); return; }
    arrivals.set(role,response);
    log(`${role} reached same-version race barrier`);
    if (arrivals.size === 2) {
      arrivals.get('web').writeHead(204).end();
      setTimeout(() => arrivals.get('ios').writeHead(204).end(), 200);
      log('both clients reached the barrier; Web and iOS released within the same concurrent race window');
    }
  });
  await new Promise((resolve,reject) => { gateServer.once('error',reject); gateServer.listen(3220,'127.0.0.1',resolve); });
}
function verifyResources() {
  const existing = compose(['ps','-a','-q'], inspectionEnv);
  check(existing, 'existing project resource check');
  if (existing.stdout.trim()) throw new Error('refusing to reuse pre-existing isolated lab containers');
  const volumes = run('docker',['volume','ls','-q','--filter',`label=com.docker.compose.project=${project}`]);
  check(volumes, 'existing project volume check');
  if (volumes.stdout.trim()) throw new Error('refusing to reuse pre-existing isolated lab volumes');
  for (const port of ['54351','3219','3220']) {
    const occupied = run('lsof',['-nP',`-iTCP:${port}`,'-sTCP:LISTEN']);
    if (occupied.status === 0) throw new Error(`required loopback port ${port} is already occupied`);
  }
}
function verifyBindings() {
  const listed = compose(['ps','-a','-q']); check(listed,'container verification');
  const ids = listed.stdout.trim().split(/\r?\n/).filter(Boolean);
  if (ids.length !== 4) throw new Error('expected exactly four isolated services');
  const names = new Set();
  for (const id of ids) {
    const item = run('docker',['inspect','--format','{{json .Config.Labels}}|{{json .HostConfig.PortBindings}}',id],composeEnv); check(item,'container binding verification');
    const sep = item.stdout.indexOf('|'); const labels = JSON.parse(item.stdout.slice(0,sep)); const binds = JSON.parse(item.stdout.slice(sep+1).trim()) ?? {};
    if (labels['com.docker.compose.project'] !== project) throw new Error('unexpected container project label');
    const name = labels['com.docker.compose.service']; names.add(name);
    const all = Object.values(binds).flatMap((value) => value ?? []);
    if (name === 'api') {
      if (all.length !== 1 || all[0].HostIp !== '127.0.0.1' || all[0].HostPort !== '54351') throw new Error('API is not restricted to 127.0.0.1:54351');
    } else if (all.length) throw new Error(`${name} unexpectedly publishes host ports`);
  }
  if (['db','auth','rest','api'].some((name) => !names.has(name))) throw new Error('isolated project is missing a required service');
}
async function runBackend() {
  const jwt = randomBytes(48).toString('base64url');
  const dbPassword = randomBytes(32).toString('base64url');
  const anonKey = makeAnonKey(jwt);
  const email = `dual-${randomBytes(12).toString('hex')}@example.invalid`;
  const password = `${randomBytes(24).toString('base64url')}Aa7!`;
  secrets = [jwt,dbPassword,anonKey,email,password];
  composeEnv = {...baseEnv,LOCAL_JWT_SECRET:jwt,LOCAL_DB_PASSWORD:dbPassword};
  log('checking isolated ports and project identity'); verifyResources(); started = true;
  check(compose(['up','-d','--wait','db','auth']), 'isolated database and GoTrue startup');
  // GoTrue owns auth.users; apply only the explicit learning migration allowlist.
  let setup = 'create table public.answer_attempts (id bigint generated by default as identity primary key,user_id uuid not null references auth.users(id) on delete cascade,lesson_id integer not null,exercise_id text not null,answer text not null,verdict text not null,error_tags text[] default \'{}\',created_at timestamptz default now());\n';
  for (const relative of ['supabase/migrations/202609070001_m4_learning_records.sql','supabase/migrations/202609070002_lesson_accuracy.sql','supabase/migrations/202609130001_knowledge_point_mastery.sql','supabase/migrations/202610030001_textbook_scoped_learning.sql','supabase/candidates/202611060001_atomic_mistake_state.sql']) {
    const fs = await import('node:fs/promises'); setup += `\n-- ${path.basename(relative)}\n${await fs.readFile(path.join(root,relative),'utf8')}\n`;
  }
  setup += `alter role authenticator password '${dbPassword}';\ngrant usage on schema public to anon,authenticated,authenticator;\ngrant select on public.answer_attempts,public.question_review_state,public.lesson_progress,public.knowledge_point_mastery,public.daily_learning_progress,public.mistake_state,public.mistake_state_migrations,public.mistake_state_operations to authenticated;\ngrant select on public.answer_attempts,public.question_review_state,public.lesson_progress,public.knowledge_point_mastery,public.daily_learning_progress to authenticator;`;
  psql(setup);
  check(compose(['up','-d','rest','api']), 'isolated API startup');
  verifyBindings();
  log('loopback-only service bindings verified');
  await waitFor(`${authUrl}/health`,'GoTrue');
  await waitFor(`${authUrl}/rest/v1/`,'PostgREST');
  log('GoTrue and PostgREST are healthy; explicit learning migration allowlist applied');
  const {response: signupResponse,data:signup} = await jsonRequest(`${authUrl}/auth/v1/signup`,{email,password},{apikey:anonKey});
  if (!signupResponse.ok || !(signup.id || signup.user?.id)) throw new Error(`isolated signup failed (HTTP ${signupResponse.status})`);
  const {response:loginResponse,data:session} = await jsonRequest(`${authUrl}/auth/v1/token?grant_type=password`,{email,password},{apikey:anonKey});
  if (!loginResponse.ok || !session.access_token) throw new Error(`isolated password authentication failed (HTTP ${loginResponse.status})`);
  log('real GoTrue signup and password authentication passed');
  const token = session.access_token;
  let tokenRole;
  try { tokenRole = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8')).role; } catch {}
  if (tokenRole !== 'authenticated') throw new Error(`GoTrue access token role is ${tokenRole == null || tokenRole === '' ? 'missing' : 'unexpected'}; authenticated role required`);
  const authHeaders = {apikey:anonKey,Authorization:`Bearer ${token}`};
  const snapshot = await jsonRequest(`${authUrl}/rest/v1/rpc/get_textbook_mistake_state_v1`,{p_textbook_id:textbookId},authHeaders);
  if (!snapshot.response.ok || !Array.isArray(snapshot.data)) {
    const code = typeof snapshot.data?.code === 'string' && /^(?:PGRST\d{3}|[0-9A-Z]{5})$/.test(snapshot.data.code) ? snapshot.data.code : 'unknown';
    const message = typeof snapshot.data?.message === 'string' ? snapshot.data.message : '';
    const location = typeof snapshot.data?.details === 'string' ? snapshot.data.details : '';
    const category = ['Unknown user', 'Unsupported legacy mistake snapshot', 'Unsupported legacy mistake entry', 'cannot call jsonb_object_keys on a scalar', 'cannot extract elements from an object', 'invalid input syntax for type json', 'invalid configuration parameter name', 'unrecognized configuration parameter', 'invalid parameter value', 'parameter', 'json', 'claim', 'role'].find((value) => message.toLowerCase().includes(value.toLowerCase())) ?? 'unclassified';
    const safeWords = new Set('role permission denied current session user transaction function set reset change while security definer cannot is not allowed within must be member of to switch does exist unknown jwt claim claims missing invalid name value config option parameter unsupported bad length request prepared statement server db auth failure password grant requires a the in an null true false string json'.split(' '));
    const roleCategory = (message.toLowerCase().match(/[a-z]+/g) ?? []).filter((word) => safeWords.has(word)).join(' ') || 'none';
    const source = ['_initialize_mistake_state', 'get_textbook_mistake_state_v1', 'auth.uid', 'set_config'].find((value) => location.includes(value)) ?? 'unclassified';
    throw new Error(`initial PostgREST snapshot failed (HTTP ${snapshot.response.status}, code ${code}, category ${category}, role detail ${roleCategory}, source ${source})`);
  }
  log('authenticated PostgREST snapshot passed');
  const questionId = 'L01-Q001';
  log('testing atomic answer');
  const accepted = await jsonRequest(`${authUrl}/rest/v1/rpc/record_textbook_answer_with_mistakes_v1`,{
    p_operation_id:'lab-operation-primary',p_textbook_id:textbookId,p_question_id:questionId,p_expected_version:0,p_correct:false,p_mode:'new',p_lesson_id:1,p_answer:'lab answer',p_error_tags:['lab'],p_knowledge_tags:['lab'],p_verdict:'incorrect',p_lesson_question_limit:20,
  },authHeaders);
  if (!accepted.response.ok || accepted.data.version !== 1 || accepted.data.isMistake !== true) throw new Error(`atomic answer RPC failed (HTTP ${accepted.response.status})`);
  log('testing atomic replay');
  const duplicate = await jsonRequest(`${authUrl}/rest/v1/rpc/record_textbook_answer_with_mistakes_v1`,{
    p_operation_id:'lab-operation-primary',p_textbook_id:textbookId,p_question_id:questionId,p_expected_version:0,p_correct:false,p_mode:'new',p_lesson_id:1,p_answer:'lab answer',p_error_tags:['lab'],p_knowledge_tags:['lab'],p_verdict:'incorrect',p_lesson_question_limit:20,
  },authHeaders);
  if (!duplicate.response.ok || duplicate.data.duplicate !== true) throw new Error(`idempotent replay failed (HTTP ${duplicate.response.status})`);
  log('testing atomic conflict');
  const stale = await jsonRequest(`${authUrl}/rest/v1/rpc/record_textbook_answer_with_mistakes_v1`,{
    p_operation_id:'lab-operation-stale',p_textbook_id:textbookId,p_question_id:questionId,p_expected_version:0,p_correct:true,p_mode:'mistakes',p_lesson_id:1,p_answer:'stale',p_error_tags:[],p_knowledge_tags:[],p_verdict:'correct',p_lesson_question_limit:20,
  },authHeaders);
  if (stale.response.ok || !JSON.stringify(stale.data).includes('40001')) throw new Error(`stale PostgREST RPC did not expose serialization conflict (HTTP ${stale.response.status})`);
  const cleared = await jsonRequest(`${authUrl}/rest/v1/rpc/record_textbook_answer_with_mistakes_v1`,{
    p_operation_id:'lab-operation-clear',p_textbook_id:textbookId,p_question_id:questionId,p_expected_version:1,p_correct:true,p_mode:'mistakes',p_lesson_id:1,p_answer:'cleared',p_error_tags:[],p_knowledge_tags:[],p_verdict:'correct',p_lesson_question_limit:20,
  },authHeaders);
  if (!cleared.response.ok || cleared.data.isMistake !== false || cleared.data.version !== 2) throw new Error(`clear mistake RPC failed (HTTP ${cleared.response.status})`);
  const dbcheck = psql(`do $$ begin if (select count(*) from public.answer_attempts where exercise_id='L01-Q001') <> 2 then raise exception 'answer attempts assertion'; end if; if (select count(*) from public.mistake_state_operations where operation_id in ('lab-operation-primary','lab-operation-clear')) <> 2 then raise exception 'operation assertion'; end if; if (select version from public.mistake_state where question_id='L01-Q001') <> 2 or (select is_mistake from public.mistake_state where question_id='L01-Q001') then raise exception 'mistake state assertion'; end if; end $$;`);
  void dbcheck;
  log('atomic add, clear, same-version conflict, idempotent replay and database assertions passed');
  return {anonKey,email,password,questionId};
}
async function startWeb(env) {
  webProcess = spawn('npm',['run','dev','--','--hostname','127.0.0.1','--port','3219'],{cwd:root,env:{...process.env,...env},stdio:'ignore',detached:true});
  await waitFor('http://127.0.0.1:3219/','Next.js');
  log('Next.js listening on 127.0.0.1:3219');
}
async function verifyNextApi(credentials, anonKey) {
  const login = await jsonRequest(`${authUrl}/auth/v1/token?grant_type=password`,{email:credentials.email,password:credentials.password},{apikey:anonKey});
  if (!login.response.ok || !login.data.access_token) throw new Error(`second-device authentication failed (HTTP ${login.response.status})`);
  const headers = {Authorization:`Bearer ${login.data.access_token}`,'content-type':'application/json'};
  const snapshot = await fetch('http://127.0.0.1:3219/api/study-state?textbookId=builtin-japanese-syntax',{headers,signal:AbortSignal.timeout(15000)});
  const state = await snapshot.json().catch(()=>null);
  if (!snapshot.ok || state?.mistakeStateAvailable !== true || !Array.isArray(state.mistakeStates)) throw new Error(`Next study-state API failed (HTTP ${snapshot.status})`);
  const questionId = 'L01-Q002';
  const answer = {textbookId:textbookId,questionId,lessonId:1,questionLimit:20,answer:'dual api incorrect',correct:false,mode:'new',errorTags:['api-lab'],knowledgeTags:['api-lab'],clientRequestId:'api-lab-answer',expectedMistakeVersion:0};
  const first = await fetch('http://127.0.0.1:3219/api/record-answer',{method:'POST',headers,body:JSON.stringify(answer)});
  const firstBody = await first.json().catch(()=>null);
  if (!first.ok || firstBody?.mistakeState?.version !== 1 || firstBody?.mistakeState?.isMistake !== true) throw new Error(`Next answer API failed (HTTP ${first.status})`);
  const replay = await fetch('http://127.0.0.1:3219/api/record-answer',{method:'POST',headers,body:JSON.stringify(answer)});
  const replayBody = await replay.json().catch(()=>null);
  if (!replay.ok || replayBody?.duplicate !== true) throw new Error(`Next idempotency replay failed (HTTP ${replay.status})`);
  const conflict = await fetch('http://127.0.0.1:3219/api/record-answer',{method:'POST',headers,body:JSON.stringify({...answer,clientRequestId:'api-lab-stale',correct:true,mode:'mistakes',expectedMistakeVersion:0})});
  if (conflict.status !== 409) throw new Error(`Next stale-version API expected HTTP 409, got ${conflict.status}`);
  const clear = await fetch('http://127.0.0.1:3219/api/record-answer',{method:'POST',headers,body:JSON.stringify({...answer,clientRequestId:'api-lab-clear',correct:true,mode:'mistakes',expectedMistakeVersion:1})});
  const clearBody = await clear.json().catch(()=>null);
  if (!clear.ok || clearBody?.mistakeState?.version !== 2 || clearBody?.mistakeState?.isMistake !== false) throw new Error(`Next clear API failed (HTTP ${clear.status})`);
  psql(`do $$ begin if (select count(*) from public.answer_attempts where exercise_id='L01-Q002') <> 2 then raise exception 'Next answer attempts assertion'; end if; if (select count(*) from public.mistake_state_operations where operation_id in ('api-lab-answer','api-lab-clear')) <> 2 or exists(select 1 from public.mistake_state_operations where operation_id='api-lab-stale') then raise exception 'Next operations assertion'; end if; if not exists(select 1 from public.mistake_state where question_id='L01-Q002' and version=2 and not is_mistake) then raise exception 'Next state assertion'; end if; end $$;`);
  log('real Next API authentication, snapshot, answer, clear, conflict, replay and database assertions passed');
}
async function cleanup() {
  if (gateServer) await new Promise((resolve) => gateServer.close(resolve));
  if (webProcess && webProcess.exitCode === null && webProcess.pid) {
    try { process.kill(-webProcess.pid, 'SIGTERM'); } catch {}
    await Promise.race([new Promise((r)=>webProcess.once('exit',r)),sleep(5000)]);
    try { process.kill(-webProcess.pid, 'SIGKILL'); } catch {}
  }
  if (started) {
    const down = compose(['down','--volumes','--remove-orphans'],composeEnv);
    if (down.error || down.status !== 0) console.error('[dual-lab] cleanup failed; isolated resources may remain');
    else log('isolated containers and volume removed');
  }
  for (const marker of [questionMarker,raceResultMarker,webRaceResultMarker]) if (marker) { try { await (await import('node:fs/promises')).unlink(marker); } catch {} }
  secrets = [];
}
async function main() {
  const opts = new Set(process.argv.slice(2));
  const known = new Set(['--backend','--web','--ios','--cross-client']);
  if ([...opts].some((arg)=>!known.has(arg)) || opts.size > 1) throw new Error('choose exactly one of --backend, --web, --ios, or --cross-client');
  const mode = opts.values().next().value ?? '--backend';
  const credentials = await runBackend();
  const env = {LOCAL_DUAL_AUTH_URL:authUrl,LOCAL_DUAL_WEB_URL:'http://127.0.0.1:3219',LOCAL_DUAL_ANON_KEY:credentials.anonKey,LOCAL_DUAL_EMAIL:credentials.email,LOCAL_DUAL_PASSWORD:credentials.password,NEXT_PUBLIC_SUPABASE_URL:authUrl,NEXT_PUBLIC_SUPABASE_ANON_KEY:credentials.anonKey,MISTAKE_STATE_V1_ENABLED:'1'};
  await startWeb(env);
  if (mode !== '--ios') await verifyNextApi(credentials,credentials.anonKey);
  questionMarker = path.join(root,'build',`dual-client-question-${randomBytes(12).toString('hex')}.txt`);
  const crossEnv = mode === '--cross-client' ? {...env,LOCAL_DUAL_QUESTION_MARKER:questionMarker} : env;
  const runBrowser = (grep) => {
    const args = ['playwright','test','--config','tests/dual-client-lab.config.ts','tests/e2e/dual-client-lab.spec.ts',...(grep ? ['--grep',grep] : [])];
    const result = run('npx',args,{...process.env,...crossEnv});
    if (result.error || result.status !== 0) throw new Error('browser UI verification failed; test output suppressed');
  };
  const runIOS = (selection,expected,extra = {}) => {
    const runnerPath = path.join(root,'scripts/ios/dual-client-sdk-test.sh');
    const runnerEnv = {...process.env,...Object.fromEntries(Object.entries({...crossEnv,...extra}).map(([key,value])=>[`TEST_RUNNER_${key}`,value])),...(selection ? {TEST_RUNNER_ONLY_TEST:selection} : {}),...(expected ? {TEST_RUNNER_EXPECTED_TESTS:String(expected)} : {})};
    const child = spawn('bash',[runnerPath],{cwd:root,env:runnerEnv,stdio:['ignore','pipe','ignore']});
    let output = '';
    child.stdout.on('data',chunk => { output += chunk.toString(); });
    return new Promise((resolve,reject) => child.once('exit',code => {
      if (code !== 0) { reject(new Error('iOS XCTest runner failed; build output suppressed')); return; }
      for (const line of output.split(/\r?\n/)) if (/^(SDK Dual-client tests:|SDK result bundle:)/.test(line)) log(line);
      resolve();
    }));
  };
  const runBrowserAsync = (grep,extra = {}) => {
    const args = ['playwright','test','--config','tests/dual-client-lab.config.ts','tests/e2e/dual-client-lab.spec.ts','--grep',grep];
    const child = spawn('npx',args,{cwd:root,env:{...process.env,...crossEnv,...extra,LOCAL_DUAL_GATE_URL:'http://127.0.0.1:3220'},stdio:['ignore','ignore','ignore']});
    return new Promise((resolve,reject) => child.once('exit',code => code === 0 ? resolve() : reject(new Error('browser UI verification failed; test output suppressed'))));
  };
  if (mode === '--web') { runBrowser('authenticated learning UI|submits an incorrect answer'); log('browser UI interaction passed'); }
  else if (mode === '--cross-client') {
    runBrowser('submits an incorrect answer through the UI');
    log('browser recorded the shared-account mistake');
    await runIOS('JapaneseSyntaxCoachTests/DualClientLabTests/testBrowserCreatedMistakeCanBeClearedByLearningStore',1,crossEnv);
    runBrowser('browser refresh confirms the iOS LearningStore cleared its mistake');
    log('iOS LearningStore clear confirmed after browser refresh');
    await startRaceGate();
    raceResultMarker = path.join(root,'build',`dual-client-ios-race-${randomBytes(12).toString('hex')}.txt`);
    webRaceResultMarker = path.join(root,'build',`dual-client-web-race-${randomBytes(12).toString('hex')}.txt`);
    const raceEnv = {...env,LOCAL_DUAL_GATE_URL:'http://127.0.0.1:3220',LOCAL_DUAL_RACE_RESULT:raceResultMarker,LOCAL_DUAL_WEB_RACE_RESULT:webRaceResultMarker};
    psql(`create or replace function public.dual_lab_race_lock() returns trigger language plpgsql as $$ begin if new.question_id='L01-Q008' then perform pg_advisory_xact_lock(hashtext('dual-client-lab-L01-Q008')); perform pg_sleep(1.0); end if; return new; end $$; drop trigger if exists dual_lab_race_lock on public.mistake_state; create trigger dual_lab_race_lock before insert or update on public.mistake_state for each row execute function public.dual_lab_race_lock();`);
    await Promise.all([
      runIOS('JapaneseSyntaxCoachTests/DualClientLabTests/testSameVersionRaceReleasesWebAndLearningStoreTogether',1,raceEnv),
      runBrowserAsync('browser Cookie request races LearningStore Bearer request at the shared gate',raceEnv),
    ]);
    const fs = await import('node:fs/promises');
    const [web,ios] = (await Promise.all([fs.readFile(webRaceResultMarker,'utf8'),fs.readFile(raceResultMarker,'utf8')])).map(JSON.parse);
    if (![web,ios].every(item => Number.isFinite(item.start) && Number.isFinite(item.end) && item.end > item.start)) throw new Error('race request timing observations are invalid');
    const overlapMs = Math.min(web.end,ios.end) - Math.max(web.start,ios.start);
    if (overlapMs <= 0) throw new Error('race requests did not overlap in flight');
    log(`same-version outcomes: Web HTTP ${web.status}, iOS LearningStore HTTP ${ios.status}; client requests overlapped ${Math.round(overlapMs)} ms`);
    if (web.status !== 200 || ios.status !== 409) throw new Error('same-version race did not produce Web HTTP 200 and iOS HTTP 409 with its failed queue retained');
    const questionId = 'L01-Q008';
    psql(`do $$ begin if (select count(*) from public.answer_attempts where exercise_id='${questionId}') <> 1 then raise exception 'race answer attempt count assertion'; end if; if (select count(*) from public.mistake_state_operations where payload->>'questionId'='${questionId}') <> 1 then raise exception 'race operation count assertion'; end if; if not exists(select 1 from public.mistake_state where question_id='${questionId}' and version=1 and is_mistake) then raise exception 'race version assertion'; end if; end $$;`);
    log('same-version Web Cookie and iOS Bearer race passed: one 200, one 409, one answer, one operation, version 1');
  } else if (mode === '--ios') {
    await runIOS(null,3);
  }
  log(`${mode.slice(2)} verification completed`);
}
try { await main(); } catch (error) { console.error(`[dual-lab] failed: ${error.message}`); process.exitCode=1; } finally { await cleanup(); }
