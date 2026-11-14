# App Store 发布前检查清单

适用范围：`japanese-syntax-coach` 原生 iOS 客户端（Bundle ID `com.juxintong.nihongo`）。

**当前状态：第 1 节分别列出当前 worktree 的有限检查与 `ios-native-app` 分支的历史记录；均不代表已满足上架条件。**
其余条目未在本清单中确认完成；App Store Connect 状态、签名归档、上传和提交审核均需另行核实，
涉及上传或提交时必须事先获得明确授权。发布前应以当前代码和新鲜的验证记录为准。

图例：`[ ]` 未执行 · `[x]` 已完成并已验证

---

## 1. 代码与构建

**当前 worktree 最近检查（2026-11-04，非签名构建）：**

- Release、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO` 的 `xcodebuild build` 退出码为 0（2026-11-04）；这不是签名归档或设备测试。构建包 Info.plist 为版本 `1.0.0`、构建号 `1`；App 隐私清单与源文件字节一致，且包内含 `swift-crypto` 自身的隐私清单。Release 包含格式有效且非空的 Supabase 运行时配置字段（仅检查存在性，未显示值，也未测试连接）；对 Release 可执行文件的有限标记扫描未发现 service-role key 或 PEM 私钥标记，不构成完整秘密扫描。需在实际归档后重新核对 SDK 清单和构建号唯一性。
- `npx tsc --noEmit` 在当前 worktree 退出码为 0（2026-11-04）。
- `npm run build` 在当前 worktree 通过（2026-11-04）：Next.js 16.3.4 编译和 TypeScript 检查完成，生成 25 个静态页面；这不代表线上版本已部署。
- Debug、通用 iOS 设备的 `build-for-testing` 使用 `-jobs 1` 构建成功（2026-11-04）。20:17 在独立 DerivedData 目录进行的完整重编译未复现此前记录的 `AuthService` actor 隔离或 XCTest 部署目标链接警告；仅见因未依赖 `AppIntents.framework` 而跳过元数据提取的提示。仅构建测试包，未运行 XCTest；此前警告记录保留为早先构建结果，不据此推断测试已运行或实际设备行为。
- 本地离线测试复跑（2026-11-05）：ESM `tests/*.offline.test.mjs` 154 通过、0 失败；Apple 通知日志 CJS 23 通过、0 失败；隐私清单 Python 2 通过。独立 StoreKit 离线替身脚本最近一次记录为 2026-11-04 全部 PASS（不是 XCTest）。Node 对若干 `.ts` 文件输出 `MODULE_TYPELESS_PACKAGE_JSON` 性能提示；测试通过不替代真实 StoreKit、SDK、Keychain 或设备验证。
- 2026-11-05 刷新检查：`npx tsc --noEmit` 与 `npm run build` 通过，Next.js 生成 25 个静态页面。使用 `/Applications/Xcode.app/Contents/Developer` 执行 Release、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO` 构建成功；Debug `build-for-testing` 也成功，仅编译 XCTest bundle，未运行 XCTest。Xcode 提示因未依赖 `AppIntents.framework` 而跳过元数据提取；`build-for-testing` 另有 test host 未列入 preferred buildables、但在 workspace-wide search 中找到的警告。首次调用因活动开发者目录指向 Command Line Tools 而失败，随后通过命令级 `DEVELOPER_DIR` 完成；未更改全局开发者目录、未签名归档或启动模拟器。
- 后续 TTS publisher fencing 离线验证中再次运行根级 `npx tsc --noEmit`，本次退出码为 2：`build/current-ios-release-validation/SourcePackages/checkouts/supabase-swift/Examples/supabase/functions/hello-world/index.ts` 与 `build/isolated-ios-tests/.../index.ts` 的远程 `https://deno.land/...` import 无法解析。根因是根 `tsconfig.json` 的 `**/*.ts` include 扫入 `build/`、而 exclude 仅包含 `node_modules`。因此前一条通过记录是当时检查结果，不代表这次运行；本轮未改 `tsconfig.json`，亦未删除或清理 build 输出。作用范围 adapter 类型检查通过；publisher 离线 Node 合同测试 204/204 通过。这些结果不替代 iOS XCTest、真实设备或 StoreKit 验证。
- 随后在获准的隔离模拟器 `JSC isolated tests`（UUID `81F9065A-F0FF-4D53-ADE7-B6909604354C`）运行 `JapaneseSyntaxCoachTests`：130 passed、0 failed、0 skipped（iOS 27.2，结果 `build/authorized-isolated-xctest-results.xcresult`）。本次通过不代表真机、Apple 登录、StoreKit 沙盒或线上服务验证；未选择或启动原有 iPhone 17 模拟器。
- 再次检查当前 AppIcon asset catalog：9 个 PNG 的实际像素尺寸均与 `Contents.json` 中的逻辑尺寸和 scale 相符；`AppIcon-1024.png` 为 1024×1024 且无 alpha（`sips` 检查，2026-11-05）。

**以下是其他分支的历史记录，不代表当前 worktree 已完成：**

- [x] `xcodegen generate --spec ios/project.yml` 后重新生成的 `project.pbxproj` 已提交
      （重新生成后 `git status` 为空，无漂移）
- [x] `xcodebuild test` 全绿：78 tests，0 failures（记录见 `artifacts/ios/validation.log`）
- [x] `xcodebuild -configuration Release` 成功（**BUILD SUCCEEDED**，模拟器目标）
- [x] `npm run build` 通过；`npx tsc --noEmit` 无错误
- [x] `npx playwright test`：109 通过 / 3 失败；3 项失败在基线 `8b01e69` 上同样复现
      （`lesson-flow.spec.ts:225/241/273`），与本分支无关
- [x] 仓库中不含任何凭据（`git grep -iE "service_role|SUPABASE_SERVICE_ROLE|PRIVATE KEY"`）
- [x] `ios/JapaneseSyntaxCoach/Resources/builtin-japanese-syntax.json` 与网站教材一致
      （重新执行 `npm run textbook:export:ios` 后内容完全相同，contentHash 未变）

## 2026-11-06 本轮验收与下一步安排

- 生产答题同步修复已发布至现有 Vercel 项目。实际生产基线为 `5cd674b`；本次仅合入答题路由、服务端 Supabase 客户端、请求认证 helper 三文件修复。生产部署 `dpl_9dqSUZE1b6WiEJY4hwEzUzDKo5dn` 已接管原域名。
- 生产数据库执行的是经确认的 `artifacts/ios/production-answer-sync-repair.sql`，SHA256 为 `550d61dab71d06aaf765c588c1ab2c29f32c2e06df0d5ed90a67495ef022322a`。已确认五表教材列、辅助函数及幂等 RPC/表存在；这不表示迁移目录或原子错题候选已整体部署。该修复 SQL 留作审计，不应重复执行。
- iPhone 16 在新部署中三次 `POST /api/record-answer` 均为 200，随后 `GET /api/study-state` 为 200；用户确认待同步已清零。只读生产核验得到答案 `340 → 343`、幂等请求 3 条、完成 3 条、未完成 0 条。核验查询：`https://supabase.com/dashboard/project/ecegssnkpyyjrufgtepq/sql/a944bd98-6d7d-4398-9317-443f5afa9025`。
- 用户已确认真机登录恢复、重启后恢复会话、退出再登录。本轮本地再次执行 `codesign --verify --deep --strict build/word-card-device/Build/Products/Debug-iphoneos/JapaneseSyntaxCoach.app` 成功；签名 entitlement 包含团队 `RMBJCSP3G9`、应用标识 `RMBJCSP3G9.com.juxintong.nihongo` 和 `com.apple.developer.applesignin = [Default]`，但 `get-task-allow = true`，该包是开发测试包，不是分发归档。
- `python3 tests/ios-privacy-manifest.offline.test.py` 本轮执行 2 项通过；它仅检查静态契约，不替代最终归档隐私报告与 App Store Connect 问卷。
- 本轮 `security find-identity -v -p codesigning` 仅统计结果：可用 Apple Development 身份 1 个，Apple Distribution 与旧式 iPhone Distribution 均为 0。尚未创建或下载分发证书；本机缺少现成可用的分发签名身份，不等同团队后台没有证书。真机列表确认 iPhone 16 仍为 available (paired)。公开 `/support` 本轮可读取，显示支持邮箱 `service@niixmiro.com`。
- 本轮重新读取线上 `/privacy`、`/terms`、`/subscription`：仍含可在应用中注销、当前月付/年付方案以及恢复购买同步权益的承诺。它们与本地暂停账号删除、新购买和权益同步的状态不一致，仍是提交前阻塞。此次最小答题接口部署没有发布本地政策文案。

- 隔离 `--cross-client` 闭环已实际运行：浏览器 UI 登录并提交错误答案，iOS `LearningStore` 经真实 GoTrue/Next/PostgREST 读取并清除同题，浏览器重新登录刷新后确认空错题本。父会话读取 `build/dual-client-sdk-20261106-231636-88353.xcresult` 得到 4 项通过、0 失败、0 跳过；本轮离线接线检查另有 5 项通过。它仅验证浏览器 UI 与 iOS SDK/XCTest 的顺序协作，不是实际 iOS UI、两端同时竞争或生产原子错题功能的证明。原子错题候选仅在隔离环境启用。

- 隔离屏障竞争最终补测完成（2026-11-07）：`PLAYWRIGHT_BROWSERS_PATH="$PWD/build/playwright-browsers" node scripts/ios/dual-client-lab.mjs --cross-client` 实跑通过。同账号、同题、同预期版本，浏览器 Cookie 请求直接收到 HTTP 200，Swift 测试专用 URLProtocol 从真实 HTTPURLResponse 捕获 409；iOS `LearningStore` 显示版本冲突且队列保留 1 项。双方客户端请求区间重叠 989ms；数据库断言一条答案、一个操作、版本从 0 到 1。父会话读取最终 `build/dual-client-sdk-20261107-001134-27335.xcresult`，确认 1 项通过、0 失败、0 跳过，另复跑接线检查 5 项通过。
- 并发证据范围：这是浏览器与 iOS SDK/XCTest 的受控隔离竞争，使用仅隔离库的 1 秒持锁触发器及 200ms 放行偏置，以稳定覆盖 iOS 失败路径；时间戳证明客户端请求区间重叠，不是数据库锁等待的直接观测。它不证明自然竞争下获胜分布、真实 iOS UI、生产双端并发或原子错题候选已上线。原有 `--web` 和 `--ios` 独立模式亦已实跑，后者 3 项 XCTest 通过。运行器报告已清理自身容器/卷并关闭新建模拟器；端口检查未列出监听，但 lsof 有文件系统 stat 警告，故端口观测可能不完整。

## 2026-11-07 离线重放证据范围复核

- 重新读取既有 `build/dual-client-sdk-20261106-231636-88353.xcresult` 的测试树：`testRealAnswerReplayClearsMistakeAndConflictKeepsQueue()` 为 Passed，同包另三项也为 Passed。这是对历史结果包的复核，本轮没有重跑 XCTest。
- 当前对应源码 `ios/JapaneseSyntaxCoachTests/DualClientLabTests.swift` 使用测试专用 URLProtocol 对下一次答题注入传输失败，断言待同步为 1；随后调用 `retryPending()`，断言真实隔离服务确认后队列为 0、错题版本递增，再覆盖清除错题和陈旧版本冲突保留队列。证据范围是 iOS SDK/XCTest 故障注入与隔离服务往返，不能称为真机物理断网、离线跨进程重启重放或完整双端 UI 验收；当前源码也未据历史结果包证明未发生后续变化。

## 2026-11-07 暂停态与本地上架阻塞复核

- 在指定隔离工作树重新运行 `node --test tests/subscription-paused.offline.test.mjs tests/account-deletion-fail-closed.test.mjs tests/account-deletion-server-contract.test.mjs`：13 项测试中 9 通过、0 失败、4 项标记为 TODO。测试覆盖暂停态及账号删除 fail-closed 的本地契约；TODO 尚未完成。该结果不验证生产行为、真实 Apple 登录/购买或 App Store 审核状态。
- 本机 `security find-identity -v -p codesigning` 仅统计身份类型：Apple Development 1 个，Apple Distribution / iPhone Distribution 0 个。此结果只描述当前本机可用身份，不代表 Apple Developer 团队后台状态。
- 同轮 `git diff --check` 无输出；本次复核未执行构建、归档、上传、审核提交或生产操作。
- 追加的 App Store 准备静态检查：暂停购买与支持文案离线测试 6 项通过、0 项失败；`python3 tests/ios-privacy-manifest.offline.test.py` 2 项通过；现有两张候选截图均为 1206×2622、无 Alpha 通道。上述检查不替代真实 StoreKit、最终归档隐私报告、核心学习流程截图人工审核或 App Store Connect 状态核验。

## 2026-11-07 分发证书、App Store Connect 记录、真机 UI 对齐验收与最新双端联调复跑

- **Apple Distribution 证书与 App Store Connect 记录已创建**：
  - 在公司团队 `Beijing Three pony Technology Co.,Ltd`（Team ID `RMBJCSP3G9`）下创建并安装 `Apple Distribution` 证书（SHA1 `0222BF02EBFF8CD8F5E779F16DE844DE645ECE5A`，有效期至 `2027/11/7`）。
  - 在 App Store Connect 创建 iOS 应用记录「日句」（Apple ID `6831837064`，Bundle ID `com.juxintong.nihongo`，SKU `nihongo-ios-001`，主要语言简体中文，当前版本状态 `iOS 1.0 准备提交`）。
  - 修复 `ios/JapaneseSyntaxCoach/Info.plist` 缺失 `CFBundlePackageType = APPL` 后，归档 `build/app-store-20261107-0951/JapaneseSyntaxCoach-fixed.xcarchive`（版本 `1.0.0`，构建号 `202611070951`）已通过 `xcodebuild -exportArchive`（`destination=upload`）成功上传至 App Store Connect（未提交审核）。
- **iOS UI 对齐现有 Web 及 iPhone 16 真机完整界面与交互验收**：
  - 仅在隔离工作树修改 6 个 iOS 视图文件（`ContentView.swift`、`HomeView.swift`、`HomeVisualStyle.swift`、`TextbookView.swift`、`LessonView.swift`、`QuestionView.swift`），Web 侧 `app/`、`components/`、`lib/` 与根 `tsconfig.json` 未做新改动。
  - 编译签名并覆盖安装到真机 iPhone 16（UDID `00008140-001E6D610CD1801C`）后，实测完成全部 5 个核心界面的真机视觉与点击交互截图验收：
    1. 主首页（暖米纸底色主卡、环形进度、三项进度摘要卡、当前课程卡、底部 4 项浮动导航栏）：`build/ios-web-alignment/01-home-verified.png`
    2. 第 2 课句型详情页（学习目标、「开始整课练习」按钮、按含义/接续/说明/例句分层的句型卡片）：`build/ios-web-alignment/02-grammar-detail-verified.png`
    3. 课程列表页（底部「课程」Tab 选中态、顶部「教材」大标题、浅薄荷绿圆角矩形编号块 `01`–`04` + 深青绿数字及语法点数量标签，原生真机 `1179×2556`）：`build/ios-web-alignment/03-course-list-verified.png`
    4. 第 2 课答题页与提交正误反馈卡（云端同步状态条、题号进度、题型标签、选项卡片、查看提示、点击选项 B 并提交后弹出参考答案解析卡）：`build/ios-web-alignment/04-question-view-verified.png`、`build/ios-web-alignment/04b-question-feedback-verified.png`
    5. 错题本页与底部浮动导航栏（原生真机 `1179×2556`）：`build/ios-web-alignment/05-mistakes-verified.png`
  - 已将真机 `1179×2556` 原生截图（课程列表页、错题本页）去除 Alpha 通道生成 `artifacts/ios/screenshots/app-store-candidates/iphone-6.1-1179x2556/03-course-list-1179x2556.png` 与 `05-mistakes-1179x2556.png`（`sips` 核验均为 `1179×2556`、`hasAlpha: no`）。
- **最新 UI 对齐版 Release 分发签名归档与导出 IPA 核验（本地构建号 `202611072210`，未自动上传）**：
  - 归档路径：`build/app-store-20261107-2210/JapaneseSyntaxCoach-ui-aligned.xcarchive`；本地导出 IPA：`build/app-store-20261107-2210/export/日句.ipa`。
  - `codesign --verify --deep --strict` 验证通过；签名身份为 `Apple Distribution: Beijing Three pony Technology Co.,Ltd (RMBJCSP3G9)`，Provisioning Profile 为 `iOS Team Store Provisioning Profile: com.juxintong.nihongo`（UUID `20f775d3-0905-4b28-b745-8f895aa24bcc`）。
  - 导出包 Entitlements 核验：`application-identifier = RMBJCSP3G9.com.juxintong.nihongo`、`beta-reports-active = true`、`com.apple.developer.applesignin = [Default]`、`com.apple.developer.team-identifier = RMBJCSP3G9`、`get-task-allow = false`。
  - 导出包 `Info.plist` 核验：`CFBundleIdentifier = com.juxintong.nihongo`、`CFBundleShortVersionString = 1.0.0`、`CFBundleVersion = 202611072210`、`CFBundlePackageType = APPL`、`ITSAppUsesNonExemptEncryption = false`、`MinimumOSVersion = 16.0`、`CFBundleURLSchemes = [nihongo]`；`SUPABASE_URL`（指向生产 `ecegssnkpyyjrufgtepq.supabase.co`）与 `SUPABASE_ANON_KEY` 均存在且非空（未输出秘密值）。
  - 导出包内隐私清单核验：包含主包 `JapaneseSyntaxCoach.app/PrivacyInfo.xcprivacy`（`NSPrivacyTracking=false`，声明 `CA92.1` 及 UserID、EmailAddress、OtherUserContent、PurchaseHistory 四类收集数据）与 `swift-crypto_Crypto.bundle/PrivacyInfo.xcprivacy`（空数组，`NSPrivacyTracking=false`）。
- **最新 UI 对齐代码下的隔离环境双端联调完整复跑（2026-11-07 22:13–22:22）**：
  - `PLAYWRIGHT_BROWSERS_PATH="$PWD/build/playwright-browsers" node scripts/ios/dual-client-lab.mjs --cross-client` 实跑通过：
    - 跨端错题清除闭环结果包 `build/dual-client-sdk-20261107-221347-56401.xcresult`：1 通过、0 失败、0 跳过；
    - 同账号、同题、同预期版本屏障并发竞争结果包 `build/dual-client-sdk-20261107-221641-59239.xcresult`：1 通过、0 失败、0 跳过（Web Cookie HTTP 200，iOS Bearer HTTP 409，请求区间重叠 `1022 ms`，数据库断言 1 条答案、1 个操作、版本 `0 → 1`）。
  - `PLAYWRIGHT_BROWSERS_PATH="$PWD/build/playwright-browsers" node scripts/ios/dual-client-lab.mjs --ios` 实跑通过：
    - 结果包 `build/dual-client-sdk-20261107-222024-62596.xcresult`：3 通过、0 失败、0 跳过（含 `testInjectedLearningBaseURLIsUsedForSnapshotAndAnswerRequests()`、`testRealAnswerReplayClearsMistakeAndConflictKeepsQueue()`、`testRealAuthSignOutAndSessionRestore()`）。
  - 离线契约与接线测试 18 项（14 通过、0 失败、4 项 TODO）及隐私清单测试 2 项通过，`git diff --check` 无输出。
- **App Store Connect 会话恢复后的后台只读核查（2026-11-07）**：
  - **商务协议状态（`/business/atb/1d82d1aa-7b0b-4d7c-b4ac-c6c456304cb7`）**：
    - `免费 App 协议`（对应《Apple Developer Program 许可协议》Schedule 1）已更新为 **「有效」**（生效日期 `2026年11月1日 - 2027年7月28日`）；此前阻塞「构建版本」与「订阅」页面的顶部许可协议警告已消除。
    - `付费 App 协议`（Schedule 2）当前状态为 **「有效（新协议可用）」**（生效日期 `2026年5月21日 - 2027年7月28日`），右侧仍显示 `查看并同意条款` 按钮（若启用付费订阅仍建议由 Account Holder 同意最新条款）。
  - **TestFlight 与版本 1.0 构建状态**：
    - TestFlight iOS 页面（`/teams/3cd19068-9140-4ab5-96c0-b9b816423210/apps/6831837064/testflight/ios`）中，构建版本 `202611070951`（版本 `1.0.0`，UI 对齐前构建）已完成后台处理与出口合规校验，状态为 **「准备提交（89 天后过期）」**。
    - 「iOS App 版本 1.0（准备提交）」页面（`/apps/6831837064/distribution/ios/version/inflight`）中，顶部红色许可协议警告已消除；「App 预览和截屏」标签页默认选中 **「带灵动岛的 iPhone（中等显示屏）」**（页面明确提示支持选取适用于 iPhone 6.1 英寸 `1179×2556` 或 6.3 英寸 `1206×2622` 显示屏的截屏素材，当前 `0/3 个 App 预览`、`0/10 张 App 截屏`）；「推广文本」「描述」「关键词」「技术支持网址 (URL)」「营销网址 (URL)」「版权」及「App 审核」联系人和演示账号字段当前均为空；「构建版本」区域已正常开放 **「添加构建版本」** 按钮（当前尚未绑定构建）。
  - **订阅页面（`/apps/6831837064/distribution/subscriptions`）**：
    - 此前顶部的许可协议黄色警告已消除，页面已开放自动续期订阅下的 **「订阅群组 → 创建」** 按钮；当前尚未创建订阅群组与商品（0 个订阅商品）。
  - **App 隐私页面（`/apps/6831837064/distribution/privacy`）**：
    - `隐私政策网址 (URL)` 与 `用户隐私选择网址 (URL)` 当前均为 `–`（未填写），数据类型问卷仍处于初始「开始」未填写状态，「发布」按钮尚未就绪。
  - **App 信息页面（`/apps/6831837064/distribution/info`）**：
    - `内容版权` 显示 `设置内容版权信息`（未设置）；
    - `类别` 的主要类别与次要类别尚未保存选定；
    - `年龄分级` 显示 `设置年龄分级`（未设置，按元数据草稿应设为 `4+`）；
    - `中国大陆 ICP 备案号` 显示 `设置`（未填写；若暂未取得 ICP 备案号，在「价格与销售范围 → App 供应情况」中须先排除中国大陆地区，否则无法在中国大陆区上架）；
    - `App Store 服务器通知` 的生产环境与沙盒环境服务器 URL 均显示 `设置 URL`（对应服务端 `/api/apple/notifications`）。
  - **价格与销售范围页面（`/apps/6831837064/distribution/pricing`）**：
    - `价格时间表` 显示 `添加定价`（尚未设置初始基础价格 ¥0.00 / 免费）；
    - `App 供应情况` 显示 `设置供应情况`（尚未设置可供下载的国家或地区）。
- **Apple 登录、StoreKit Sandbox 与真机截图尺寸静态核对（2026-11-08）**：
  - **Apple 登录（Sign in with Apple）**：`AuthView.swift:247-255` 与 `357-371` 使用 `SignInWithAppleButton(.signIn)` 提取 `credential.identityToken` 后调用 `store.signInWithApple(idToken: token)`（未传 `nonce`），由 `SupabaseAuthServiceLive` 调用 `signInWithIdToken(credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))`。已在 `AuthSessionStoreTests.swift` 新增 `testSignInWithAppleForwardsCredentialsAndUpdatesSessionAndGeneration()` 与 `testSignInWithAppleClassifiesFailuresWithoutExposingRawErrors()` 验证凭据转发、会话/学习代数更新及 `.providerDisabled` / `.badJWT` / `.invalidJWT` / `.noAuthorization` 脱敏错误分类。Release 归档 `202611081217` 的 Store Provisioning Profile 已含 `com.apple.developer.applesignin = [Default]`；真实登录验证前需确认生产 Supabase Dashboard 已启用 Apple provider 并将 `com.juxintong.nihongo` 列入 Authorized Client IDs。
  - **StoreKit 更新观察任务生命周期修复与验证**：修复 `StoreKitManager.swift` 中 `updatesTask` 调用 `await self?.observeTransactionUpdates()` 在挂起等待 `transactionUpdates()` 期间强引用持有 `self` 导致 `deinit` 无法执行的问题，改为在任务内直接遍历 `resolvedProvider.transactionUpdates()` 并对每条交易解包 `guard let self else { return }` 后调用 `handleTransactionUpdate(_:)`；同时在 `StoreKitStateTests.swift` 新增 `testStoreKitManagerDeallocatesAndCancelsTransactionUpdatesStreamWhileAwaitingUpdates()` 与 `testTransactionUpdateStreamFinishingEndsObservationAndAllowsDeallocation()`。在临时隔离模拟器运行 `StoreKitStateTests`、`StoreKitFinishOfflineTests`、`AuthSessionStoreTests` 与 `AccountDeletionTests` 共 65 项测试全部通过（结果包 `build/storekit-auth-unit-20261108-121447-99945.xcresult`，65 passed, 0 failed, 0 skipped）。
  - **StoreKit Sandbox 与服务端验签**：客户端 `StoreKitManager.newPurchasesEnabled = false`（`StoreKitManager.swift:178`）且 `lib/apple/server.ts:62-67` 的 `updateMembershipFromAppleTransaction` 无条件抛出 `AppleEntitlementWritesDisabledError`。服务端 `getVerifier()`（`lib/apple/server.ts:28-48`）除要求 `APPLE_BUNDLE_ID=com.juxintong.nihongo`、`APPLE_ROOT_CA_BASE64`、`APPLE_ENVIRONMENT`（`SANDBOX` 或 `PRODUCTION`）、`APPLE_SUBSCRIPTION_PRODUCT_IDS` 外，当 `APPLE_ENVIRONMENT=PRODUCTION` 时还强制要求 `APPLE_APP_APPLE_ID=6831837064`（现已确认为 App Store Connect 分配的 Apple ID `6831837064`）。
  - **真机与全套统一原生尺寸截图核对**：`build/ios-web-alignment/` 留存 iPhone 16 真机实测验收图；同时通过 `HomeRefreshTests.testRenderCoreScreensAtNativeDisplayResolution()` 在临时隔离模拟器（测试后立即销毁）生成并经 `sips` 核验三套完整 5 页无 Alpha 通道（`hasAlpha: no`）App Store 候选截图（覆盖 `01-home`、`02-grammar-detail`、`03-course-list`、`04-question-view`、`05-mistakes`）：
    - 6.1" Dynamic Island（`1179×2556`）：`artifacts/ios/screenshots/app-store-candidates/iphone-6.1-1179x2556/`（5 张全套统一渲染图 + 2 张真机原生 `03-course-list-device-1179x2556.png`、`05-mistakes-device-1179x2556.png`，结果包 `build/home-refresh-iphone16-20261108-123141-7205.xcresult` 3/3 通过）
    - 6.3" Dynamic Island（`1206×2622`）：`artifacts/ios/screenshots/app-store-candidates/iphone-6.3-1206x2622/`（5 张全套统一渲染图，结果包 `build/home-refresh-iphone17pro-20261108-123141-7205.xcresult` 3/3 通过）
    - 6.9" Primary Display（`1320×2868`）：`artifacts/ios/screenshots/app-store-candidates/iphone-6.9-1320x2868/`（5 张全套统一渲染图，结果包 `build/home-refresh-iphone16promax-20261108-123141-7205.xcresult` 3/3 通过）
  - **刷新本地 Release 归档（`1.0.0` build `202611081217`，仅本地导出）及归档级隐私清单/Required Reason API 符号审计**：包含最新 Web 对齐 UI 与 `StoreKitManager` 更新流生命周期修复的归档 `build/app-store-20261108-1217/JapaneseSyntaxCoach-ui-aligned.xcarchive` 及导出 IPA `build/app-store-20261108-1217/export/日句.ipa` 已通过 `codesign --verify --deep --strict` 核验。对归档内静态链接后的 Release Mach-O 主二进制执行 `nm -u` Required Reason API 符号扫描，仅检出 SwiftUI `@AppStorage`（`NSUserDefaults`）符号引用，未检出 FileTimestamp、SystemBootTime、DiskSpace 或 ActiveKeyboards 类别符号；归档内仅含主包 `JapaneseSyntaxCoach.app/PrivacyInfo.xcprivacy`（声明 `CA92.1` 及四类收集数据，`NSPrivacyTracking=false`）与 `swift-crypto_Crypto.bundle/PrivacyInfo.xcprivacy`（空数组，`NSPrivacyTracking=false`）。

后续顺序：Account Holder 已完成《Apple Developer Program 许可协议》更新，`免费 App 协议` 已生效且「添加构建版本」与「创建订阅群组」已解锁；`付费 App 协议`（Schedule 2）仍有新版本可由 Account Holder 在商务页查看并同意。同时需用户明确确认：（1）生产环境是否部署原子错题候选迁移并开启 `MISTAKE_STATE_V1_ENABLED`；（2）针对账号删除 fail-closed（HTTP 503）、新订阅暂停及线上 `/privacy`、`/terms`、`/subscription` 文案不一致的上架阻塞路线；（3）是否将最新 UI 对齐版 IPA（`1.0.0` build `202611081217`）上传至 TestFlight。上一轮问卷因 60 秒等待超时自动选定保持暂停/暂不上传默认项，不构成用户授权。

以下历史条目中的“未核实”以本节明确列出的新证据为补充；没有列出实际结果的项目仍未通过。

## 2. Apple Developer 后台

- [x] App ID `com.juxintong.nihongo` 已存在，App Store Connect 中已关联（Apple ID `6831837064`）
- [x] 开启 **Sign in with Apple** 能力（导出 IPA 的 Store Provisioning Profile `UUID 20f775d3-0905-4b28-b745-8f895aa24bcc` 含 `com.apple.developer.applesignin = [Default]`）
- [ ] Distribution / Release 的 Provisioning Profile 含 **In-App Purchase** 能力及 App Store Connect 侧商品/沙盒真实核验（StoreKit 在无需额外 entitlement 时仍依赖后台商品与 Paid Applications Schedule 协议状态）
- [x] 团队 `RMBJCSP3G9`（`Beijing Three pony Technology Co.,Ltd`）下的 App Store Connect Admin 权限已确认；Account Holder 已同意最新《Apple Developer Program 许可协议》（`免费 App 协议`生效期 `2026年11月1日 - 2027年7月28日`），商务页 `付费 App 协议`（Schedule 2）状态为「有效（新协议可用）」，仍可由 Account Holder 点击「查看并同意条款」更新
- [ ] 已创建用于沙盒测试的 Apple 沙盒账号（**不要**写进仓库）

## 3. App Store Connect 记录

- [x] 创建 App 记录：名称「日句」（Apple ID `6831837064`，SKU `nihongo-ios-001`，Bundle ID `com.juxintong.nihongo`，主要语言「简体中文」，当前版本状态 `iOS 1.0 准备提交`）；主要类别「教育」待在版本信息页核对保存
- [ ] 功能完成并验证后，重新审定 `docs/ios/app-store-metadata-draft.md` 中的名称、副标题、描述、关键词及各 URL；现有草稿不可直接提交
- [ ] 在 App Store Connect 填写支持 URL `https://japanese-syntax-coach.vercel.app/support`。
      页面已独立部署并经公网访问检查；提交审核前再次核实可用性。
- [ ] 上传图标（当前 worktree 的 `AppIcon.appiconset` 中 9 个 PNG 尺寸均与 `Contents.json` 声明一致；`AppIcon-1024.png` 已本地检查为 1024×1024 且无 alpha）、截图（本 App target 仅支持 iPhone；App Store Connect 版本 1.0 页「App 预览和截屏」默认选中「带灵动岛的 iPhone（中等显示屏）」，页面明确提示支持选取 iPhone 6.1 英寸 `1179×2556` 或 6.3 英寸 `1206×2622` 截屏素材，当前 `0/10 张 App 截屏`。[官方规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)。本地已在 `artifacts/ios/screenshots/app-store-candidates/iphone-6.1-1179x2556/`、`iphone-6.3-1206x2622/` 与 `iphone-6.9-1320x2868/` 生成三套完整 5 页无 alpha PNG 候选截图及 2 张真机原生 `1179×2556` 无 alpha 副本；真机 5 个核心界面的验收图另存于 `build/ios-web-alignment/`，待用户确认后即可上传至 App Store Connect）
- [ ] 根据最终实际数据流、SDK 和归档隐私报告核对并填写隐私问卷；历史草稿不可直接作为答案
- [ ] 订阅组与两个自动续期商品已创建：
      - `com.juxintong.nihongo.monthly`（月度，¥18）
      - `com.juxintong.nihongo.yearly`（年度，¥180）
- [ ] 每个商品都填好显示名、描述、本地化、审核截图
- [ ] 订阅商品加入同一个订阅组，并设置等级（年付高于月付）
- [ ] 审核信息里填写完整的注册账号（邮箱 + 密码）
- [ ] 功能完成并经真实环境验证后，根据实际登录、购买、恢复和删除行为重新编写审核备注；当前新购买、权益同步和账号删除均暂停

## 4. 服务端与 Supabase

> **迁移阻塞：不要批量执行当前迁移目录。** `202611030001_apple_transaction_ownership.sql` 故意无条件报错；`202611030002_account_deletion_operation_store.sql` 虽标注仅供审查，仍含可执行 DDL。`supabase/candidates/` 中的候选也不得部署。上线前须完成设计、权限与迁移审查，并分别取得明确的线上迁移授权；不能假设注释会阻止执行。

- [ ] 生产环境的 `APPLE_SUBSCRIPTION_PRODUCT_IDS` 包含两个商品 ID（`com.juxintong.nihongo.monthly,com.juxintong.nihongo.yearly`）
- [ ] 生产环境的 `APPLE_ROOT_CA_BASE64`（Apple 根证书）、`APPLE_BUNDLE_ID=com.juxintong.nihongo` 与 `APPLE_APP_APPLE_ID=6831837064`（`lib/apple/server.ts:38-42` 在 `PRODUCTION` 模式下强制校验）已配置
- [ ] 生产环境的 `APPLE_ENVIRONMENT` 与 App Store 环境一致（沙盒联调时需设为 `SANDBOX` 或支持沙盒回退）
- [ ] Supabase Redirect URLs 白名单包含 `nihongo://auth-callback`
- [ ] Supabase Apple provider 已启用
- [x] 原生答题幂等能力已通过单独审查的 `artifacts/ios/production-answer-sync-repair.sql` 在生产部署，并由真机三次写入与去重表记录核对。未据此标记原迁移文件的迁移历史为已应用。
- [ ] 生产环境 `NEXT_PUBLIC_SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` 正确

## 5. 签名、归档与上传

- [x] 在 Xcode / `xcodebuild` 中使用真实的公司团队（`RMBJCSP3G9`）与 `Apple Distribution` 证书完成签名导出
- [x] Archive 成功：UI 对齐前版本 `1.0.0 (202611070951)` 已归档并上传至 App Store Connect，且在 TestFlight 中已完成后台处理与出口合规校验（状态「准备提交，89 天后过期」）；包含最新 Web 对齐 UI 与 `StoreKitManager` 生命周期修复的版本 `1.0.0 (202611081217)` 已完成本地 Release 归档（`build/app-store-20261108-1217/JapaneseSyntaxCoach-ui-aligned.xcarchive`）与 Apple Distribution 签名 IPA 导出（`build/app-store-20261108-1217/export/日句.ipa`）
- [ ] 最新 UI 对齐版（`1.0.0` build `202611081217`）上传到 App Store Connect 并核实后台处理状态（之前上传的 `202611070951` 为 UI 对齐前构建且在 TestFlight 状态为「准备提交」；`202611081217` 需用户明确确认后再上传）
- [ ] 提交前确认最终选定构建号在 ASC 中唯一且通过出口合规/构建处理

> 每次构建上传及最终提交审核均需用户本人明确确认；上一轮问卷 60 秒超时自动选择的默认项不构成上传或提交授权。

## 6. 提交审核

- [ ] 提交前再次确认版本号、构建号、描述、隐私问卷、订阅商品都已就绪
- [ ] 提交审核并记录提交时间与审核单号

## 7. 提交之后

- [ ] 审核被拒时按 Apple 的反馈修复并重新归档上传
- [ ] 获得必要授权并保护现有设备数据后，在合适的测试环境验证注册、登录、答题、同步及启用后的沙盒购买和恢复；不得将沙盒验证视为线上真实购买验证
- [ ] 确认 `https://japanese-syntax-coach.vercel.app/privacy`、`/terms`、`/subscription` 与 `/support` 均可公开访问且内容与当前行为一致（App Store 审核会直接访问相关 URL）；2026-11-04 四页均返回 HTTP 200。2026-11-05 重新读取公开 `/privacy` 页面，仍显示用户可在“我的”页面申请注销，且注销后账号及关联云端学习数据会被删除；这与当前 iOS 删除操作 fail-closed、服务端 `POST /api/account/delete` 无条件返回 503 且说明账号及数据未更改相冲突。2026-11-05 重新读取公开 `/terms` 与 `/subscription`：协议仍称用户可随时注销；订阅页仍宣传月付 ¥18/年付 ¥180、自动续期，并称恢复购买会同步会员。以上与当前账号删除、新购买及权益同步暂停状态冲突。本地 `app/privacy/page.tsx`、`app/terms/page.tsx`、`app/subscription/page.tsx` 已反映暂停状态，但与线上页面不同步；上线前须解决删除功能、订阅状态与政策文案的一致性。公开部署需另行授权。
- [x] 线上 iPhone Bearer 答题鉴权与学习状态读取正常，三条答题实际入库；浏览器 Cookie 兼容已做本地候选 HTTP 回归，生产浏览器实际答题尚待单独验收。

---

## 已知未验证项（发布前必须人工验证）

| 项目 | 原因 |
| --- | --- |
| 真实沙盒购买 | 需要 Apple 沙盒账号与 ASC 商品配置 |
| 真实 Apple 登录 | 需要设备、配置好的 provisioning profile 与 Supabase Apple provider |
| Keychain 跨启动持久化 | iPhone 16 重启后会话恢复已由用户确认；没有单独读取或审计 Keychain 内部存储 |
| StoreKit 更新观察任务生命周期 | 已修复并经 XCTest 可控替身验证（2026-11-08，`build/storekit-auth-unit-20261108-121447-99945.xcresult`）：`StoreKitManager` 改为在 `updatesTask` 中直接遍历 `resolvedProvider.transactionUpdates()` 并逐条弱解包 `self`，消除跨流挂起时的强引用持有；`StoreKitStateTests` 已验证等待更新期间对象释放、`deinit` 取消任务触发流 `onTermination` 以及流自然结束后的对象释放。 |
| 必需原因 API 隐私声明 | 静态核对（2026-11-05）：`ContentView.swift` 的 `@AppStorage("hasSeenOnboarding")` 保存本 App 的引导完成标志；App 源码中未检出直接 `UserDefaults` 调用。`PrivacyInfo.xcprivacy` 声明 `NSPrivacyTracking=false`、UserID、EmailAddress、OtherUserContent、PurchaseHistory 四类收集数据，以及 UserDefaults 类别和 `CA92.1`；获准隔离 XCTest 构建的 App 包内含 App 自身 manifest 和 `swift-crypto_Crypto.bundle` manifest；前者与源 manifest 内容一致，后者的收集数据及 accessed API 数组为空（另有构建产品目录和 XCTest 插件中的重复副本，不计作额外 App 运行时清单）。Apple 对 `CA92.1` 的说明适用于仅访问本 App 可读写的 defaults；不得据此读取其他 App/系统写入的信息，或写入其他 App 可访问的位置。此项仅为源码与测试构建包的静态核对：尚未核对最终签名归档的 manifest、所有依赖 SDK 合并后的清单、完整实际数据流或 App Store Connect 隐私问卷，也不构成完整性/合规结论。归档和问卷应按最终二进制重新审核。参考：[AppStorage](https://developer.apple.com/documentation/swiftui/view/defaultappstorage(_:))、[Apple 必需原因 API](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)。 |
| 认证凭据与数据保留披露 | 源码显示认证服务调用会向 Supabase Auth 传递邮箱和密码（`AuthSessionStore.swift`）。学习答案会进入本地待同步队列并可上传；服务端 `record-answer` 路由把答案传给持久化 RPC，`answer_attempts.answer` 保存答案文本，而 `202610291400_native_answer_idempotency.sql` 还把返回记录保存在幂等表的 JSON 字段中。schema 与迁移为用户外键声明了 `ON DELETE CASCADE`，但客户端删除目前 fail-closed（`LearningStore.deleteAccount`），服务端 `POST /api/account/delete` 也无条件返回 503 并说明账号及数据未更改（`app/api/account/delete/route.ts`）；线上迁移应用状态、数据库实际数据与保留时长均未核实，且本轮未连接服务或数据库。Apple 对“收集”的说明以数据是否以可读形式保留超过处理请求所需时间为判断条件；须依据 Supabase Auth 与业务 API 的实际处理/保留方式、SDK 数据流及 Apple 数据类型定义，复核 App Store Connect 披露映射，不能仅凭客户端请求或现有 manifest 推断。参考：[Apple App 隐私详细说明](https://developer.apple.com/cn/app-store/app-privacy-details/)、[Apple 收集数据类型定义](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype)。 |
| 服务端验签往返 | 需要生产环境的 Apple 根证书与 `APPLE_SUBSCRIPTION_PRODUCT_IDS` |
| 原生答题幂等生产效果 | 已通过单独修复事务部署，真机三次写入与三条完整幂等记录核对；原迁移文件历史登记、原子错题候选与生产双端同时竞争未据此确认 |
| 签名归档与上传 | 需要真实证书与明确授权 |
| `/support` 提交前复核 | 页面已上线并经公网访问检查，提交审核前再次检查可用性 |
| 支持邮箱可用性 | 用户已确认 `service@niixmiro.com` 由其管理且可收信；未确认回复时限 |
