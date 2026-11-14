import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const store = readFileSync('ios/JapaneseSyntaxCoach/Learning/LearningStore.swift', 'utf8')
const view = readFileSync('ios/JapaneseSyntaxCoach/Learning/HomeView.swift', 'utf8')

test('legacy queue notice checks only the old email-derived path', () => {
  assert.match(store, /@Published private\(set\) var hasPossibleLegacyQueue = false/)
  assert.match(store, /hasPossibleLegacyQueue = legacyQueueExists\(email: session\?\.email\)/)
  assert.match(store, /hasPossibleLegacyQueue = false/)
  const helper = store.match(/private func legacyQueueExists\(email: String\?\) -> Bool \{([\s\S]*?)\n    \}/)?.[1]
  assert.ok(helper)
  assert.match(helper, /trimmingCharacters\(in: \.whitespacesAndNewlines\)\.lowercased\(\)/)
  assert.match(helper, /SHA256\.hash/)
  assert.match(helper, /attributesOfItem\(atPath: queueURL\(for: digest\)\.path\)/)
  assert.match(helper, /NSFileNoSuchFileError/)
  assert.match(helper, /NSFileReadNoSuchFileError/)
  assert.match(helper, /catch \{ return true \}/)
  assert.doesNotMatch(helper, /Data\(contentsOf:|OfflineAnswerQueue|removeItem|write\(/)
})

test('sync view warns legacy data is not counted or synced', () => {
  assert.match(view, /if model\.showsSyncStatus \|\| store\.hasPossibleLegacyQueue/)
  assert.match(view, /if store\.hasPossibleLegacyQueue/)
  assert.match(view, /旧版待同步数据/)
  assert.match(view, /请勿清除应用数据/)
})

test('home sync row also distinguishes unreadable counts from zero', () => {
  const section = view.split('private struct HomeSyncStatusRow: View')[1]?.split('extension HomeView')[0] ?? ''
  assert.match(section, /store\.pendingCountIsKnown/)
  assert.match(section, /待同步答案：数量未知（队列无法读取）/)
})

test('shared LearningSyncStatusView reports unknown pending count when queue is unreadable and exposes retry accessibility ID', () => {
  const sharedSection = view.split('struct LearningSyncStatusView: View')[1] ?? ''
  assert.ok(sharedSection.length > 0, 'LearningSyncStatusView should exist in HomeView.swift')
  assert.match(sharedSection, /store\.pendingCountIsKnown/)
  assert.match(sharedSection, /待同步答案：数量未知（队列无法读取）/)
  assert.match(sharedSection, /\.accessibilityIdentifier\("pendingAnswerCount"\)/)
  assert.match(sharedSection, /\.accessibilityIdentifier\("legacyQueueNotice"\)/)
  assert.match(sharedSection, /\.accessibilityIdentifier\("homeSyncRetry"\)/)
  assert.match(sharedSection, /\.accessibilityLabel\("刷新或重试同步"\)/)
})
