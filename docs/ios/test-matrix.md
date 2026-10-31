# 测试矩阵

覆盖原生 iOS 客户端（分支 `ios-native-app`）与网站侧的自动化验证，以及必须人工完成、无法在本地
自动化的部分。最后一次自动化运行的结果见 `artifacts/ios/validation.log`。

## 1. 自动化：XCTest（iOS 原生客户端，78 项，0 失败）

运行命令：

```bash
xcodegen generate --spec ios/project.yml
xcodebuild test -project ios/JapaneseSyntaxCoach.xcodeproj -scheme JapaneseSyntaxCoach \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

| 领域 | 测试文件 | 覆盖内容 |
| --- | --- | --- |
| 教材包契约 | `TextbookRepositoryTests` | 内置教材 schema、题量、题目顺序、每课 20 题上限、contentHash 格式与运行时校验、空 ID 与不支持版本的报错 |
| 判分一致性 | `AnswerEvaluatorTests` | 选项题按文本或选项键判定、助词题判定、相似度阈值边界、错误标签与知识标签、网站去糖变体（含重叠的否定过去式） |
| 选项语义 | `AnswerEvaluatorTests` | 选项文本唯一性、显示文本与提交文本的对应、`needs_fix` 相似度使用显示态期望文本 |
| 认证 | `AuthSessionStoreTests` | 未配置 Supabase 时不崩溃并进入 misconfigured、回调白名单与大小写校验、畸形/不可信回调拒绝、注册深链统一走 `exchangeCallback`、刷新失败映射、退出登录清理会话 |
| API 客户端 | `AuthSessionStoreTests` | Bearer 注入、401 后刷新重试一次、第二次 401 不再刷新、空 token、403、网络失败与服务端错误映射 |
| 离线答案队列 | `OfflineAnswerQueueTests` | FIFO 顺序、跨重试稳定的 `clientRequestId`、仅在服务端确认写入后移除、失败项保留、损坏持久化恢复为空队列 |
| 购买状态机 | `StoreKitStateTests` | 商品不可用、未登录、取消、待处理、未验证、商品缺失 |
| 购买与完成顺序 | `StoreKitStateTests` | 服务端接受/确认重复后才 `finish`；网络失败、未授权、账号不匹配、服务端拒绝都不 `finish` |
| 待同步队列 | `StoreKitStateTests`、`PendingTransactionQueueTests` | 同一交易只入队一次、失败原因刷新、标记 blocked、按交易 ID 移除、跨实例持久化、损坏文件逐条恢复并保留原始字节、写失败被上报、丢弃全部账号文件 |
| 购买账号归属 | `StoreKitStateTests` | 属于其它账号的购买被存到该账号的队列，不污染当前账号 |
| 交易观察者 | `StoreKitStateTests` | `Transaction.updates` 投递的失败交易被入队重放；无会话时同样入队 |
| 并发 | `StoreKitStateTests` | 购买与恢复同时看到同一笔交易时只提交一次、只 `finish` 一次 |
| 账号删除 | `StoreKitStateTests` | 删除确认字面量必须为 `DELETE`；清除账号数据会删除本机待同步购买文件 |
| 首启引导 | `OnboardingArtworkTests` | 四张引导插图都在 App bundle 内且可加载、页面数量与唯一性 |

## 2. 自动化：网站侧（Next.js / Playwright）

运行命令：

```bash
npm run build
npx tsc --noEmit
npx playwright test
```

| 规格 | 覆盖内容 |
| --- | --- |
| `tests/e2e/architecture.spec.ts` | 教材导出包契约、答题幂等迁移与路由契约、Bearer/Cookie 双认证且路由不信任客户端 user ID |
| `tests/e2e/auth-contract.spec.ts` | Bearer 解析边界、受保护 API 统一使用 `getAuthenticatedSupabase(request)`、Apple 账号令牌的大小写无关比较 |
| `tests/e2e/record-answer-idempotency.spec.ts` | 带幂等键的答题请求契约、无键时保留旧路径、503 行为、迁移里的用户范围唯一键 |
| `tests/e2e/learning-progress-compat.spec.ts` | legacy 与结构化进度分开呈现、v2/v3 兼容、未知版本标记 unsupported 并保留原始数据、503 分支保留 legacy 字段 |
| `tests/e2e/question-bank.spec.ts` | 24 课题库回归：字段、ID 唯一性、题型覆盖、答案去标点与去重 |
| `tests/e2e/lesson-flow.spec.ts` | 首页入口、锁定课程、整课答题、错题本、候选词、助词题判分、注册流程 |
| `tests/e2e/textbook-switcher.spec.ts` | 教材切换、schemaVersion 1 兼容、非法 JSON 拒绝 |
| `tests/e2e/review-set.spec.ts` | 复习间隔与混合复习集合 |
| `tests/e2e/pwa.spec.ts` | PWA manifest、图标、Service Worker、窄屏无横向滚动 |
| `tests/e2e/support-page.spec.ts` | 支持页联系方式与两条账号注销路径、隐私政策写明应用内注销路径 |
| `tests/e2e/ai-fallback.spec.ts` | AI 分析接口的降级、401/429/超时处理 |

**已知既有失败（与本分支无关）**：`tests/e2e/lesson-flow.spec.ts` 的第 225、241、273 行共 3 项在分支
基线 `8b01e69` 上同样失败，属仓库既有失败。

## 3. 构建

| 目标 | 命令 | 结果 |
| --- | --- | --- |
| 工程生成 | `xcodegen generate --spec ios/project.yml` | 通过；生成的 `project.pbxproj` 必须随每次新增 Swift 文件提交 |
| Release 模拟器构建 | `xcodebuild -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` | 通过，无警告 |

## 4. 模拟器人工检查（已完成 2 轮）

设备：iPhone 17 Pro（iOS 26.5 运行时）。截图见 `artifacts/ios/screenshots/`。

| 轮次 | 检查内容 | 发现 | 处理 |
| --- | --- | --- | --- |
| 第 1 轮 | 首启引导、登录页、登录页「未配置 Supabase」错误态 | 引导插图完全不渲染（白屏）；SwiftUI 顶栏与插图自带页眉重复；登录主按钮与次要链接外观相同 | 引导插图改为从 bundle 显式加载；原生顶栏改为覆盖插图页眉；登录按钮改为主按钮样式 |
| 第 2 轮 | 引导第 1 页与第 2/3/4 页的等比模拟、登录页（已配置与未配置两种） | 四页几何均正常，登录页主次操作已可区分 | 无进一步修改 |

> 说明：本次会话没有暴露桌面控制工具，无法在模拟器里点击翻页。第 2/3/4 页通过与设备同尺寸的等比
> 裁剪模拟逐页核对，确认原生顶栏覆盖范围与插图内容区不冲突。

## 5. 必须人工完成、无法本地自动化的部分

| 项目 | 为什么无法自动化 | 需要谁 |
| --- | --- | --- |
| 沙盒购买与订阅弹窗 | 需要 Apple 沙盒账号与 App Store Connect 商品配置 | 账号持有人 |
| 真实 Apple 登录 | 需要真机、配置了 Sign in with Apple 的描述文件、Supabase Apple provider | 账号持有人 |
| Keychain 跨启动持久化 | 需要真机多次启动验证 | 账号持有人 |
| 服务端验签往返 | 需要生产环境的 Apple 根证书与 `APPLE_SUBSCRIPTION_PRODUCT_IDS` | 运维 |
| 数据库迁移 `202610291400` 的线上效果 | 迁移只准备了源文件，尚未应用到线上 | 运维 |
| 真实 Supabase 往返（学习状态、答题写库） | 需要真实 anon key 与线上项目 | 账号持有人 |
| 签名、归档、上传、提交审核 | 需要真实证书与明确授权 | 账号持有人 |
| VoiceOver 与动态字体全量走查 | 需要人工逐屏操作 | 设计与测试 |
| 隐私清单复核 | 需要 Apple 隐私清单生成工具 | 账号持有人 |
