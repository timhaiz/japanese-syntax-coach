# 日句 — 原生 iOS 客户端

这是 `japanese-syntax-coach` 网站的原生 iOS 客户端。它复用现有的 Next.js / Supabase 后端，
但首页、教材、答题、进度、订阅和账户全部是原生 SwiftUI 界面。网站本身保持不变，仍然使用
Cookie 认证并继续对外提供服务。

## 目录结构

```text
ios/
├── project.yml                       # XcodeGen 工程定义（project.pbxproj 由它生成）
├── README.md                         # 本文件
├── JapaneseSyntaxCoach/
│   ├── AppConfiguration.swift        # Bundle ID、商品 ID、Supabase 坐标
│   ├── AppEnvironment.swift          # 共享的 auth / storeKit / learning 服务
│   ├── ContentView.swift             # 根视图：首启引导 → 标签页 / 登录
│   ├── OnboardingView.swift          # 首启引导流程
│   ├── StoreKitManager.swift         # 交易监听、待同步队列、账号归属
│   ├── Auth/                         # 邮箱密码、验证码、重置、Apple 登录
│   ├── Billing/                      # StoreKit 2 订阅、待同步队列、账户与订阅页
│   ├── Learning/                     # 教材、判分、答题、离线答案队列、进度
│   ├── Models/                       # 教材数据模型
│   ├── Networking/                   # Bearer 鉴权的 API 客户端
│   ├── Onboarding/                   # 首启引导插图
│   ├── Resources/                    # 内置教材 JSON（由导出脚本生成）
│   └── Assets.xcassets               # 图标与颜色资源
└── JapaneseSyntaxCoachTests/         # XCTest 单元测试
```

## 环境要求

- macOS（当前验证环境：macOS 26.x，Xcode 16/17 系列）
- XcodeGen（`brew install xcodegen`）
- iOS 16.0+ 部署目标，Bundle ID `com.juxintong.nihongo`
- Swift Package：`supabase/supabase-swift`，精确版本 `2.39.0`（`Package.resolved` 已提交）

## 生成工程与构建

工程文件由 XcodeGen 生成，**不要手工编辑 `project.pbxproj`**。每次新增或删除 Swift 文件后
都必须重新生成并提交 `project.pbxproj`，否则提交态无法编译。

```bash
# 在仓库根目录执行
xcodegen generate --spec ios/project.yml

# Debug 构建 + 运行单元测试
xcodebuild test \
  -project ios/JapaneseSyntaxCoach.xcodeproj \
  -scheme JapaneseSyntaxCoach \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO

# Release 模拟器构建
xcodebuild \
  -project ios/JapaneseSyntaxCoach.xcodeproj \
  -scheme JapaneseSyntaxCoach \
  -configuration Release -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## 必填的构建设置

`SUPABASE_URL` 与 `SUPABASE_ANON_KEY` 在 `ios/project.yml` 中默认为空，仓库里**不存放任何
凭据**。缺少或填错时应用不会崩溃，而是进入“未配置”状态并给出说明。

| 设置 | 说明 |
| --- | --- |
| `SUPABASE_URL` | Supabase 项目地址，必须是 `https://` 开头 |
| `SUPABASE_ANON_KEY` | Supabase anon key（公开 key，可随 App 分发） |

命令行覆盖示例：

```bash
xcodebuild -project ios/JapaneseSyntaxCoach.xcodeproj -scheme JapaneseSyntaxCoach \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  SUPABASE_URL='https://<project>.supabase.co' \
  SUPABASE_ANON_KEY='<anon key>' \
  CODE_SIGNING_ALLOWED=NO build
```

匿名 key 之外的服务端凭据（service role key、Apple 私钥）**永远不能**放进 App。

## 需要在 Supabase / Apple 后台完成的手工配置

1. Supabase **Authentication → URL Configuration**：把 `nihongo://auth-callback` 加入
   Redirect URLs 白名单，否则邮件验证码链接与密码重置链接无法回到 App。
2. Supabase **Authentication → Providers**：启用 Apple provider 并填入 Apple 的
   Service ID / 密钥，App 的「通过 Apple 登录」才会生效。
3. Apple Developer 账号：App ID `com.juxintong.nihongo` 需要开启 **Sign in with Apple**
   能力，Provisioning Profile 里必须包含该能力。
4. App Store Connect：创建两个自动续期订阅商品（见下表），并创建订阅组。

## 商品与后端契约

| 项目 | 值 |
| --- | --- |
| 月付商品 | `com.juxintong.nihongo.monthly` |
| 年付商品 | `com.juxintong.nihongo.yearly` |
| 购买凭据提交 | `POST /api/apple/entitlements`，请求体 `{ "signedTransaction": "<JWS>" }` |
| 会员状态 | `GET /api/membership`（**唯一**的会员状态来源，客户端不自行推导） |
| 账号删除 | 本地 iOS 入口及服务端 `POST /api/account/delete` 暂不可用；本地服务端返回 503，尚未部署 |

上线前必须将服务端环境变量 `APPLE_SUBSCRIPTION_PRODUCT_IDS` 配置为包含上面两个商品 ID 的逗号分隔列表，并核对实际部署配置。本地服务端对账号 token 有效的交易在列表为空时抛出配置错误；不在非空列表中的商品以 `unknown-product` 被拒绝。账号 token 无效时会更早返回未更新；本地通知入口对有交易但未更新的结果返回 503，但这不保证通知持久保存或重试，其他通知处理缺口仍待解决。此改动尚未部署，线上行为须单独核实。

## 购买与同步的约定

- 价格与周期**只**从 StoreKit 读取，界面里不硬编码任何价格。
- 设计目标是在服务端确认接受或确认重复后才 `finish`，其他结果保留交易以供恢复；但队列写入失败及交易冲突仍有未解决的持久化缺口，不能保证所有记录都已安全保存或可重放。
- 队列按账号分区，交易的 Apple `appAccountToken` 用于确定归属；无归属记录不得推断为当前账号。跨账号交易冲突、持久冻结和完整证据保全仍未解决，不能将当前实现视为已证明隔离安全。
- 服务端比较 `appAccountToken` 与登录账号时**忽略大小写**：Apple 只保证它是一个 UUID 字符串，
  而 Supabase 用户 ID 是小写，大小写敏感比较会把本人购买误判成账号不匹配。
- 当前本地账号删除入口关闭，不会执行删除或购买队列清理。删除恢复机制完成并验证前，不得清除归属不明或待同步的购买记录；线上行为仍需单独核实。

## 教材资源

`ios/JapaneseSyntaxCoach/Resources/builtin-japanese-syntax.json` 是版本化的教材包，由网站
侧的 TypeScript 教材导出而来。**网站教材是唯一权威源**，改教材后必须重新导出：

```bash
npm run textbook:export:ios
```

导出的 JSON 带 `contentHash`，App 在运行时会用 canonical SHA-256 校验，不匹配会拒绝加载。

## 相关文档

- 发布前检查清单：`docs/ios/app-store-launch-checklist.md`
- App Store 元数据草稿：`docs/ios/app-store-metadata-draft.md`
- 测试矩阵：`docs/ios/test-matrix.md`
- 自动化验证日志：`artifacts/ios/validation.log`
- App 实际使用的隐私清单：`ios/JapaneseSyntaxCoach/PrivacyInfo.xcprivacy`。`docs/ios/PrivacyInfo.xcprivacy` 是旧参考副本，不是当前 App 构建使用的清单；上架前仍须核对实际归档、数据处理及 App Store Connect 隐私信息。
