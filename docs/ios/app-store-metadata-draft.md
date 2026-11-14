# App Store 元数据草稿

> **状态：历史草稿，不可直接用于提交审核。**
> 当前新订阅、恢复后的权益同步和账号删除均暂停；相关功能、安全接线和真实环境验证完成前不得提交本稿。
> App Store Connect 中的应用记录已创建（App ID `6831837064`，Team `RMBJCSP3G9`），Account Holder 已同意最新《Apple Developer Program 许可协议》（`免费 App 协议`生效期 `2026年11月1日 - 2027年7月28日`），版本 1.0 的「添加构建版本」与订阅页的「创建订阅群组」均已解锁；商务页 `付费 App 协议`（Schedule 2）状态为「有效（新协议可用）」。未经用户本人明确授权不得上传新构建或提交审核。

## 1. 基本信息

| 字段 | 值 | 状态 |
| --- | --- | --- |
| App 名称 | 日句 | 已在 App Store Connect 创建记录（App ID `6831837064`） |
| 副标题 | 看句型·听例句·练输出 | 草稿（≤30 字符） |
| 主要语言 | 简体中文 | 已定（`zh-Hans`） |
| 主要类别 | 教育（Education） | 草稿 |
| 附加类别 | 教材（Books）或 效率（Productivity） | 可选，待定 |
| Bundle ID | `com.juxintong.nihongo` | 已定 |
| SKU | `NIHONGO20261107` | 已定 |
| 加密出口合规 | `ITSAppUsesNonExemptEncryption = false`（Info.plist 已设置并已在签名归档 `202611070951` / `202611072210` 中核实） | 已定 |
| 版权 | © 2026 Beijing Three pony Technology Co.,Ltd | 草稿，待确认最终展示格式 |
| 最低系统 | iOS 16.0 | 已定 |
| 分级 | 4+ | 草稿，见第 5 节 |

## 2. 描述

### 2.1 简介（ promotional text，≤170 字符）

```text
24 课日语句型与语法练习：先看结构和例句，再自己组织输出。
```

### 2.2 完整描述

```text
日句是一款面向日语初学者的句型与语法练习应用。

• 24 课循序渐进的日语句型课程，从助词、授受表达到会话应答
• 24 课共 548 道练习，覆盖选择、助词、翻译、问答四种题型
• 答题记录与学习进度支持云端同步，并提供到期复习计划
• 阅读例句，结合练习理解句型
• 支持邮箱注册登录与「通过 Apple 登录」

学习流程很简单：先看句型结构和例句，再把读懂的内容自己写出来。

> 提交阻塞：新订阅和应用内会员权益同步目前暂停。以下订阅描述仅作恢复功能后的文案参考，不得用于当前版本提交。
>
> 订阅由 Apple 处理；可通过 App 内的管理入口前往 Apple 账户设置管理或取消订阅。
```

> 校对提示：完整描述中不应出现任何价格、促销或功能与 App 实际行为不符的表述。当前 App 内只有月付
> 与年付两个自动续期商品，价格以 App 内显示为准。

## 3. 关键词与 URL

| 字段 | 值 | 状态 |
| --- | --- | --- |
| 关键词（≤100 字符） | `日语,语法,句型,初级,例句,练习,错题,日本,备考` | 草稿 |
| 营销 URL | `https://japanese-syntax-coach.vercel.app/` | 草稿 |
| 支持 URL | `https://japanese-syntax-coach.vercel.app/support` | 已上线：页面包含支持邮箱 `service@niixmiro.com`，以及隐私政策和服务条款链接 |
| 隐私政策 URL | `https://japanese-syntax-coach.vercel.app/privacy` | 草稿（该页面已存在） |
| 服务条款 URL | `https://japanese-syntax-coach.vercel.app/terms` | 草稿（该页面已存在） |
| 自定义 EULA | 不使用，沿用 Apple 标准 EULA | 草稿 |

## 4. 订阅商品

| 商品 | 商品 ID | 展示价 | 周期 |
| --- | --- | --- | --- |
| 月度会员 | `com.juxintong.nihongo.monthly` | ¥18 | 每月自动续期 |
| 年度会员 | `com.juxintong.nihongo.yearly` | ¥180 | 每年自动续期 |

价格以 App Store Connect 后台配置为准，App 内只从 StoreKit 读取实际价格，不硬编码。

**App Store Connect 侧待办**

- [ ] 创建两个自动续期订阅商品与一个订阅组，年付等级高于月付
- [ ] 为每个商品填写显示名、描述、本地化与审核截图
- [ ] 配置商品审核信息与审核截图
- [ ] 确认服务端环境变量 `APPLE_SUBSCRIPTION_PRODUCT_IDS`（含两个商品 ID）、`APPLE_BUNDLE_ID=com.juxintong.nihongo`、`APPLE_APP_APPLE_ID=6831837064`、`APPLE_ROOT_CA_BASE64` 及 `APPLE_ENVIRONMENT` 已配置
- [ ] 在 App Store Connect「App 信息」页完成主要类别（教育）、内容版权、年龄分级（4+）及 ICP 备案/地区供应范围设置，在「价格与销售范围」页完成初始价格（免费 ¥0.00）与销售国家/地区设置

**订阅功能记录（当前不可作为可用功能或审核文案）**

- 订阅页可读取 StoreKit 商品价格与周期，并提供 Apple 订阅管理入口。
- 新购买已关闭；当前不能声称可提交购买或完成 Apple 订阅确认流程。
- 「账户 → 订阅与购买」仍显示恢复购买入口，但应用内会员权益同步已暂停；不能声称恢复后可同步或恢复会员权益。
- 隐私政策 / 服务条款链接指向站内页面；线上页面与当前暂停状态不一致，部署更改需另行授权。

## 5. 隐私披露

App Store Connect 隐私问卷（App 隐私）按以下内容填写：

| 数据类型 | 是否收集 | 是否与身份关联 | 是否用于追踪 | 用途 |
| --- | --- | --- | --- | --- |
| 用户 ID | 是 | 是 | 否 | App 功能 |
| 邮箱地址 | 是 | 是 | 否 | App 功能 |
| 用户内容 | 是 | 是 | 否 | App 功能 |

- 当前 App 隐私清单声明 `NSPrivacyTracking = false`（`ios/JapaneseSyntaxCoach/PrivacyInfo.xcprivacy`）；提交前仍须核实实际数据流与 SDK。
- 第三方 SDK：Supabase（认证与数据库）、StoreKit（Apple 支付，应用不接触付款信息）、VOICEVOX / AI
  服务仅在用户主动使用相关功能时处理教材内容。
- App 隐私清单 `ios/JapaneseSyntaxCoach/PrivacyInfo.xcprivacy` 当前声明 UserDefaults 的 `CA92.1`，并包括购买历史数据类型；提交前需结合实际用途、SDK 及归档隐私报告重新核对，不能仅凭草稿填写问卷。

**账号删除（App Store 指南 5.1.1(v)）**

- 当前 App 的「账户 → 删除账号」仅提示暂不可用，不发起删除或清除数据。
- **上架阻塞项**：完成安全的删除流程和真实权限验证后，重新核对实际删除范围、应用内路径及生产隐私政策；不得将当前入口描述为已完成删除。

## 6. 年龄分级

| 问题 | 答案 |
| --- | --- |
| 卡通或暴力 | 无 |
| 恐怖或惊悚 | 无 |
| 成人/性暗示题材 | 无 |
| 酒精、烟草或毒品 | 无 |
| 医疗/治疗信息 | 无 |
| 赌博（模拟） | 无 |
| 脏话或粗俗幽默 | 无 |
| 枪械或武器 | 无 |
| 现实暴力 | 无 |
| 人体或性主题 | 无 |
| 赌博与金钱 | 无 |
| 涉及酒精/烟草/毒品 | 无 |
| 医疗或治疗信息 | 无 |
| 人体或性主题 | 无 |
| 恐怖或惊悚 | 无 |
| 暴力 | 无 |

结论：**4+**。App 内没有用户之间的公开内容，只有学习者自己的答案与进度。

## 7. 审核信息

| 字段 | 值 | 状态 |
| --- | --- | --- |
| 审核联系邮箱 | 待填 | **待办** |
| 审核联系电话 | 待填 | **待办** |
| 演示账号（邮箱） | 待填 | **待办**：需要一个可用的测试账号 |
| 演示账号（密码） | 待填 | **待办**：不要写进仓库 |
| 演示账号（Apple 沙盒） | 待填 | **待办**：用于验证沙盒购买 |

### 历史审核备注（不可直接粘贴；功能完成并验证后重写）

```text
1. 本 App 需要账号。请使用「审核信息」中提供的演示账号登录（邮箱 + 密码）。
   也支持「通过 Apple 登录」，但审核环境建议直接使用演示账号。

2. 会员功能需要订阅。沙盒购买步骤：
   账户 → 订阅与购买 → 选择「月度会员」或「年度会员」→ 确认购买（系统弹出 Apple 订阅确认框）→ 输入
   Apple 沙盒账号完成购买。购买完成后 App 会把购买凭据提交到服务端验证，验证通过后会员状态变为
   「已开通会员」。

3. 恢复购买：账户 → 订阅与购买 → 恢复购买。

4. 账号删除：账户 → 删除账号 → 确认删除。删除后云端学习记录与本机数据都会被清除。

5. 隐私政策与服务条款可在「账户 → 订阅与购买 → 条款与隐私」以及 App 内链接访问。

6. 首次启动会显示 4 页引导说明，点击任意位置即可翻页，右上角「跳过」可直接进入登录页。
```

## 8. 截图与图标

- [x] 当前 worktree 的 1024×1024 App Store 图标已检查为 PNG 且无 alpha 通道，并已在 Release 签名归档 `202611070951` 与 `202611072210` 中完成打包核验
- [ ] iPhone 至少提交 1 张截图；至少 1 张须来自 Dynamic Island 中屏设备。`1206×2622` 与 `1179×2556`（iPhone 16 6.1" Dynamic Island 原生尺寸）均为 Apple 接受的尺寸，同一槽位需保持统一尺寸，具体要求以 [Apple 当前截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) 为准
- [ ] `artifacts/ios/screenshots/app-store-candidates/` 当前包含（均经 `sips` 核验为无 Alpha 通道 `hasAlpha: no`）：
  - `1206×2622` 引导页/登录页候选图 2 张（`01-onboarding-1.png`、`02-auth.png`）
  - `iphone-6.1-1179x2556/` 下全套 5 张核心学习界面（`01-home`、`02-grammar-detail`、`03-course-list`、`04-question-view`、`05-mistakes`）原生 `1179×2556` 无 alpha 候选图 + 2 张 iPhone 16 真机原生无 alpha 副本（`03-course-list-device-1179x2556.png`、`05-mistakes-device-1179x2556.png`）
  - `iphone-6.3-1206x2622/` 下全套 5 张核心学习界面原生 `1206×2622` 无 alpha 候选图
  - `iphone-6.9-1320x2868/` 下全套 5 张核心学习界面原生 `1320×2868`（Apple 6.9" 主展示尺寸）无 alpha 候选图
  - 另已在 `build/ios-web-alignment/` 留存 iPhone 16 真机 5 大核心页面验收截图；正式上传 App Store Connect 前需结合人工画面审核选定对应尺寸槽位上传
- [ ] 正式截图应覆盖真实可用的首页、教材、答题、进度与账户体验；新购买、权益同步和删除目前暂停，不能用截图暗示这些功能已可用

## 9. 未完成事项汇总

- [x] 支持 URL 指向已上线的支持页面：`/support`（含支持邮箱及政策链接）
- [x] 已在用户授权下创建 App Store Connect 应用记录（App ID `6831837064`）并上传首个构建 `202611070951`（TestFlight 状态已就绪为「准备提交，89 天后过期」）；最新 Web 对齐 UI 与 `StoreKitManager` 生命周期修复构建 `202611081217` 已完成本地 Release 归档与 Apple Distribution 签名导出核验（待用户本人确认后再上传）
- [ ] 核实生产隐私政策中的账号删除路径与实际删除流程（当前客户端与服务端 `POST /api/account/delete` 均为 fail-closed）
- [ ] 审核联系信息与演示账号（邮箱、密码、Apple 沙盒账号）
- [ ] Account Holder 已完成《Apple Developer Program 许可协议》更新并解锁「添加构建版本」与「创建订阅群组」；若启用付费订阅，仍需在商务页同意最新《付费 App 协议》（Schedule 2）并完成 App Store Connect 商品、订阅组、审核截图与本地化配置（或按免费工具版路线隐藏未闭环购买入口）
- [x] 1024×1024 App Store 图标格式与 alpha 已在当前 worktree 及 Release 签名归档 `202611070951` / `202611072210` / `202611081217` 中核实
- [ ] iPhone 截图须补齐统一尺寸的核心学习页面并完成人工画面审核后再上传
- [x] 已通过 `tests/ios-privacy-manifest.offline.test.py` 及 IPA 解包核实主包 `PrivacyInfo.xcprivacy` 与 `swift-crypto` 隐私清单；最终提交前仍须在 App Store Connect 后台核对线上隐私问卷
- [ ] 取得用户本人明确授权后，才上传新构建 `202611081217` 或提交 App Store 审核
