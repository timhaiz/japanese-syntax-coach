# 日句 iOS 原生首版 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不回退现有 Web 体验的前提下，把日句的核心学习、原生认证、进度同步和 StoreKit 订阅实现为可重复构建的 SwiftUI iOS 首版。

**Architecture:** SwiftUI 原生页面通过 Supabase Swift Auth 管理会话，使用 Bearer token 调用现有 Next.js API；Next.js 服务端同时支持 Cookie 与 Bearer，并继续用 RPC 写入学习数据。现有 TypeScript 教材/题库生成版本化 JSON，作为 iOS 内置教材包；离线仅缓存已加载内容与待提交答题，提交由服务端幂等键保护。StoreKit 2 交易先服务端验签同步，成功后才 finish。

**Tech Stack:** SwiftUI、StoreKit 2、Supabase Swift SDK（SPM）、Next.js App Router、Supabase SSR/JS、PostgreSQL RPC、TypeScript、Playwright、XcodeGen、XCTest。

## Global Constraints

- 开发目录：`/Users/zhang/Documents/japanese-syntax-coach-ios-native`，分支 `ios-native-app`；不得覆盖 `/Users/zhang/Documents/japanese-syntax-coach` 的现有未提交改动。
- iOS deployment target 保持 iOS 16.0；Bundle ID 保持 `com.juxintong.nihongo`。
- 网站端 Cookie 认证必须继续工作；原生客户端只使用 Supabase anon key，不得包含 service-role key。
- 认证首版必须保留邮箱密码注册/登录、邮件验证码、密码重置和 Apple 登录。
- 商品 ID 保持 `com.juxintong.nihongo.monthly` 与 `com.juxintong.nihongo.yearly`。
- 本阶段不创建 App Store Connect 记录、不上传构建、不提交审核。
- 用户已明确允许只在 `ios-native-app` 隔离分支进行本地提交；不得 push 到远端。
- 任何修改服务端数据库的迁移都必须先有本地测试与明确用户确认；不可重复执行已应用的 Apple 归属迁移；本计划仅准备新迁移，不执行远端应用。
- 每个任务完成后运行该任务的专属检查；不要把模拟器构建结果描述为真机签名或 App Store 上传成功。

---

### Task 1: 建立可测试的 Bearer/Cookie Supabase 服务端客户端

**Files:**
- Modify: `lib/supabase-server.ts`
- Create: `lib/auth/request-supabase.ts`（若实现需要拆分请求认证）
- Test: `tests/e2e/architecture.spec.ts` 和新增 `tests/e2e/auth-contract.spec.ts`

**Interfaces:**
- Produces `getSupabaseServer(request?: Request): Promise<SupabaseClient | null>`，Bearer 存在时用 token 创建服务端客户端，否则沿用 SSR cookies。
- Produces `getAuthenticatedSupabase(request: Request): Promise<{ supabase: SupabaseClient; user: User } | { response: NextResponse }>`，所有受保护 API 从此入口获得 user。

- [ ] **Step 1: Write the failing contract test**

在测试中读取服务端认证封装和至少三个受保护路由，断言存在 Authorization Bearer 解析、`auth.getUser(token)` 路径，并断言路由没有从请求 body/query 接受 user ID 作为身份来源。

```ts
const source = readFileSync(resolve(process.cwd(), 'lib/supabase-server.ts'), 'utf8')
expect(source).toContain('Authorization')
expect(source).toContain('Bearer')
expect(source).toContain('getUser')
for (const route of ['study-state', 'record-answer', 'membership']) {
  const routeSource = readFileSync(resolve(process.cwd(), `app/api/${route}/route.ts`), 'utf8')
  expect(routeSource).not.toMatch(/body\.userId|searchParams\.get\(['"]userId/)
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `npx playwright test tests/e2e/architecture.spec.ts --grep "Bearer"`
Expected: FAIL because `lib/supabase-server.ts` currently only creates a cookie client.

- [ ] **Step 3: Implement the minimal dual-auth factory**

解析 `request.headers.get('authorization')`，仅接受 `Bearer <non-empty-token>`；使用 `createClient(url, anonKey, { global: { headers: { Authorization: ... } }, auth: { autoRefreshToken: false, persistSession: false } })`，再通过 `auth.getUser(token)` 验证。无 Bearer 时保持 `createServerClient` 的 cookie 逻辑。抽出 `getAuthenticatedSupabase`，统一返回 401 response，禁止信任客户端 user ID。

- [ ] **Step 4: Migrate protected routes and preserve website behavior**

将 `study-state`、`record-answer`、`membership`、`apple/entitlements`、`account/delete` 和 TTS 受保护路由改为传入 Request 使用统一认证入口；保留已有 Cookie 调用语义。对匿名会员查询保持现有 `/api/membership` 行为，仅需要用户的端点返回 401。

- [ ] **Step 5: Run focused and existing tests**

Run: `npx playwright test tests/e2e/architecture.spec.ts tests/e2e/question-bank.spec.ts`
Expected: PASS；若需要数据库/环境变量的测试，明确记录跳过原因，不伪报通过。

- [ ] **Step 6: Commit the reviewed task locally**

```bash
git add lib/supabase-server.ts lib/auth/request-supabase.ts app/api tests/e2e/architecture.spec.ts tests/e2e/auth-contract.spec.ts
git commit -m "feat: support bearer auth for native clients"
```

Do not push or deploy.

---

### Task 2: 为答题记录增加服务端幂等键和旧数据兼容边界

**Files:**
- Create: `supabase/migrations/202610291400_native_answer_idempotency.sql`（执行前用 `supabase migration list --project-ref ecegssnkpyyjrufgtepq` 确认版本未存在；如已存在则停止并调查，不改写历史迁移）
- Modify: `app/api/record-answer/route.ts`
- Modify: 相关 RPC 定义/迁移文件（若必须新增参数，新增迁移而不改历史迁移）
- Test: `tests/e2e/architecture.spec.ts` 和新增 `tests/e2e/record-answer-idempotency.spec.ts`

**Interfaces:**
- Request body accepts `clientRequestId?: string`，格式限制为 UUID 或长度受限的安全字符串。
- API forwards the idempotency key to an atomic RPC or a unique persistence table and returns `{ duplicate: true, record }` on replay.
- Existing website callers omitting the key remain valid but do not receive native queue guarantees.

- [ ] **Step 1: Write the failing contract test**

```ts
const source = readFileSync(resolve(process.cwd(), 'app/api/record-answer/route.ts'), 'utf8')
expect(source).toContain('clientRequestId')
expect(source).toContain('duplicate')
const migration = readFileSync(resolve(process.cwd(), migrationPath), 'utf8')
expect(migration).toContain('unique')
```

- [ ] **Step 2: Run test and verify it fails**

Run: `npx playwright test tests/e2e/architecture.spec.ts --grep "idempot"`
Expected: FAIL because current request body and RPC have no client request ID.

- [ ] **Step 3: Implement the smallest database-backed idempotency design**

Add a user-scoped table with `user_id + client_request_id` unique constraint and stored response/record reference, or extend the existing atomic learning RPC if its schema makes that safer. The RPC must authenticate by `auth.uid()`, reject mismatched user IDs, return the existing record for an already-seen key, and insert exactly once for a new key. Do not use an in-memory map.

- [ ] **Step 4: Add API validation and replay response**

Validate key length and character set before calling Supabase. Pass it to the RPC; return 400 for malformed values, 401 for missing auth, 500/503 for unavailable persistence, and a stable duplicate response for a replay. Preserve legacy RPC fallback only for requests without a key.

- [ ] **Step 5: Run static and migration checks**

Run: `npx playwright test tests/e2e/architecture.spec.ts --grep "idempot"`
Run: `npx supabase db lint --local`
Expected: focused test PASS; local lint either PASS or reports a documented local database prerequisite.

- [ ] **Step 6: Commit migration source locally after review**

Review migration SQL, auth boundaries, diff and test output. Commit source and tests on the isolated branch only. Do not apply the migration remotely without separate explicit confirmation.

```bash
git add app/api/record-answer/route.ts supabase/migrations tests/e2e/record-answer-idempotency.spec.ts
git commit -m "feat: make native answer retries idempotent"
```

---

### Task 3: 保留并兼容旧 `user_metadata.learning_progress`

**Files:**
- Create: `app/api/learning-progress/route.ts`（仅当现有接口不能安全读取 legacy metadata 时）
- Modify: `app/api/study-state/route.ts`
- Modify: `lib/supabase-server.ts`（只在 Task 1 未涵盖的数据读取路径需要时）
- Test: `tests/e2e/learning-progress-compat.spec.ts`

**Interfaces:**
- `GET /api/study-state` returns structured progress and a separately normalized `legacyProgress` payload with `legacyProgressAvailable: boolean` when present.
- The API never merges legacy metadata with structured counters, mutates either store on GET, or silently hides legacy progress; iOS displays both clearly until an explicit migration is reviewed and approved.

- [ ] **Step 1: Add failing compatibility tests**

Test three cases: (a) only legacy metadata exists and both response shape and legacy payload are returned without mutation, (b) structured rows and legacy metadata both exist and both are returned in separate fields, (c) no legacy data returns `legacyProgressAvailable: false` and the current empty structured shape. Assert API never calls `auth.updateUser` or overwrites `user_metadata` during a GET.

- [ ] **Step 2: Run focused test and verify it fails**

Run: `npx playwright test tests/e2e/learning-progress-compat.spec.ts`
Expected: FAIL because `/api/study-state` currently does not read or report legacy metadata.

- [ ] **Step 3: Inspect data timestamps and define deterministic precedence**

Use a read-only query against a non-production fixture or mocked data. Since legacy metadata has a single `updatedAt` and structured state uses answer events, return both stores in separate fields whenever present; do not choose one as a destructive replacement, and do not merge counters by summation. Preserve raw metadata unchanged until a manual one-time migration plan is separately approved.

- [ ] **Step 4: Implement read-only fallback and normalization**

Use the authenticated Supabase user object to read `user_metadata.learning_progress`, validate shape/version, scope by `builtin-japanese-syntax`, normalize counts/mistakes against the packaged question IDs, and return the legacy snapshot separately with `legacyProgressAvailable`. No mutation from this endpoint.

- [ ] **Step 5: Run focused tests and API regression tests**

Run: `npx playwright test tests/e2e/learning-progress-compat.spec.ts tests/e2e/question-bank.spec.ts`
Expected: PASS for precedence and legacy preservation.

- [ ] **Step 6: Commit compatibility code locally after review**

Review data precedence, privacy and test output. Commit only on the isolated branch; do not mutate remote user metadata.

```bash
git add app/api/study-state/route.ts app/api/learning-progress/route.ts tests/e2e/learning-progress-compat.spec.ts
git commit -m "fix: preserve legacy learning progress for native clients"
```

---

### Task 4: 生成版本化教材 JSON 和 Swift Codable 模型

**Files:**
- Create: `scripts/textbook/export-ios-package.mjs`
- Create: `ios/JapaneseSyntaxCoach/Models/TextbookModels.swift`
- Create: `ios/JapaneseSyntaxCoach/Resources/builtin-japanese-syntax.json` (copied/generated build resource)
- Modify: `package.json`
- Modify: `ios/project.yml` (add explicit `JapaneseSyntaxCoachTests` unit-test target)
- Create: `ios/JapaneseSyntaxCoachTests/TextbookRepositoryTests.swift`
- Test: `tests/e2e/architecture.spec.ts`

**Interfaces:**
- Node script `node scripts/textbook/export-ios-package.mjs --output ios/JapaneseSyntaxCoach/Resources/builtin-japanese-syntax.json` writes deterministic JSON with `schemaVersion`, `contentHash`, and `textbook`.
- Swift `TextbookPackage: Decodable` validates schema version and exposes `Textbook`, `TextbookLesson`, `TextbookQuestion`.
- `TextbookRepository.loadBundled() throws -> TextbookPackage` loads the exact resource from the bundle.

- [ ] **Step 1: Write the failing export/model contract test**

```ts
expect(existsSync(resolve(process.cwd(), 'scripts/textbook/export-ios-package.mjs'))).toBeTruthy()
const packageJson = JSON.parse(readFileSync(resolve(process.cwd(), 'ios/JapaneseSyntaxCoach/Resources/builtin-japanese-syntax.json'), 'utf8'))
expect(packageJson.schemaVersion).toBe(1)
expect(packageJson.contentHash).toMatch(/^[a-f0-9]{64}$/)
expect(packageJson.textbook.id).toBe('builtin-japanese-syntax')
expect(packageJson.textbook.questions.length).toBeGreaterThan(100)
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `npx playwright test tests/e2e/architecture.spec.ts --grep "versioned textbook"`
Expected: FAIL because no iOS export script/resource exists.

- [ ] **Step 3: Implement deterministic TypeScript export**

Import `builtInTextbookPackage`, serialize stable key order, compute SHA-256 over canonical textbook payload, add `contentHash`, and write UTF-8 JSON with a fixed trailing newline. Add `textbook:export:ios` to `package.json`.

- [ ] **Step 4: Implement Swift Codable models and repository**

Keep model fields aligned with `lib/textbooks.ts`: question type, IDs, prompt, answer, hint, optional options/acceptedAnswers; lesson grammar fields including optional audio/responses/pitfalls. Reject unsupported schema versions and missing IDs with user-visible load errors.

- [ ] **Step 5: Add the generated resource to XcodeGen and verify bundle loading**

Configure `ios/project.yml` resources so the JSON is included exactly once. Add a small XCTest target if the project has no test target; test schema, lesson count, question count, deterministic content hash presence, and question ordering.

- [ ] **Step 6: Run export and tests**

Run: `npm run textbook:export:ios`
Run: `npx playwright test tests/e2e/architecture.spec.ts --grep "versioned textbook"`
Run: `xcodegen generate --spec ios/project.yml`
Expected: generated JSON exists, contract test passes, Xcode project regenerates without duplicate resource errors.

- [ ] **Step 7: Commit the reviewed textbook package locally**

Inspect generated resource size and deterministic output, then commit only on the isolated branch.

```bash
git add scripts/textbook package.json ios/JapaneseSyntaxCoach ios/project.yml tests/e2e/architecture.spec.ts
git commit -m "feat: package versioned textbook content for ios"
```

---

### Task 5: 接入 Supabase Swift Auth、Keychain 会话和深链回调

**Files:**
- Modify: `ios/project.yml`
- Modify: `ios/JapaneseSyntaxCoach/JapaneseSyntaxCoachApp.swift`
- Replace: `ios/JapaneseSyntaxCoach/ContentView.swift`
- Create: `ios/JapaneseSyntaxCoach/Auth/AuthSessionStore.swift`
- Create: `ios/JapaneseSyntaxCoach/Auth/AuthView.swift`
- Create: `ios/JapaneseSyntaxCoach/Auth/AuthCallbackRouter.swift`
- Create: `ios/JapaneseSyntaxCoach/Networking/APIClient.swift`
- Modify: `ios/JapaneseSyntaxCoach/Info.plist`
- Modify: `ios/JapaneseSyntaxCoach/JapaneseSyntaxCoach.entitlements`
- Test: `ios/JapaneseSyntaxCoachTests/AuthSessionStoreTests.swift`

**Interfaces:**
- `AuthSessionStore` publishes `phase: AuthPhase`, `session`, `userEmail`, `errorMessage`; methods `signIn`, `signUp`, `verifySignupCode`, `requestPasswordReset`, `signInWithApple`, `handle(url:)`, `signOut`.
- `APIClient.request<T: Decodable>(_: URLRequest) async throws -> T` appends current Bearer token and retries one 401 after session refresh.
- `AuthCallbackRouter.route(_ url: URL) -> AuthCallback` handles signup/recovery/Apple callbacks without treating arbitrary URLs as auth callbacks.

- [ ] **Step 1: Write failing XCTest cases**

Cover callback classification, malformed callback rejection, logout clearing Keychain/session, and API request header injection using a mock token provider.

```swift
func testCallbackRouterRejectsUntrustedURL() {
    XCTAssertEqual(AuthCallbackRouter.route(URL(string: "https://example.com/?code=x")!), .ignored)
}
```

- [ ] **Step 2: Run XCTest and verify failure**

Run: `xcodebuild -project ios/JapaneseSyntaxCoach.xcodeproj -scheme JapaneseSyntaxCoach -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test CODE_SIGNING_ALLOWED=NO`
Expected: FAIL because native auth files/test target are absent.

- [ ] **Step 3: Add Supabase Swift package and app configuration**

Add the pinned Supabase Swift package URL/version supported by current Xcode; keep anon URL/key in build configuration or Info.plist placeholders, never service role. Add URL scheme/associated-domain configuration needed for callbacks and Apple capability entitlement without adding secrets.

- [ ] **Step 4: Implement session store and auth views**

Restore session at launch, subscribe to auth state changes, persist through SDK Keychain storage, and expose loading/error/verified-email states. Implement email/password login, signup, six-digit OTP verification, password reset, Apple credential exchange, logout and callback handling. Prevent duplicate submits and display retryable errors.

- [ ] **Step 5: Implement API client**

Use a protocol-based session token provider for tests. Attach `Authorization: Bearer`; refresh exactly once on 401; map 401/403/offline/5xx into typed errors. Do not fall back to website cookies from native requests.

- [ ] **Step 6: Run unit tests and simulator build**

Run the XCTest command above and:
`xcodebuild -project ios/JapaneseSyntaxCoach.xcodeproj -scheme JapaneseSyntaxCoach -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: auth tests and build pass.

- [ ] **Step 7: Commit the reviewed auth implementation locally**

Review auth flows, callback allowlist and test output. Commit only on the isolated branch; do not enable external OAuth settings without approval.

```bash
git add ios
git commit -m "feat: add native supabase authentication"
```

---

### Task 6: 实现原生教材、首页、课程、整课答题和进度

**Files:**
- Create: `ios/JapaneseSyntaxCoach/Learning/LearningStore.swift`
- Create: `ios/JapaneseSyntaxCoach/Learning/AnswerEvaluator.swift`
- Create: `ios/JapaneseSyntaxCoach/Learning/OfflineAnswerQueue.swift`
- Create: `ios/JapaneseSyntaxCoach/Learning/HomeView.swift`
- Create: `ios/JapaneseSyntaxCoach/Learning/TextbookView.swift`
- Create: `ios/JapaneseSyntaxCoach/Learning/LessonView.swift`
- Create: `ios/JapaneseSyntaxCoach/Learning/QuestionView.swift`
- Create: `ios/JapaneseSyntaxCoach/Learning/ProgressView.swift`
- Create: `ios/JapaneseSyntaxCoach/Learning/LearningStateModels.swift`
- Modify: `ios/JapaneseSyntaxCoach/ContentView.swift`
- Test: `ios/JapaneseSyntaxCoachTests/AnswerEvaluatorTests.swift`
- Test: `ios/JapaneseSyntaxCoachTests/OfflineAnswerQueueTests.swift`

**Interfaces:**
- `AnswerEvaluator.evaluate(question: TextbookQuestion, answer: String) -> LocalEvaluation`.
- `OfflineAnswerQueue.enqueue(_ item: PendingAnswer)`, `peek()`, `remove(id:)`, `retry(using:) async`.
- `LearningStore.loadStudyState() async`, `submit(_ answer: AnswerSubmission) async`, `retryPending() async`.

- [ ] **Step 1: Write failing evaluator and queue tests**

Cover accepted choices, normalized text, needs-fix similarity, stable UUID client request IDs, FIFO retry, failed-item retention and corrupted persistence recovery.

- [ ] **Step 2: Run focused XCTest and verify failure**

Run: `xcodebuild -project ios/JapaneseSyntaxCoach.xcodeproj -scheme JapaneseSyntaxCoach -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:JapaneseSyntaxCoachTests/AnswerEvaluatorTests -only-testing:JapaneseSyntaxCoachTests/OfflineAnswerQueueTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL because types are absent.

- [ ] **Step 3: Implement evaluator from existing semantics**

Mirror `normalizeAnswer`/`isAnswerAccepted` behavior for the four question types. Return verdict, correctness, expected answer, and feedback; do not introduce a new grading rule that diverges from the website without a test documenting it.

- [ ] **Step 4: Implement local persistence and API DTOs**

Persist cached textbook and queue in application support using Codable and atomic file replacement. Use `/api/study-state` and `/api/record-answer`; include textbook ID, question/lesson IDs, answer, verdict, tags, mode, question limit and client request ID. Never send user ID from the client.

- [ ] **Step 5: Implement native navigation and screens**

Create a `TabView` or equivalent root with Home, Textbook, Progress and Account/Subscription entry points. Home shows current lesson, due reviews and sync status. Textbook shows 24 lessons and grammar points. Lesson presents all questions sequentially, supports choice/token/text input, immediate feedback and full-lesson completion. Progress shows completed lessons, metrics and top errors. All loading/error/offline states are explicit.

- [ ] **Step 6: Implement synchronization semantics**

On authenticated launch load cloud study state, preserve local cached content, enqueue answer before network submit, remove only after successful or duplicate response, and show pending count. On logout/delete clear user-scoped queue and cached progress. Do not overwrite cloud state with a client snapshot.

- [ ] **Step 7: Run focused tests, E2E regression and build**

Run XCTest focused tests, `npx playwright test tests/e2e/lesson-flow.spec.ts tests/e2e/question-bank.spec.ts`, then simulator Release build. Expected: native tests pass, website tests pass, build succeeds.

- [ ] **Step 8: Commit the reviewed native learning UI locally**

Review native navigation, data persistence and website regression output. Commit only on the isolated branch.

```bash
git add ios/JapaneseSyntaxCoach ios/JapaneseSyntaxCoachTests
git commit -m "feat: build native learning experience"
```

---

### Task 7: 完成 StoreKit 2、账户页、订阅同步和注销清理

**Files:**
- Modify: `ios/JapaneseSyntaxCoach/StoreKitManager.swift`
- Create: `ios/JapaneseSyntaxCoach/Billing/SubscriptionView.swift`
- Create: `ios/JapaneseSyntaxCoach/Billing/AccountView.swift`
- Create: `ios/JapaneseSyntaxCoach/Billing/EntitlementSync.swift`
- Modify: `ios/JapaneseSyntaxCoach/ContentView.swift`
- Modify: `ios/JapaneseSyntaxCoach/Info.plist`
- Test: `ios/JapaneseSyntaxCoachTests/StoreKitStateTests.swift`

**Interfaces:**
- `StoreKitManager.purchase(productID:) async -> PurchaseState`.
- `StoreKitManager.restorePurchases() async -> RestoreState`.
- `EntitlementSync.submit(signedTransaction:) async throws -> MembershipState`.
- Account deletion invokes `POST /api/account/delete` with confirmation and clears `AuthSessionStore` plus `LearningStore` user data.

- [ ] **Step 1: Write failing StoreKit state tests**

Test mapping of unavailable product, user cancellation, pending purchase, unverified transaction, server sync failure and successful sync; assert successful transaction is finishable only after sync acknowledgment.

- [ ] **Step 2: Run focused XCTest and verify failure**

Run: `xcodebuild -project ios/JapaneseSyntaxCoach.xcodeproj -scheme JapaneseSyntaxCoach -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:JapaneseSyntaxCoachTests/StoreKitStateTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL because the new state model and sync boundary are absent.

- [ ] **Step 3: Refactor StoreKit manager around server acknowledgment**

Keep product IDs from `AppConfiguration`; set `appAccountToken` from authenticated UUID; on verified purchase submit JWS to `/api/apple/entitlements`; finish only after accepted or duplicate acknowledgment. Persist retryable signed transactions in a user-scoped queue. Observe `Transaction.updates` with the same path.

- [ ] **Step 4: Build subscription and account screens**

Show localized `Product.displayPrice`, period, auto-renewal disclosure, privacy/terms links, purchase, restore, manage subscriptions, account email, membership status, sync status, logout and destructive account deletion confirmation. Do not claim membership until `/api/membership` confirms it.

- [ ] **Step 5: Add deletion cleanup and accessibility labels**

On successful deletion clear session, local queue, cached progress and user-scoped files; on failure preserve state and offer retry. Add VoiceOver labels, dynamic type-safe layouts, reduced-motion handling and keyboard focus where applicable.

- [ ] **Step 6: Run tests and simulator build**

Run StoreKit-focused XCTest, website E2E regression, and Release simulator build. Sandbox purchase/recovery requires a real configured Apple account and is a manual acceptance step; do not mark it passed from simulator compilation alone.

- [ ] **Step 7: Commit the reviewed StoreKit/account work locally**

Review StoreKit finish ordering, account deletion cleanup and all test output. Commit only on the isolated branch.

```bash
git add ios/JapaneseSyntaxCoach ios/JapaneseSyntaxCoachTests
git commit -m "feat: add native subscriptions and account controls"
```

---

### Task 8: 发布前检查、材料草稿和最终验证

**Files:**
- Modify: `ios/README.md`
- Modify: `docs/ios/app-store-launch-checklist.md`
- Create: `docs/ios/app-store-metadata-draft.md`
- Create: `docs/ios/test-matrix.md`
- Create: `artifacts/ios/` generated logs only

**Interfaces:**
- Documentation lists exact bundle ID, product IDs, URLs, required Apple capabilities, reviewer test flow, privacy disclosures and known manual prerequisites.
- No document claims ASC record creation, upload, signature, or review submission unless independently completed and authorized.

- [ ] **Step 1: Run the full automated validation**

Run:
`npm run build`
`npx playwright test`
`xcodegen generate --spec ios/project.yml`
`xcodebuild -project ios/JapaneseSyntaxCoach.xcodeproj -scheme JapaneseSyntaxCoach -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
`xcodebuild -project ios/JapaneseSyntaxCoach.xcodeproj -scheme JapaneseSyntaxCoach -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test CODE_SIGNING_ALLOWED=NO`

Record each command and result in `artifacts/ios/validation.log`; distinguish PASS, FAIL and SKIPPED prerequisites.

- [ ] **Step 2: Perform at most two visual/manual inspection rounds**

Inspect onboarding, login, home, textbook, lesson, progress, subscription and account screens on at least one iPhone simulator size; check loading/error/offline states, dynamic type and VoiceOver labels. Fix only clearly broken issues within scope.

- [ ] **Step 3: Prepare metadata draft**

Document app name `日句`, subtitle/description draft, keywords, support URL, privacy URL, terms URL, account deletion instructions, subscription disclosures, review notes and Sandbox test-account placeholders. Mark all account-holder actions as pending.

- [ ] **Step 4: Stop for final review checkpoint**

Review the metadata draft, validation log and outstanding ASC/signing prerequisites. Leave all changes uncommitted and do not upload or submit.

- [ ] **Step 5: Final report**

Report changed files, tests run, tests skipped and why, simulator build status, signing/archive status, ASC status, and explicit remaining manual steps. Do not upload or submit without a separate user confirmation.
