#!/usr/bin/env node
import { createHmac, randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const projectDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../.local-auth-lab');
const expectedUrl = 'http://127.0.0.1:54341';
const projectName = 'jsc-auth-loopback-20261106';
const composeFile = path.join(projectDir, 'docker-compose.yaml');
const childEnv = Object.fromEntries(
  ['PATH', 'HOME', 'USER', 'LOGNAME', 'LANG', 'TMPDIR', 'DOCKER_HOST', 'DOCKER_CONTEXT'].filter((key) => process.env[key]).map((key) => [key, process.env[key]]),
);
const cleanupEnv = {
  ...childEnv,
  LOCAL_JWT_SECRET: 'local-cleanup-placeholder-jwt-secret',
  LOCAL_DB_PASSWORD: 'local-cleanup-placeholder-db-password',
};

function run(command, args, env = childEnv) {
  return spawnSync(command, args, {
    cwd: projectDir,
    encoding: 'utf8',
    env,
    maxBuffer: 8 * 1024 * 1024,
  });
}

function requireSuccess(result, phase) {
  if (result.error || result.status !== 0) {
    const detail = result.error?.code ? ` (${result.error.code})` : '';
    throw new Error(`${phase} failed${detail}; command output suppressed.`);
  }
}

function compose(args, env = childEnv) {
  return run('docker', ['compose', '--env-file', '/dev/null', '--project-name', projectName, '--file', composeFile, ...args], env);
}

function makeAnonKey(jwtSecret) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ iss: 'supabase', ref: 'jsc-auth-loopback', role: 'anon', iat: now, exp: now + 86400 })}`;
  const signature = createHmac('sha256', jwtSecret).update(unsigned).digest('base64url');
  return `${unsigned}.${signature}`;
}

async function request(pathname, body, headers = {}) {
  const response = await fetch(`${expectedUrl}${pathname}`, {
    method: 'POST',
    headers: { apikey: anonKey, 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
  let data;
  try {
    data = await response.json();
  } catch {
    throw new Error(`${pathname} returned non-JSON (${response.status}).`);
  }
  if (!response.ok) {
    const code = typeof data.error_code === 'string' ? data.error_code : (typeof data.code === 'string' ? data.code : '');
    const detail = [data.msg, data.message, data.error_description].find((value) => typeof value === 'string') ?? '';
    let category = 'unclassified';
    let safeDetail = 'no safe detail available';
    const knownDatabaseErrors = [
      ['database error finding user', 'Database error finding user'],
      ['database error creating user', 'Database error creating user'],
      ['database error saving new user', 'Database error saving new user'],
      ['database error updating user', 'Database error updating user'],
      ['database error loading user after sign-up', 'Database error loading user after sign-up'],
    ];
    const knownDatabaseError = knownDatabaseErrors.find(([pattern]) => detail.toLowerCase().includes(pattern));
    if (knownDatabaseError) {
      category = 'database operation';
      safeDetail = `GoTrue reported "${knownDatabaseError[1]}"`;
    } else if (/schema|permission|relation/i.test(detail)) {
      category = 'database schema or permission';
      safeDetail = 'GoTrue reported a database schema or permission error';
    } else if (/jwt|token|signing/i.test(detail)) {
      category = 'token configuration';
      safeDetail = 'GoTrue reported a token configuration error';
    } else if (/email|password|signup|provider/i.test(detail)) {
      category = 'auth configuration';
      safeDetail = 'GoTrue reported an authentication configuration error';
    }
    const safeCode = /^[a-z0-9_-]{1,64}$/i.test(code) ? code : 'not-provided';
    throw new Error(`${pathname} failed with HTTP ${response.status} (category: ${category}, code: ${safeCode}; ${safeDetail}).`);
  }
  return data;
}

async function waitForAuth(composeEnv) {
  for (let attempt = 0; attempt < 60; attempt += 1) {
    const listed = compose(['ps', '-a', '-q'], composeEnv);
    if (listed.status === 0) {
      for (const id of listed.stdout.trim().split(/\r?\n/).filter(Boolean)) {
        const state = run('docker', ['inspect', '--format', '{{index .Config.Labels "com.docker.compose.service"}} {{.State.Status}}', id], composeEnv);
        if (state.status === 0 && state.stdout.trim() === 'auth exited') {
          reportContainerStartupDiagnostics(composeEnv);
          throw new Error('GoTrue container exited during startup.');
        }
      }
    }
    try {
      const response = await fetch(`${expectedUrl}/health`, { signal: AbortSignal.timeout(1000) });
      if (response.ok) return;
      if (attempt === 0) console.error(`GoTrue health endpoint returned HTTP ${response.status}.`);
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  reportContainerStartupDiagnostics(composeEnv);
  throw new Error('GoTrue did not become healthy within 60 seconds.');
}

function reportContainerStartupDiagnostics(env) {
  const listed = compose(['ps', '-a', '-q'], env);
  if (listed.status !== 0) {
    console.error('Startup diagnostics unavailable (Compose status query failed).');
    return;
  }
  const ids = listed.stdout.trim().split(/\r?\n/).filter(Boolean);
  for (const id of ids) {
    const inspected = run('docker', ['inspect', '--format', '{{index .Config.Labels "com.docker.compose.service"}}', id], env);
    const service = inspected.status === 0 ? inspected.stdout.trim() : 'unknown';
    if (!['auth', 'db'].includes(service)) continue;
    const state = run('docker', ['inspect', '--format', '{{.State.Status}} exit={{.State.ExitCode}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}', id], env);
    if (state.status === 0) console.error(`Container state [${service}]: ${state.stdout.trim()}`);
    const result = run('docker', ['logs', '--tail', '40', id], env);
    if (result.status !== 0) continue;
    let emitted = 0;
    for (const line of `${result.stdout}\n${result.stderr}`.split(/\r?\n/)) {
      let record = {};
      const jsonStart = line.indexOf('{');
      if (jsonStart >= 0) {
        try { record = JSON.parse(line.slice(jsonStart)); } catch {}
      }
      let details = [record.msg, record.error, record.message, record.err]
        .filter((value) => typeof value === 'string')
        .join(' ');
      if (!details) details = line;
      for (const secret of diagnosticSecrets) details = details.split(secret).join('[redacted]');
      details = details
        .replace(/(?:postgres(?:ql)?|mysql):\/\/[^\s"']+/gi, '[redacted database URL]')
        .replace(/\b(?:password|secret|token|key|pass|pwd|user|username)\s*[=:]\s*[^\s,;"']+/gi, '[redacted credential]')
        .replace(/\b(?:Bearer\s+)?eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g, '[redacted JWT]')
        .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[redacted email]')
        .replace(/\bhttps?:\/\/[^\s"']+/gi, '[redacted URL]');
      const stateCode = details.match(/SQLSTATE\s*[:=]?\s*([0-9A-Z]{5})/i)?.[1];
      const missingObject = details.match(/(?:relation|table|column|schema|function)\s+["']?([A-Za-z_][A-Za-z0-9_$]*(?:\.[A-Za-z_][A-Za-z0-9_$]*)?)["']?\s+does not exist/i);
      const fixedError = [
        'Database error finding user', 'Database error creating user', 'Database error saving new user',
        'Database error updating user', 'Database error loading user after sign-up',
        'GoTrue migrations applied successfully',
      ].find((candidate) => details.includes(candidate));
      if (!stateCode && !missingObject && !fixedError) continue;
      if (emitted >= 12) continue;
      const level = typeof record.level === 'string' && /^[a-z]+$/i.test(record.level) ? record.level : undefined;
      const fields = [level && `level=${level}`, fixedError && `fixedError="${fixedError}"`, stateCode && `SQLSTATE=${stateCode}`, missingObject && `missingObject=${missingObject[1]}`].filter(Boolean);
      console.error(`Container error [${service}]: ${fields.join(' ')}`);
      emitted += 1;
    }
  }
}

function verifyPortBindings(env = childEnv) {
  const result = compose(['ps', '-a', '-q'], env);
  requireSuccess(result, 'Compose status');
  const ids = result.stdout.trim().split(/\r?\n/).filter(Boolean);
  if (ids.length !== 3) throw new Error('Expected exactly the lab db, auth, and API containers.');
  const services = new Set();
  for (const id of ids) {
    const inspected = run('docker', [
      'inspect', '--format', '{{json .Config.Labels}}|{{json .HostConfig.PortBindings}}', id,
    ], env);
    requireSuccess(inspected, 'Docker inspect');
    const separator = inspected.stdout.indexOf('|');
    if (separator < 0) throw new Error('Docker inspect returned an invalid response.');
    const labels = JSON.parse(inspected.stdout.slice(0, separator));
    const bindings = JSON.parse(inspected.stdout.slice(separator + 1).trim()) ?? {};
    if (labels['com.docker.compose.project'] !== projectName) throw new Error('Found a container outside the fixed Compose project.');
    services.add(labels['com.docker.compose.service']);
    const service = labels['com.docker.compose.service'];
    if (service === 'api') {
      const apiBindings = bindings['80/tcp'] ?? [];
      if (apiBindings.length !== 1 || apiBindings[0].HostIp !== '127.0.0.1' || apiBindings[0].HostPort !== '54341') {
        throw new Error('API is not exclusively bound to 127.0.0.1:54341.');
      }
    } else if (Object.values(bindings).some((items) => items?.length)) {
      throw new Error(`${service} unexpectedly publishes a host port.`);
    }
  }
  if (['db', 'auth', 'api'].some((service) => !services.has(service))) {
    throw new Error('Compose project is missing a required lab service.');
  }
}

let anonKey;
let labStarted = false;
let labEnvironment = cleanupEnv;
const diagnosticSecrets = new Set();
function stopLab() {
  const stopped = compose(['down', '--volumes', '--remove-orphans'], cleanupEnv);
  requireSuccess(stopped, 'Compose stop');
}

try {
  if (process.argv[2] === '--stop') {
    stopLab();
    console.log('Local Auth lab stopped and its data volume removed.');
  } else {
    const jwtSecret = randomBytes(48).toString('base64url');
    const dbPassword = randomBytes(32).toString('base64url');
    diagnosticSecrets.add(jwtSecret);
    diagnosticSecrets.add(dbPassword);
    const composeEnv = { ...childEnv, LOCAL_JWT_SECRET: jwtSecret, LOCAL_DB_PASSWORD: dbPassword };
    labEnvironment = composeEnv;

    const ports = run('lsof', ['-nP', '-iTCP:54341', '-sTCP:LISTEN']);
    if (ports.status === 0) throw new Error('Port 54341 is already listening; refusing to change another service.');

    const existing = compose(['ps', '-a', '-q'], cleanupEnv);
    requireSuccess(existing, 'Existing Auth lab resources check');
    if (existing.stdout.trim()) throw new Error('refusing to reuse existing Auth lab resources; stop the dedicated lab explicitly first.');
    labStarted = true;
    const started = compose(['up', '-d'], composeEnv);
    if (started.error || started.status !== 0) {
      reportContainerStartupDiagnostics(composeEnv);
      requireSuccess(started, 'Compose start');
    }
    verifyPortBindings(composeEnv);
    console.log('Compose bindings: localhost-only verified.');

    await waitForAuth(composeEnv);
    const schemaCheck = compose(['exec', '-T', 'db', 'psql', '-U', 'postgres', '-d', 'postgres', '-Atc', "SELECT 'search_path=' || current_setting('search_path'); SELECT schemaname || '.' || tablename FROM pg_tables WHERE tablename IN ('users','identities') ORDER BY 1;"], composeEnv);
    requireSuccess(schemaCheck, 'Auth schema diagnostics');
    console.log(schemaCheck.stdout.trim());
    anonKey = makeAnonKey(jwtSecret);
    const email = `local-auth-${randomBytes(12).toString('hex')}@example.invalid`;
    const password = `${randomBytes(24).toString('base64url')}Aa7!`;
    for (const secret of [anonKey, email, password]) diagnosticSecrets.add(secret);

    const signup = await request('/auth/v1/signup', { email, password });
    if (!signup.id && !signup.user?.id) throw new Error('Signup response did not include a user.');
    console.log('Signup: passed.');

    const signin = await request('/auth/v1/token?grant_type=password', { email, password });
    if (!signin.access_token || !signin.refresh_token) throw new Error('Password sign-in did not issue a session.');
    console.log('Password sign-in: passed.');

    const refreshed = await request('/auth/v1/token?grant_type=refresh_token', { refresh_token: signin.refresh_token });
    if (!refreshed.access_token || !refreshed.refresh_token) throw new Error('Refresh did not issue a rotated session.');
    console.log('Refresh: passed.');

    const signedOut = await fetch(`${expectedUrl}/auth/v1/logout`, {
      method: 'POST',
      headers: { apikey: anonKey, Authorization: `Bearer ${refreshed.access_token}` },
      signal: AbortSignal.timeout(15000),
    });
    if (!signedOut.ok) throw new Error(`Sign-out failed with HTTP ${signedOut.status}.`);
    console.log('Sign-out: passed.');
    if (process.argv.includes('--sdk')) {
      const sdk = run('bash', [path.resolve(projectDir, '../scripts/ios/local-auth-sdk-test.sh'),
        ...(process.argv.includes('--all') ? ['--all'] : [])], {
        ...childEnv,
        DEVELOPER_DIR: '/Applications/Xcode.app/Contents/Developer',
        LOCAL_AUTH_LAB_URL: expectedUrl,
        LOCAL_AUTH_LAB_ANON_KEY: anonKey,
      });
      if (sdk.error || sdk.status !== 0) {
        const output = `${sdk.stdout ?? ''}\n${sdk.stderr ?? ''}`;
        console.error(`SDK runner exit: ${sdk.status}.`);
        const resultPath = output.match(/\/[^\n\r]*\/auth-local-sdk-[A-Za-z0-9-]+\.xcresult/)?.[0];
        if (resultPath) console.error(`SDK result bundle: ${resultPath}`);
        for (const [label, pattern] of [
          ['XcodeGen project generation error', /Error Domain=NSCocoaErrorDomain/],
          ['missing isolated spec', /isolated XcodeGen spec is missing/],
          ['SDK tests skipped or failed', /did not execute exactly two passing tests/],
          ['Xcode build or test failure', /TEST FAILED|BUILD FAILED|xcodebuild: error/],
        ]) if (pattern.test(output)) console.error(`SDK runner: ${label}.`);
      }
      requireSuccess(sdk, 'Swift SDK Auth tests');
      // Suppress build output; deliver only the aggregate counts and result path.
      const summaryLines = sdk.stdout.split(/\r?\n/).filter((line) =>
        line.startsWith('SDK Auth tests:') || line.startsWith('SDK auth result bundle:'));
      console.log(summaryLines.join('\n'));
      stopLab();
      labStarted = false;
      console.log('Result: REST and Swift SDK Auth checks passed; isolated lab cleaned.');
    } else {
      console.log(`Result: all Auth checks passed at ${expectedUrl}; lab remains running.`);
    }
  }
} catch (error) {
  if (labStarted && process.argv[2] !== '--stop') reportContainerStartupDiagnostics(labEnvironment);
  if (labStarted) {
    try {
      stopLab();
    } catch {}
  }
  console.error(`Auth lab failed: ${error.message}`);
  process.exitCode = 1;
}
