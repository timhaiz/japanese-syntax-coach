import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const root = new URL('../', import.meta.url);
const source = async (path) => readFile(new URL(path, root), 'utf8');

test('LearningStore routes all learning API calls through its injected base URL', async () => {
  const store = await source('ios/JapaneseSyntaxCoach/Learning/LearningStore.swift');
  assert.match(store, /apiBaseURL:\s*URL\s*=\s*AppConfiguration\.webURL/);
  assert.match(store, /apiBaseURL\.appendingPathComponent\("api\/study-state"\)/);
  assert.match(store, /apiBaseURL\.appendingPathComponent\("api\/record-answer"\)/);
  assert.match(store, /apiBaseURL\.appendingPathComponent\("api\/account\/delete"\)/);
  assert.doesNotMatch(store, /AppConfiguration\.webURL\.appendingPathComponent\("api\/(?:study-state|record-answer|account\/delete)"\)/);
});

test('dual-client XCTest project is isolated and runner enforces fixed local targets', async () => {
  const project = await source('scripts/ios/dual-client-project.yml');
  const runner = await source('scripts/ios/dual-client-sdk-test.sh');
  const swiftTests = await source('ios/JapaneseSyntaxCoachTests/DualClientLabTests.swift');
  assert.match(project, /path: JapaneseSyntaxCoachTests\/DualClientLabTests\.swift/);
  assert.doesNotMatch(project, /PendingTransactionQueueReentrancyTests|PendingTransactionQueueCorruptionBackupTests/);
  assert.doesNotMatch(runner, /510E97CE-798B-4D14-A2A6-0792B8551502/);
  assert.match(runner, /simctl create/);
  assert.match(runner, /simctl shutdown "\$SIMULATOR_ID"/);
  assert.doesNotMatch(runner, /simctl (?:erase|delete)/);
  assert.match(runner, /http:\/\/127\.0\.0\.1:54351/);
  assert.match(runner, /http:\/\/127\.0\.0\.1:3219/);
  assert.match(swiftTests, /authURL\.absoluteString == "http:\/\/127\.0\.0\.1:54351"/);
  assert.match(swiftTests, /webURL\.absoluteString == "http:\/\/127\.0\.0\.1:3219"/);
  assert.match(swiftTests, /LOCAL_DUAL_ANON_KEY/);
});
