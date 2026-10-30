# App Store 发布前检查清单

适用范围：`japanese-syntax-coach` 原生 iOS 客户端（Bundle ID `com.juxintong.nihongo`）。

**当前状态：第 1 节（代码与构建）已在 `ios-native-app` 分支验证通过，其余全部条目均为「未执行」。**
本仓库只包含代码与文档；App Store Connect 记录、上传、签名归档和提交审核都必须在获得明确
授权后由人工执行。本文中的每一项都不是「已完成」的声明。

图例：`[ ]` 未执行 · `[x]` 已完成并已验证

---

## 1. 代码与构建

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

## 2. Apple Developer 后台

- [ ] App ID `com.juxintong.nihongo` 已存在，App Store Connect 中已关联
- [ ] 开启 **Sign in with Apple** 能力
- [ ] Distribution / Release 的 Provisioning Profile 含 **Sign in with Apple** 与
      **In-App Purchase** 能力
- [ ] 团队 `RMBJCSP3G9` 下的 App Store Connect 权限已确认
- [ ] 已创建用于沙盒测试的 Apple 沙盒账号（**不要**写进仓库）

## 3. App Store Connect 记录

- [ ] 创建 App 记录：名称「日句」、主要语言「简体中文」、主要类别「教育」
- [ ] 填写 `docs/ios/app-store-metadata-draft.md` 中的名称、副标题、描述、关键词、
      支持 URL、隐私政策 URL、服务条款 URL
- [ ] 上传图标（1024×1024，无 alpha 通道）、截图（6.9" 与 6.5" 各至少一张）
- [ ] 隐私问卷按 `docs/ios/app-store-metadata-draft.md` 的「隐私披露」逐项作答
- [ ] 订阅组与两个自动续期商品已创建：
      - `com.juxintong.nihongo.monthly`（月度，¥18）
      - `com.juxintong.nihongo.yearly`（年度，¥180）
- [ ] 每个商品都填好显示名、描述、本地化、审核截图
- [ ] 订阅商品加入同一个订阅组，并设置等级（年付高于月付）
- [ ] 审核信息里填写完整的注册账号（邮箱 + 密码）
- [ ] 审核备注里说明：需要 Supabase 账号登录；会员需要沙盒购买；恢复购买入口在
      「账户 → 订阅与购买」

## 4. 服务端与 Supabase

- [ ] 生产环境的 `APPLE_SUBSCRIPTION_PRODUCT_IDS` 包含两个商品 ID
- [ ] 生产环境的 `APPLE_ROOT_CA_BASE64`（Apple 根证书）与 `APPLE_BUNDLE_ID` 已配置
- [ ] 生产环境的 `APPLE_ENVIRONMENT` 与 App Store 环境一致
- [ ] Supabase Redirect URLs 白名单包含 `nihongo://auth-callback`
- [ ] Supabase Apple provider 已启用
- [ ] 数据库迁移 `supabase/migrations/202610291400_native_answer_idempotency.sql`
      **已在生产库应用**（该迁移此前只准备了源文件，尚未上线）
- [ ] 生产环境 `NEXT_PUBLIC_SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` 正确

## 5. 签名、归档与上传

- [ ] 在 Xcode 中选择真实的 Team 与 Distribution 证书
- [ ] Archive 成功（`Product → Archive`），导出时的版本号与构建号已递增
- [ ] 归档产物已上传到 App Store Connect 并通过处理
- [ ] 提交前确认构建号在 ASC 中唯一

> 上述任何一步都会把产物交给 Apple，必须在获得明确授权后才执行。

## 6. 提交审核

- [ ] 提交前再次确认版本号、构建号、描述、隐私问卷、订阅商品都已就绪
- [ ] 提交审核并记录提交时间与审核单号

## 7. 提交之后

- [ ] 审核被拒时按 Apple 的反馈修复并重新归档上传
- [ ] 上线后用真实账号跑一遍：注册 → 登录 → 答题 → 同步 → 购买（沙盒）→ 恢复购买
- [ ] 确认 `https://japanese-syntax-coach.vercel.app/privacy` 与 `/terms` 可公开访问
      （App Store 审核会直接访问这两个地址）
- [ ] 确认线上 API 对 Bearer token 鉴权正常（网站 Cookie 登录不受影响）

---

## 已知未验证项（发布前必须人工验证）

| 项目 | 原因 |
| --- | --- |
| 真实沙盒购买 | 需要 Apple 沙盒账号与 ASC 商品配置 |
| 真实 Apple 登录 | 需要设备、配置好的 provisioning profile 与 Supabase Apple provider |
| Keychain 跨启动持久化 | SDK 已配置 `storageKey`，但未在真机证明 |
| 服务端验签往返 | 需要生产环境的 Apple 根证书与 `APPLE_SUBSCRIPTION_PRODUCT_IDS` |
| 迁移 `202610291400` 的线上效果 | 迁移只准备了源文件，尚未应用到线上 |
| 签名归档与上传 | 需要真实证书与明确授权 |
