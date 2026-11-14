# 日句 iOS 原生首版设计

日期：2026-10-28
状态：待用户审阅

## 目标与范围

将日句改造成以 SwiftUI 原生体验为主、可准备 App Store 首发构建的 iOS 应用，同时保留 Next.js/Supabase 作为现有 Web 与服务端。首版包含原生邮箱登录/注册、邮件验证码、密码重置、Sign in with Apple、首页、教材目录与课程、整课答题、学习进度、StoreKit 订阅、账户管理、退出登录和账号删除。

本阶段不创建 App Store Connect 记录、不上传构建、不提交审核；这些外部操作需另行确认。App Store 审核结果不可保证。

## 已确认决策

- 产品路线：原生化关键体验，不以 WebView 承载核心学习流程。
- 首发页面：原生学习体验和原生账户流程。
- 后端：沿用 Next.js/Supabase；iOS 通过现有 Next.js API，不直接写业务表。
- API 身份验证：现有网站 Cookie 继续工作；受保护 API 增加 Supabase Bearer access token 验证。
- 认证：Supabase Swift SDK 管理原生会话与 Keychain 持久化；保留邮箱密码注册/登录、邮箱验证码、密码重置、Apple 登录。邮件链接使用 Universal Link 或自定义 URL Scheme 回到 App。
- 内容：现有 TypeScript 教材/题库为单一权威源，构建生成带 schema 版本和内容 hash 的 JSON 资源。
- 离线：在线优先；可访问本机已缓存内容，离线答案暂存并联网重放，不承诺首版完整离线下载。
- 订阅：沿用 StoreKit 2、后端交易验签和商品 ID `com.juxintong.nihongo.monthly`、`com.juxintong.nihongo.yearly`。
- ASC 尚未创建记录；ASC 创建、上传、送审均不包含在本阶段自动动作内。

## 客户端架构

SwiftUI 提供应用根路由及认证、首页、教材、课程、整课练习、进度、订阅、账户等功能域。按职责拆分认证会话、API 客户端、教材仓库、学习状态仓库、离线答题队列、StoreKit 管理器和可复用状态视图。Supabase 客户端只使用公开 anon key；service-role key 只留在服务端。

认证回调须支持邮箱注册验证、密码重置和 Apple 登录回调；处理取消、回调失效、过期会话、重复回调和用户主动登出。令牌存入 Keychain，由 API 客户端附加 Authorization Bearer；401 时尝试 SDK 刷新一次，之后转登录流程。

## 服务端 API 与数据流

统一 Supabase 服务端客户端工厂，从 Request Authorization Bearer 解析并通过 Supabase `auth.getUser(token)` 验证；无 Bearer 时沿用 Next.js SSR Cookie。禁止信任客户端提供的 user ID；每次请求的用户身份只来自经验证的 session。

- `GET /api/study-state?textbookId=...`：返回云端已记录的学习统计、复习状态和指标。
- `POST /api/record-answer`：继续调用既有安全 RPC；增加客户端生成的幂等键/请求 ID，使重试和离线队列重放不会重复统计。
- `GET /api/membership`：提供登录态与会员状态。
- `POST /api/apple/entitlements`：验证 signed transaction 并绑定当前登录用户；恢复购买也走此端点。
- `POST /api/account/delete`：Bearer 和 Cookie 均可认证；成功后客户端清除会话、缓存和未提交队列。

现有网站端点行为需保持兼容。API 错误采用稳定状态码和可展示错误信息；401、403、网络超时、限流和服务端失败分别处理。

## 教材、答题和进度

现有 `lib/textbooks.ts`、课程数据和 `lib/question-bank.ts` 是教材与题库权威来源。构建脚本导出 JSON 包，包含 schemaVersion、教材 ID、题目、课程、语法点、资源版本/hash；Swift 使用 Codable 解码并校验版本。初始包随 App 内置，后续可通过版本化远程包更新而不改变权威源。

原生答题覆盖选择、助词、翻译和问答四类，沿用现有评分语义。一次答题先更新界面和本地持久化队列，再发送 API；成功后从云端状态确认。离线缓存仅展示已具备的教材；答案记录暂存到本地，重连后按序提交。服务端幂等保障重试安全。多设备冲突以服务端答题事件与聚合状态为准，不采用客户端整份进度覆盖。

迁移兼容：当前 Web 还把一部分学习进度放在 `user_metadata.learning_progress`，而结构化 study-state 使用专门学习表。必须先盘点两种来源的实际覆盖与最新时间语义，提供不丢数据的读取回退或一次性迁移；若无法可靠自动合并，不得静默覆盖，应保留旧值并暴露迁移状态。

## 订阅与账户

StoreKit 2 加载月付和年付商品，登录用户购买时设置 `appAccountToken`。已验证交易经 `/api/apple/entitlements` 上报，会员状态通过 `/api/membership` 刷新。应用监听交易更新；成功交易先确保服务端同步完成再结束交易，断网或服务端失败时保留可重试签名数据。恢复购买调用 `AppStore.sync()` 并逐条上报相关 verified current entitlements。

订阅界面展示 Apple 返回的本地化价格、周期、自动续订说明、隐私政策与使用条款入口、购买和恢复购买。账户界面显示邮箱、会员和同步状态，提供登出及有明确二次确认的账号删除入口。

## 错误与无障碍状态

覆盖加载、无课程、未登录、邮箱未验证、弱网/断网、缓存可用、同步中/失败、API 未授权、购买取消/等待/失败、商品不可用、恢复无结果、账号删除失败等状态。离线队列在用户可见位置显示待同步数与重试操作。界面支持 VoiceOver 标签、动态字体、键盘/焦点可达和系统减少动态效果设置。

## 测试与验收

### Swift 单元测试

- 教材 JSON 解码、版本/hash 校验、题型排序和评分边界。
- 认证回调路由、会话恢复和登出清理。
- 离线答案入队、顺序重放、失败保留与幂等 ID 稳定性。
- StoreKit 状态映射、购买取消/等待/失败与恢复结果处理。

### 服务端测试

- Cookie 与 Bearer 两种方式认证到相同用户；无效 token/无 session 被拒绝。
- 学习、会员、订阅、注销端点不信任 body user ID。
- 答题幂等重试仅产生一次统计；超时后重试语义正确。
- 旧 `user_metadata.learning_progress` 与结构化状态的兼容/迁移测试。
- Apple signed transaction 验签与用户绑定回归测试。

### 端到端验收

模拟器构建与测试；真机/Apple Sandbox 验证注册验证、Apple 登录、密码重置、进度同步、断网暂存/重连、订阅购买/恢复、注销与重新注册；检查 iPhone 尺寸、VoiceOver、动态字体及深链回调。发布前确认图标、截图、隐私标签、隐私政策和条款链接、审核说明及沙盒账号材料。

通过标准：iOS Simulator Release 构建成功；自动化测试通过；上述关键路径无静默数据丢失或重复答题计数；网站 Cookie 流程无回归；外部商店操作仍等待单独授权。

## 关键风险与前置条件

- Supabase Apple Provider、OAuth redirect allowlist、Associated Domains 或 URL Scheme、邮件模板和域名 Universal Link 配置需真实环境验证。
- Supabase Swift SDK 的 SPM 依赖及当前 XcodeGen 配置需验证可重复构建。
- 本项目里程碑和题库规模较大，教材 JSON 体积、首次安装体积及审核可接受性需测量。
- `record-answer` 的幂等需要数据库迁移和唯一约束/RPC 支持，不能仅依赖客户端内存。
- 当前 `StoreKitManager` 在交易上报与 `finish()` 时序方面需要调整，确保服务端验签失败可恢复。
- App Store Connect 尚无 App 记录和商品配置；签名、团队权限、银行税务协议及审核素材仍需账户持有人处理。
