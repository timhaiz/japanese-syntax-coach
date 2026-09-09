666# 句型教练实施计划

> 目标：把《标准日本语》第二版上册的课程内容，做成一个以“中文 → 日语主动输出”为核心的移动端 PWA。所有功能按小步增量交付；每个阶段必须通过验收并提交 Git 后，才能进入下一阶段。

## 1. 项目原则

1. 先保证学习闭环，再扩展功能：登录 → 学习句型 → 作答 → 批改 → 错题/复习 → 进度同步。
2. 规则判分优先于 AI。AI 只负责自然度、解释和记忆提示，不能覆盖确定性的助词、句型和拼写判定。
3. 题库、课程资料和页面逻辑分离。页面只调用题库，不直接维护题目。
4. 只录入已获授权使用的内容；不抓取或复制教材网站的原文、插图和音频。
5. 任何新功能先写验收条件；失败的尝试不继续叠加，回到最近一次通过检查的提交重新实现。
6. 每次执行结束必须更新本文件：勾选实际完成项，记录验证命令、Git commit、部署状态与仍未完成的内容；不得把占位内容标记为教材校对完成。

## 2. 当前状态（基线）

### 已完成

- [x] Next.js + TypeScript 移动端 PWA 外壳。
- [x] Supabase 邮箱+密码注册、验证码确认和密码登录。
- [x] 用户学习进度、课程完成状态和错题写入 Supabase 用户元数据；旧版每日任务字段仅保留兼容读取。
- [x] 本地规则批改；省略句末标点仍判定正确并给出书写提醒。
- [x] 独立题库 `lib/question-bank.ts`，第 1～3 课各至少 20 题，题目 ID 稳定（如 `L01-Q001`）。
- [x] 错题本和错题练习入口。
- [x] AI 分析入口使用 OpenAI Responses API，AI 不阻塞提交结果。
- [x] 课程解锁根据课程完成状态计算，并兼容旧版只保存 `done`/`lessonDone` 的数据。
- [x] 首页当前课程入口、整课进度和掌握度展示；旧版每日任务仅保留数据兼容，不参与当前流程。
- [x] Vercel 生产部署流程可用（当前通过 CLI 手动部署）。

### 当前已知限制

- [x] 复习项目、`nextReviewAt`、重复次数和错误回退已由 Supabase migration/RPC 持久化；仍需真实账号跨设备验收。
- [x] 第 4～24 课已补齐核心课程说明和每课至少 20 道具体题；仍需持续人工教材抽检，不把自动生成内容视为最终校对。
- [x] 第 1～24 课题型统一为选择、助词、翻译、问答，并通过稳定 ID、字段完整性和顺序回归测试。
- [x] 整课练习已移除每日 10 题逻辑，使用完整题库和 `lessonDone`／`lessonCorrect` 计算完成与解锁。
- [x] 题库已使用静态字段，`questionsForLesson` 与 `questionForId` 读取同一来源；不再使用随机题目 ID。
- [x] 修复选择题判分：选项字母会解析为对应选项内容；助词题选择 `B` 会按「の」与标准答案比较。
- [x] 作答、复习项目和课程进度已迁移至 Supabase 数据表；旧用户元数据保留为兼容回退，旧版每日任务不再参与当前练习。
- [x] 已建立 Playwright 端到端测试脚本，覆盖第 1 课主路径和认证表单基础校验。
- [x] Vercel Git 自动部署已连接 GitHub 仓库；手动 CLI 部署仍可作为紧急发布方式。

## 3. 精简后的开发范围

### 本阶段必须完成

1. 可靠的跨设备进度同步和账号切换隔离。
2. 第 1～3 课完整、可回归的题库和练习闭环。
3. 真正持久化的错题和间隔复习记录。
4. 首页只展示真实状态，不显示固定的进度、待复习题量或掌握度。
5. 手机窄屏、刷新、重新登录和生产环境的核心流程测试。

### 暂不开发

- 精确发音评分、声调评分和实时语音对话。
- 复杂社交功能、排行榜、好友系统和公开分享。
- 自动从教材网站抓取内容。
- 多模型路由、复杂的 AI 代理编排和自动生成整课题库。
- 离线提交后自动冲突合并；首版只支持缓存课程页面，提交需要联网。

## 4. 未来想法（单独管理，不进入当前迭代）

- [未来] 接入语音识别和发音评估。
- [未来] 根据错误类型自动生成个性化复习包。
- [未来] 教师/管理员题库编辑后台和内容审核流。
- [未来] 课程主题、连续学习徽章和可选订阅方案。
- [未来] 离线答题队列及多设备冲突合并。

## 5. 增量实施里程碑

### M0：建立测试和提交护栏

**目标**：让后续修改可验证、可回退。

- [x] 增加最小端到端测试工具和 `test:e2e` 脚本。
- [x] 固定第 1 课回归题：正确答案、漏标点、错误答案、错题收录。
- 记录测试账号和 Supabase 测试数据约定，不把密钥提交到 Git。

**验收**：测试能启动应用，覆盖第 1 课练习主路径；`build`、`tsc` 和 E2E 均通过。当前 M0 已完成；登录回调的真实邮箱验证留到 M1 的测试账号环境中执行。

### M1：跨设备同步稳定化

**目标**：同一 Supabase 账号在 Chrome 和 Safari 看到一致的课程、错题和整课进度。

- [x] 增加邮箱+密码注册、邮箱验证码确认和密码登录。
- [x] 为旧的无密码账号提供“设置密码”邮件流程；该链接仅用于密码设置，不作为登录方式。
- [x] 统一进度数据结构和版本号。
- [x] 登录、刷新、账号切换时先完成云端 hydration，再允许本地状态写回。
- [x] 对旧版 `done`、`lessonDone`、`completedLessons` 做一次性兼容迁移。
- [x] 保存失败时记录可见状态和控制台错误，不静默丢失；用户可手动重试。
- 用 Supabase 表替代无限增长的用户元数据（见 M4），迁移期间保留回退读取。

**验收**：注册用户能收到验证码并完成邮箱确认，之后可用邮箱+密码登录；设备 A 完成一课后，设备 B 刷新即可解锁下一课；切换到另一账号不会看到前一账号数据。Chrome/Safari 同账号的真实 Production 会话已验收；解锁仅由实际 20 题及 90% 正确率证据决定。

**当前课程缓存修复（2026-09-09）**：修复旧设备 `completedLessons` 缓存可能在登录态解析前把首页误判为第 24 课的问题。当前课程、课程锁定与同步写回均重新以答题数和正确数验证，并且只承认从第 1 课连续完成的课程；登录用户不会再用本地完成列表覆盖云端状态。增加连续 `0–23` 陈旧完成标记的回归测试。

**第 1 课逐题教材校对（2026-09-09）**：以教材 PDF 第 40 页语法解释和第 45 页练习为依据，逐项核对第 1 课的「N は N です」「N は N ではありません」「N は N ですか」及其肯定／否定／不知道应答，以及机构、国家和属性的「N1 の N2」。移除混入第 2 课的指示词／「何ですか」题干，改为教材中的 JC企画、中国企业、大学教师与疑问应答练习；保留 `L01-Q001`～`L01-Q020` 的稳定 ID。新增内容范围回归测试。第 2～24 课的逐题教材校对仍待按课次继续。

**第 2 课逐题教材校对（2026-09-09）**：以教材 PDF 第 50～51 页语法解释为依据，核对「これ／それ／あれ」「だれですか／何ですか」「N の N」「この／その／あの N」和「どれ／どの N」。将核心 20 题中泛化的所属／否定题替换为「だれ」「どれ」「どの」专项，确保用户完成整课核心练习已覆盖全部本课语法；删除已不适用的第 2 课否定可接受答案映射。保留稳定题目 ID，并新增核心题范围回归测试。第 3～24 课的逐题教材校对仍待按课次继续。

**第 3 课逐题教材校对（2026-09-09）**：以教材 PDF 第 60～61 页语法解释为依据，核对地点指示、地点判断、地点询问、「も」、选择问句与「いくら」。将核心 20 题中的泛化地点／否定题替换为「も」、二选一问句及价格问句，确保完成整课核心练习已覆盖本课全部语法；删除已不适用的否定可接受答案映射。保留稳定题目 ID，并新增核心题范围回归测试。第 4～24 课的逐题教材校对仍待按课次继续。

**第 4 课逐题教材校对（2026-09-09）**：以教材 PDF 第 70～71 页语法解释为依据，确认 `あります／います`、存在地点 `に`、方位词 `N の 上／下／前／後ろ／隣／中／外`、并列 `と` 已覆盖；将原有外围位置题替换为教材明确的句尾确认 `ね`、疑问词 `も＋否定`（だれもいません、何もありません），确保核心 20 题覆盖本课全部语法。保留稳定题目 ID，并新增核心题范围回归测试。第 5～24 课的逐题教材校对仍待按课次继续。

**第 5 课逐题教材校对（2026-09-09）**：以教材 PDF 第 85～88 页语法解释和练习为依据，核对现在／过去肯定否定、具体时间 `に`、`から／まで`、`いつ`、大约时间 `ごろ` 和对比用 `は`。将核心题中的泛化时间范围题替换为教材「昨日12時半ごろ寝ました」和时间对比表达，新增核心题范围回归测试。第 6～24 课的逐题教材校对仍待按课次继续。

**第 6 课逐题教材校对（2026-09-09）**：以教材 PDF 第 96 页语法解释和第 95 页课文为依据，逐项核对目的地 `へ`、起点 `から`、同行者 `と`、交通工具 `で`、步行 `歩いて`、移动范围 `から～まで` 及 `どこから／何で／誰と` 问答。现有核心 20 题已完整覆盖这些结构，未发现需要安全替换的题目；补充审计记录并保留题目不变。第 7～24 课的逐题教材校对仍待按课次继续。

**第 7 课逐题教材校对（2026-09-09）**：以教材 PDF 第 105～106 页语法解释和课文为依据，核对宾语 `を`、动作场所 `で`、选择 `か`、请求 `Nをください`、邀请 `ませんか` 与提议 `ましょう`。将核心题中的工具动作翻译替换为教材明确的「この本をください」，并增加核心题范围回归测试；其余手段、语言和问答表达已覆盖。第 8～24 课的逐题教材校对仍待按课次继续。

**第 8 课逐题教材校对（2026-09-09）**：以教材 PDF 第 115～117 页语法解释和课文为依据，核对手段／材料 `で`、`あげます`、`もらいます`、会面对象 `に`，以及表达「もう」和句尾提醒「よ」。将核心题中的普通授受翻译替换为教材中的「もう昼ご飯を食べました」和「もう帰りましたよ」，并增加核心题范围回归测试；第 9～24 课的逐题教材校对仍待按课次继续。

**进度读取回归修复（2026-09-09）**：整课入口在本地缓存 hydration 尚未完成时，直接从本地持久化进度读取已答题数，避免用户点击课程后从第 1 题重新开始或重练统计被误写为 1。该读取仅作为未登录本地回退，登录态仍以云端状态为准。

### M2：第 1～3 课内容质量

**目标**：每课先讲语法，再进行针对性练习。

- [x] 第 1～3 课各维护教材对应的语法点、接续、用法说明、应答和易错点；第 1 课已覆盖判断、否定、疑问与应答、`N1 の N2`（所属/机构/国家/属性）。
- [x] 第 1～3 课各有至少 20 道稳定 ID 的练习题，覆盖翻译、助词、选择和问答。
- [x] 第 1～3 课全部题目已使用 AI 逐题核对标准答案、可接受答案和提示。
- [x] 本次内容初稿使用 AI 辅助并通过结构回归；第 1～24 课仍需人工逐题抽检标准答案、可接受答案和提示。
- [x] M2.1 已完成第 1～3 课的 AI 辅助题目抽检和重复题扫描；修正第 1 课助词题答案为单独的「の」，并将第 1 课无选项的选择题改为具体翻译题。
- [x] 第 1～24 课选择题均有可见选项；助词题使用日文句子和选项，翻译题才使用文本输入。
- [x] 课程完整练习不限制为 10 题；每课固定练习完整题库，完成且正确率达到 90% 后解锁下一课并展示预告。
- [x] 前端已增加整课练习入口：按当前课全部题目练习，提交后统计答对数，达到完整题库且正确率 90% 后解锁下一课，并显示下一课预告；当前不再使用每日 10 题模式。
- [x] 新增 `lesson` 作答模式和 Supabase migration，保存整课 `answered_count` 与 `correct_count`。
- [x] 已在生产 Supabase 执行 `202609070002_lesson_accuracy.sql`；`correct_count` 已接入前端 study-state hydration，完成跨设备的 90% 正确率同步基础。
- [x] 第 2、3 课现有选择题已增加可见选项按钮；点击选项后提交，仍按选项字母进行规则判分。
- [x] 各课练习题按“选择 → 助词填写 → 翻译 → 问答”排序；第 1 课已补充稳定 ID 的选择题，进入练习不再以翻译题开场。
- [x] 助词题改为日文句子中的空格，并使用选择按钮；只有翻译题保留文本输入框。
- [x] 题型交互回归测试已同步；当前完整 E2E 为 12/12。
- [x] 前端已接入 `study-state` 的 `correct_count` hydration；登录或刷新后会恢复每课正确数。

**最近执行记录（2026-09-07）**：已按 PDF 逐页核对第 1～3 课语法页，并将接续、说明、应答和易错点展示到课程页；新增第 1 课语法说明 E2E。`npx tsc --noEmit`、`npm run build`、`npm run test:e2e`（10/10）通过；已提交并部署 `8560430 feat: expand lessons one through three grammar`。后续按第 4 课起逐课补全，每完成一课都更新本记录。

**M2.1 执行记录（2026-09-07）**：完成第 1～3 课 AI 辅助抽检和重复题扫描，修正第 1 课助词题答案及第 1 课无选项选择题；第 2、3 课旧格式选择题列为后续修正项。`npx tsc --noEmit`、`npm run test:e2e`（11/11）和 Vercel production build 通过。代码提交 `a793a15 fix: audit lesson one question answers`；生产部署 `dpl_H4Pjeb7PpQKZEAPiRJKqcytfjLzf` 已 READY。

**新增需求记录（2026-09-07）**：后续课程题库需要混合翻译、选择、填写等题型；课程题量可超过 10 题；课程完成与解锁按完整题库的至少 90% 正确率计算，完成后展示下一课内容预告。该需求将与题型交互和云端正确率字段一起实现，避免继续使用“答满 10 题即完成”的旧逻辑。

**本次执行记录（2026-09-07）**：新增整课练习模式和下一课预告；整课使用完整题库，完成后按 90% 正确率解锁。`npx tsc --noEmit`、`npm run build`、`npm run test:e2e`（11/11）通过。代码提交 `53c6723 feat: add full lesson practice accuracy gate`；生产部署 `dpl_FBLaY3zBSrSKfjNM23bKS9nR9XiM` 已 READY。云端正确率持久化和第 2、3 课选择题交互列为下一步。

**正确率持久化执行记录（2026-09-07）**：新增 `supabase/migrations/202609070002_lesson_accuracy.sql`，扩展课程进度约束、正确数和 `lesson` RPC 模式；API 已允许 `lesson` 作答，`study-state` 已返回 `correct_count`。本地 `tsc` 与 E2E（11/11）通过；待在生产 Supabase SQL Editor 执行迁移，并补前端读取。

**前端 hydration 执行记录（2026-09-07）**：登录或刷新时读取 `correct_count` 并恢复课程正确率。`npx tsc --noEmit`、`npm run build`、`npm run test:e2e`（11/11）通过；生产部署 `dpl_7Vgz3zAdhMiw736ATtoPvVeTTvEQ` 已 READY。生产 Supabase migration 已由用户执行成功。

**选择题交互执行记录（2026-09-07）**：为第 2、3 课选择题补充具体选项按钮和选中状态，避免用户只能手动输入 A/B/C；`npx tsc --noEmit`、`npm run test:e2e`（11/11）通过；生产部署 `dpl_BjuMkXPWsNUPVUsfqcHNkzV8dBkP` 已 READY。

**题型顺序执行记录（2026-09-07）**：题库读取统一按“选择 → 助词填写 → 翻译 → 问答”排序；第 1 课增加 `L01-Q021` 选择题并显示可点击选项。更新回归测试后 `npx tsc --noEmit`、`npm run test:e2e`（11/11）通过；生产部署 `dpl_CQNq1q9imHqY6e5GMzUzeZm84BzP` 已 READY。

**助词题交互执行记录（2026-09-07）**：助词题显示日文句子（如 `これは私___本です。`），选项为 `は／の／も`；文本输入框仅用于翻译题。已提交 `f0950d2 fix: present Japanese fill prompts as choices`，生产部署 `dpl_DK4GJxTfRPWvB1YtnKuMpBGNhB6q` 已 READY。当前旧 E2E 中仍有 3 个场景假设第一题为文本输入，需要后续调整测试夹具；TypeScript 和生产 Build 已通过。

**全项目只读审计记录（2026-09-07）**：已检查 `app/`、`lib/`、`supabase/migrations/`、`tests/`、`package.json`、Git 提交和 Vercel 部署记录，未修改业务代码。确认当前课程数据只有第 1～3 课完整语法说明，第 4～24 课为 `lib/courses.ts` 中的简化占位语法；题库集中在 `lib/question-bank.ts`，课程 1～3 各 20 道。Supabase 已有学习记录、复习状态、课程进度、每日任务和正确率 migration；生产 migration 已由用户执行。当前需要优先修复进度模型和题库单一来源，再继续扩充教材内容。

**选择题判分修复记录（2026-09-07）**：修复助词题选择 `B：の` 被当作字符串 `B` 与标准答案 `の` 比较而判错的问题；新增助词选择回归测试，单项通过。TypeScript、Vercel production build 通过；部署 `dpl_GJDALR7mEtgF9HhYwh1JbJ5AtQ15` 已 READY。

**验收**：每课 20 题以上；刷新或重新进入同一练习不会因随机 ID 造成重复错题；第 1～3 课题目均能被题库函数取出。

### M3：规则判分和错题闭环

**目标**：提交即时返回结果，错误可追踪、可重练。

- [x] 修复提交后题目与输入答案错位：提交只展示当前题的批改结果，点击“下一题”后才推进题目和清空输入。
- [x] 规则层判定助词、句型顺序、否定/疑问、词汇、假名和标点。
- [x] 统一结果：`correct`、`mostly_correct`、`needs_fix`、`incorrect`。
- [x] 错题按稳定题目 ID 去重；答对错题后更新状态或移出待练集合。
- [x] AI 分析按钮独立于提交，不因 AI 超时阻塞练习。

**验收**：漏标点判对但提醒；“でわありません”等假名错误进入错题并标记假名/拼写；错题本可以单独完成一轮练习。

**最近执行记录（2026-09-07）**：修复答题提交后题目先切换、答案仍显示上一题的问题；新增“提交后保持当前题目，点击下一题才切换”E2E 回归测试。`npx tsc --noEmit`、`npm run build`、`npm run test:e2e`（11/11）通过；代码已提交并推送（`d7a7469 fix: keep question and answer aligned after submit`），并已部署到生产（Vercel `dpl_FDcmPg4u5sFohwCTgGmZ79rJEzwX`，`https://japanese-syntax-coach.vercel.app`）。

### M4：持久化间隔复习

**目标**：复习安排跨设备、跨日期持久化。

- [x] 在 Supabase 建立用户级作答、复习项目、课程进度和每日任务表。
- [x] 实现当天、+1、+3、+7、+14、+30 天间隔；错误答案回退到当天。
- [x] 每次作答原子更新：答案、结果、错误标签、复习间隔、`nextReviewAt`、课程进度和每日题量。
- [x] 今日复习优先读取最多 5 道到期题；无到期题时保留旧课复习回退。
- [x] 每完成 5 课生成稳定的混合复习集合；服务层、`POST /api/create-review-set` 和首页“综合混练”入口均已接入。

**验收**：本地类型、构建与 9 条 E2E 回归测试通过；迁移已应用到生产 Supabase。生产部署后仍需用真实账号验证设备 A 答错后设备 B 刷新可见到期题，以及第 5、10、15、20 课的混练（M4.1）。

### M5：首页和设置收尾

**目标**：首页只表达可行动、可信的状态。

- [x] 当前课程入口、课程进度和掌握度全部来自统一数据源；旧版每日任务字段不再参与当前练习。
- [x] 课程卡片显示当前未完成课程；全部完成时显示完成状态。
- [x] 个人页显示注册时间、完成课程数和累计练习；旧版每日积分字段已随每日任务下线，不再展示虚假积分。
- [x] 加入同步状态、登录异常和 AI 不可用时的明确提示。

**验收**：首页无固定进度数字；所有按钮进入对应模式；窄屏无横向滚动，刷新不丢状态。

### M6：发布和质量检查

**目标**：每次发布都有可追溯证据。

- 生产环境变量检查：Supabase URL/anon key、AI base URL/key/model。
- 运行本地检查和 E2E；再执行 Vercel production deploy。
- 在生产地址验证登录回调、提交答题、错题本和跨设备读取。
- 记录部署 URL、Git commit、检查结果和已知限制。

**验收**：部署状态 READY；核心测试全部通过；回滚点明确。

### M7：题库与进度模型收敛（下一阶段）

**目标**：让题型、题库、课程完成状态和测试使用同一套数据定义。

- [x] 清理 `L01-Q021` 旧兼容题和运行时题型覆盖，改为静态题库字段：`type`、`prompt`、`answer`、`options`。
- [x] 增加规范化题目入口和 `options` 类型；`questionForId()` 与 `questionsForLesson()` 现在经过同一套规范化逻辑。
- [x] 删除旧的 `L01-Q021` 注入、重复 `choiceOptions` 来源；页面统一读取规范化题目的 `options`。
- [x] 将第 1 课早期题目的兼容型运行时覆盖改写为静态题库字段：`type`、`prompt`、`answer`、`options`。
- [x] 删除每日 10 题进度，统一使用整课答题进度；登录和跨设备恢复读取 `lesson_progress`。
- [x] 整课模式固定 20 题，累计正确率达到 90% 后解锁下一课；刷新后保留课程进度。
- [x] 更新并补齐 E2E：选择题、助词选择、翻译输入、错题选择题、整课 20+ 题、跨设备正确率；题库字段与题型顺序回归检查已加入，全部通过。
- [x] 第 1～24 课已补全课程核心语法与题库；仍需人工逐题抽检并持续内容精修。

**验收**：同一题库函数在课程、首页、错题本和复习模式返回一致题目；每日进度不影响整课进度；整课完成且正确率 ≥90% 后才解锁下一课；全量 E2E、TypeScript、Build 通过。

**M7.1 执行记录（2026-09-07）**：完成规范化题目入口和选项字段接入；助词选择回归测试通过，TypeScript 和 Vercel production build 通过。提交 `0f22f5a refactor: normalize question bank access`；部署 `dpl_4XsuDwCFa66oMSS6PajNT3Rt7cJD` 已 READY。每日/整课进度拆分、旧兼容题清理和全量 E2E 仍待完成。

**M7.2 执行记录（2026-09-08）**：删除 `L01-Q021` 旧兼容题注入和重复 `choiceOptions` 映射；页面与判分统一读取规范化题目的 `options`。全量 `npm run test:e2e`（12/12）通过，TypeScript 通过。仍需拆分每日/整课进度，并把第 1 课兼容型题型覆盖改成静态题库字段。

**M7.3 执行记录（2026-09-08）**：修正每日新题与整课进度混用问题。每日训练仍限制为 10 题，但答题会累计到整课题数（当前题库每课 20 题以上），并同步累计整课正确数；课程完成判定改为完成该课全部题目且正确率 ≥90%，不再因完成每日 10 题提前解锁下一课。旧本地进度读取上限提升至 100，云端 `lesson_progress.correct_count` 继续作为整课正确率来源。`npx tsc --noEmit`、`npm run build`、`npm run test:e2e`（12/12）均通过。Vercel 生产部署 `dpl_Ckh9iN9ag3rEhbtTp2WskKHKAV14`（`japanese-syntax-coach-fbapshba8-timhai06.vercel.app`）已 READY，并已绑定主域名。

**M7.4 执行记录（2026-09-08）**：将第 1 课 Q001、Q003、Q007 的选择/助词题完整写入静态题库，移除运行时 `normalizeQuestion`、兼容 prompt 和 `optionMap`。页面现在直接消费题库字段。TypeScript、Build、E2E（12/12）通过。提交 `9eea9e1`；Vercel 部署 `dpl_4wSpTSyYrgwKH31zJEE6y7UgueBC` 已 READY。

**M7.5 执行记录（2026-09-08）**：对第 1～3 课题库增加回归护栏，验证每课至少 20 题、稳定唯一 ID、字段完整、选择题答案存在于选项、题型顺序为选择→助词→翻译→问答。`npm run test:e2e` 共 16 项全部通过（新增题库检查 4 项，原有 12 项保持通过）。提交 `a9b4622`；Vercel 部署 `dpl_2n3b3NF6EGGQBQW3YnrDc5KNASpU` 已 READY。

**M7.6 执行记录（2026-09-08）**：根据教材第 4 课「部屋に机といすがあります」补全课程语法与 20 道题，覆盖 あります／います、存在地点「に」、主题位置句、方位词「の」、并列「と」，题型按选择→助词→翻译→问答排列。题库回归检查扩展至第 4 课，TypeScript、Build、E2E（16/16）通过。提交 `4ed993aa`；Vercel 部署 `dpl_ECLahJtaZM2f5GEsAA9qgvFpY1zL` 已 READY。

**M7.7 执行记录（2026-09-08）**：优化规则批改反馈，改为定位具体错误。支持识别「ですか」误写为「でか」、否定「では」误写为「でわ」、缺字、多字和第一个不同字符；所有题型共用同一说明函数，并新增 E2E 回归场景。TypeScript、Build、E2E（18/18）通过。提交 `efc04549`；Vercel 部署 `dpl_5dUvPNfbjWzf3ez8PrmgVQgk4KUx` 已 READY。

**M7.8 执行记录（2026-09-08）**：根据教材第 5 课「森さんは 7時に 起きます」补全课程语法与 20 道题，覆盖时间表达、ます／ません、ました／ませんでした、时间「に」、起止时间「から／まで」和「いつ」问句。题库回归检查扩展至第 5 课。提交 `6328f9c1`；Vercel 部署 `dpl_BNAD1t5Rroq1sRDBBVzw1AET5p36` 已 READY。

**M7.9 执行记录（2026-09-08）**：修复练习游标混用问题。每日训练、复习和错题练习使用独立的本次会话序号，从第 1 题开始；整课累计答题数只用于课程进度和解锁，不再驱动当前题目；移除每日训练自动跳课逻辑，避免完成 10 题后跳到第 24 课。新增回归测试验证整课已有进度时每日训练仍从 1/10 开始。TypeScript、Build、E2E（20/20）通过；提交 `8e3b7f8d`；Vercel 部署 `dpl_4oykBACFfRmSaPSb1ZDnB5SXXMBa` 已 READY。

**M7.10 执行记录（2026-09-08）**：按产品调整删除每日 10 题、每日 5 题复习、20 分钟计时和每日积分领取逻辑。首页改为当前课程入口；每课固定完成 20 题，整课进度和正确率用于解锁下一课；练习提交统一使用 `lesson` 模式。个人页改为显示累计练习，不再显示每日训练和今日积分。已删除旧 `update-daily` API，学习状态接口只读取课程进度、错题复习和正确率。TypeScript、Build、E2E（20/20）通过。提交 `a8739eef`；Vercel 部署 `dpl_4FsBLpc8wowKELbyChbFNsEAufEU` 已 READY。

**M7.11 执行记录（2026-09-08）**：根据教材第 6 课「吉田さんは 来月 中国へ 行きます」补全课程语法与 20 道题，覆盖移动目的地「へ」、起点「から」、交通工具「で」、同行者「と」以及时间疑问。题库回归检查扩展至第 6 课。提交 `cc4fa89d`；Vercel 部署 `dpl_BTtRgJjnnC4AAFyeYRmSQTuQonQt` 已 READY。

**M7.12 执行记录（2026-09-08）**：根据教材第 7 课「李さんは 毎日 コーヒーを 飲みます」补全课程语法与 20 道题，覆盖宾语「を」、工具/语言「で」、选择「か」、邀请「ませんか」和提议「ましょう」。题库回归检查扩展至第 7 课。提交 `5b8f4034`；Vercel 部署 `dpl_EwJo2mSV9JQKK1LFjHuVyV6MqXmY` 已 READY。

**M7.13 执行记录（2026-09-08）**：根据教材第 8 课「李さんは 日本語で 手紙を 書きます」补全课程语法与 20 道题，覆盖给予「に～をあげます」、获得「に／から～をもらいます」、会面对象「に会います」和相关问答。题库回归检查扩展至第 8 课。提交 `4ada3462`；Vercel 部署 `dpl_8uGnVwM86hiVe8JUYqt3ceLtEs5X` 已 READY。

**M7.14 执行记录（2026-09-08）**：根据教材第 9 课「四川料理は 辛いです」补全课程语法与 20 道题，覆盖い形容词肯定、否定、过去、过去否定、程度副词「とても／あまり」和「どうですか」问答。题库回归检查扩展至第 9 课。提交 `850451a2`；Vercel 部署 `dpl_F9wWmVYF6uHgStwNko7cXVVGiTcX` 已 READY。

**M7.15 执行记录（2026-09-08）**：根据教材第 10 课「京都の紅葉は 有名です」补全课程语法与 20 道题，覆盖な形容词肯定、否定、过去、过去否定、名词修饰「な」、程度表达和「どんな N」问句。题库回归检查扩展至第 10 课。提交 `a4ede372`；Vercel 部署 `dpl_EBzmNiSvixhm2t1m4cmM7C64Jc6a` 已 READY。

**M7.16 执行记录（2026-09-08）**：根据教材第 11 课「小野さんは 歌が 好きです」补全课程语法与 20 道题，覆盖「N が 好きです／嫌いです」「N が 上手です／下手です」「N が 分かります」、程度副词「よく／だいたい／あまり／全然」和「どんな N が 好きですか」。题库回归检查扩展至第 11 课；`npx tsc --noEmit`、`npm run build`、`npm run test:e2e -- --workers=5`（25/25）通过。代码提交 `94a91baa`；Vercel production 部署 `dpl_ACBEWub1QhTzF8ruWcLVMnnCUL9z` 已 READY，并已绑定主域名。

**M7.17 执行记录（2026-09-08）**：根据教材第 12 课「李さんは 森さんより 若いです」补全课程语法与 20 道题，覆盖「N1 は N2 より～」「N2 より N1 のほうが～」「N1 は N2 ほど～ない」、范围中的最高级、两项比较「どちら」和三项以上的最高级疑问。另修复错题练习结束条件：错题模式按错题数量结束且不再写入整课进度。题库回归检查已扩展至第 12 课；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（26/26）通过。代码提交 `43bf94be`；首次部署遇到 CLI 授权瞬态错误，重试后 Vercel production 部署 `dpl_AiWCULzaCr7CJ6Tg9ZDdhmsDZfaU` 已 READY，并已绑定主域名。

**M7.18 执行记录（2026-09-08）**：根据教材第 13 课「机の 上に 本が 3冊 あります」补全课程语法与 20 道题，覆盖量词数量、持续时间、频率、移动目的「词干 + に」、数量计价和「どのぐらい かかりますか」。题库回归检查已扩展至第 13 课；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（27/27）通过。代码提交 `0ddebef5`；Vercel production 部署 `dpl_GSSjpCG9nPoU6pSn6ce57GH8E6xs` 已 READY，并已绑定主域名。

**M7.19 执行记录（2026-09-08）**：根据教材第 14 课「昨日 デパートへ 行って、買い物しました」补全课程语法与 20 道题，覆盖て形连接动作、てから、请求「てください／てくださいませんか」、许可「てもいいですか」、禁止「てはいけません」和移动目的。题库回归检查已扩展至第 14 课；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（28/28）通过。代码提交 `c46527a5`；Vercel production 部署 `dpl_HJ3qufUCv7qBN8FPRbEnA14KudDS` 已 READY，并已绑定主域名。

**M7.20 执行记录（2026-09-08）**：根据教材第 15 课「小野さんは 今 新聞を 読んで います」补全课程语法与 20 道题，覆盖「Vています」、许可「てもいいですか」、禁止「てはいけません」、乘坐工具「に」和移动目的地「に」。题库回归检查已扩展至第 15 课；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（29/29）通过。代码提交 `208f9fc2`；Vercel production 部署 `dpl_HUfenj1pKtkshXDGwBNwy7F4XE5h` 已 READY，并已绑定主域名。

**M7.21 执行记录（2026-09-08）**：根据教材第 16 课「ホテルの 部屋は 広くて 明るいです」补全课程语法与 20 道题，覆盖形容词て形并列、名词/な形容词中顿、整体与部分「は／が」、状态「ています」和连接词。题库回归检查已扩展至第 16 课；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（30/30）通过。代码提交 `aa39fbdd`；Vercel production 部署 `dpl_9TkueogPBceUhLUsWaV3joytrjP1` 已 READY，并已绑定主域名。

**M7.22 执行记录（2026-09-08）**：根据教材第 17 课「わたしは 新しい 洋服が 欲しいです」补全课程语法与 20 道题，覆盖「N が 欲しいです」「Vたいです」、否定形式、礼貌邀请「ませんか」、疑问词与「でも／も」及委婉建议。题库回归检查已扩展至第 17 课；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（31/31）通过。代码提交 `9ad4c289`；Vercel production 部署 `dpl_4hwjyYqyqkdHrHRJf9pLfNtn4P62` 已 READY，并已绑定主域名。

**M7.23 执行记录（2026-09-08）**：补全第 18～24 课课程核心语法和每课 20 道具体题，覆盖变化表达、义务许可、动词基本形、经历列举、普通体、修饰名词、疑问嵌入、推测和引用。题库回归范围扩展至第 24 课；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（38/38）通过。代码提交 `50df8b64`；Vercel production 部署 `dpl_8Dv8eUxezLYdH3GGcWfzZ2eUgRLn` 已 READY，并已绑定主域名。

**M4.1 执行记录（2026-09-08）**：新增 `lib/review-set.ts` 和 `POST /api/create-review-set`。当已完成课程包含第 5、10、15、20 课时，按稳定课程顺序汇总旧题并去重生成混合复习集合；未达到五课节点时返回空集合。新增 2 项回归测试；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（40/40）通过。代码提交 `4b35f126`；Vercel production 部署 `dpl_AYUHhQ5Cb1Ar5STCELwSCCQP6MVj` 已 READY，并已绑定主域名。

**M4.1 页面入口执行记录（2026-09-08）**：首页接入“综合混练”入口；当完成课程列表包含第 5、10、15 或 20 课时显示按钮，启动固定 20 道稳定混合题。混练使用独立会话游标，答题写入复习记录但不修改单课 `answered_count`、`correct_count`、`lessonDone` 或解锁状态。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（40/40）通过；提交 `3b9a200c`；Vercel production 部署 `dpl_GzHX7vTXTh4EvqewqG9HYhGvbmCz` 已 READY，并已绑定主域名。

**内容抽检执行记录（2026-09-08）**：使用 Poppler 提取教材 PDF 页面并以中日 OCR 核对第 1～3 课语法页和练习页。发现第 2 课旧选择题缺少 `options` 字段且没有助词题；发现第 3 课缺少助词题。已补充第 2 课具体选项与 `の` 助词题，并补充第 3 课 `は` 助词题（稳定 ID `L03-Q021`、`L03-Q022`）。新增回归护栏，要求第 1～24 课均包含选择、助词、翻译、问答四类题型；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（41/41）通过；提交 `80a46bcd`；Vercel production 部署 `dpl_4mWxcNEwxrJaYgWSsZ9eAURUSN1Y` 已 READY，并已绑定主域名。第 1～24 课逐题人工校对仍未完成，下一轮继续核对第 4～6 课。

**第 4～6 课内容抽检执行记录（2026-09-08）**：通过 PDF OCR 核对第 4 课存在句 `あります／います`、地点 `に`、方位词 `の`，第 5 课时间 `に`、过去/否定、`から／まで`、`いつ`、大约时间 `ごろ` 和对比 `は`，第 6 课目的地 `へ`、起点 `から`、同行 `と`、交通手段 `で`、移动范围 `から～まで` 及助词对比。已补充第 5、6 课课程语法说明，并各增加 2 道针对性题（`L05-Q021`～`Q022`、`L06-Q021`～`Q022`）。本轮检查 `npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（41/41）通过；提交 `b08fb000`；Vercel production 部署 `dpl_39E3un2rSv6oS4yGwjJauXJ1nLqz` 已 READY，并已绑定主域名；第 4～6 课仍需逐题人工核对可接受答案。

**第 7～9 课内容抽检执行记录（2026-09-08）**：通过 PDF OCR 核对第 7 课动作场所 `で`、选择 `か`、请求 `Nをください`，第 8 课手段/材料 `で`、授受 `あげます／もらいます`、完成 `もう` 和并列 `も～も`，第 9 课い形容词活用、程度副词、宾语对比 `は` 和い形容词修饰名词。已补充课程语法说明，并各增加 2 道针对性题（`L07-Q021`～`Q022`、`L08-Q021`～`Q022`、`L09-Q021`～`Q022`）。本轮 `npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（41/41）通过；提交 `49821a4d`；Vercel production 部署 `dpl_Gd3fXsCzdqNGCSPomfu4SToRXAbh` 已 READY，并已绑定主域名；第 7～9 课仍需逐题人工核对可接受答案。

**第 10～12 课内容抽检执行记录（2026-09-08）**：通过 PDF OCR 核对第 10 课名词过去式、`でも／そして`，第 11 课 `や～など`、原因 `から／だから`、频率副词和 `どうしてですか`，第 12 课两项与多项比较、`最近` 和偏好 `NよりNのほうがいいです`。已补充课程语法说明，并各增加 2 道针对性题（`L10-Q021`～`Q022`、`L11-Q021`～`Q022`、`L12-Q021`～`Q022`）。本轮 `npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（41/41）通过；第 10～12 课仍需逐题人工核对可接受答案。

**第 13～15 课内容抽检执行记录（2026-09-08）**：通过 PDF OCR 核对第 13 课数量、持续时间、移动目的词干＋に、数量计价和 `どのぐらい`，第 14 课て形、てから、请求、经过/离开地点 `を`，第 15 课动作进行、许可禁止、乘坐工具 `に`、移动目的地 `に` 以及结果状态 `ています`。已补充课程语法说明，并各增加 2 道针对性题（`L13-Q021`～`Q022`、`L14-Q021`～`Q022`、`L15-Q021`～`Q022`）。本轮 `npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（41/41）通过；提交 `33982f00`；Vercel production 部署 `dpl_Ey4toomkkyE1F1YqC6kBPNRpsbxK` 已 READY，并已绑定主域名；第 13～15 课仍需逐题人工核对可接受答案。

**第 16～18 课内容抽检执行记录（2026-09-08）**：通过 PDF OCR 核对第 16 课形容词/名词并列、结果状态 `ています`、句内转折 `ですが`、`まだ～ていません`，第 17 课愿望、邀请、疑问词＋`でも／も` 和 `ぜひ`，第 18 课 `く／に なります`、`く／に します` 以及名词变化。已补充课程语法说明，并各增加 2 道针对性题（`L16-Q021`～`Q022`、`L17-Q023`～`Q024`、`L18-Q021`～`Q022`；第 17 课原有稳定 ID 已避让）。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（41/41）通过；提交 `28d6b885`；Vercel production 部署 `dpl_B4UYZ9tv8SSjvPXW7asQHiKvw46x` 已 READY，并已绑定主域名；第 16～18 课仍需逐题人工核对可接受答案。

**PWA 发布质量执行记录（2026-09-08）**：检查发现项目已有 `public/manifest.webmanifest`，但此前没有 Service Worker。新增生产环境专用 `app/pwa-register.tsx` 与 `public/sw.js`：安装时缓存首页和 manifest，导航网络失败时回退缓存首页，静态资源采用缓存优先；开发环境不注册，避免影响热更新。该离线能力仅作为渐进增强，答题提交仍需联网。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（42/42）全部通过；提交 `86752708` 并推送 GitHub；Vercel production 部署 `dpl_3vbbG8dSdksJNcDBGRpQmFAX4wWg` 已 READY，主域名 `https://japanese-syntax-coach.vercel.app` 已更新。真实设备安装与离线打开仍待验收。

**PWA 安装元数据补强（2026-09-08）**：新增品牌图标 `public/icon.svg`，并在 manifest 声明 `any maskable` 图标，修复原 manifest `icons: []` 导致部分浏览器无法提示安装的问题。本轮 TypeScript、Build、E2E（42/42）均通过；提交 `0252af8c` 并推送 GitHub；Vercel production 部署 `dpl_CskBN3cH2QkA2DSvQVVxeXCVgPq2` 已 READY，主域名已更新。待在手机浏览器确认安装提示和离线打开。

**课程语法结构回归护栏（2026-09-08）**：新增课程数据测试，要求第 1～24 课均存在具体标题、目标和至少 3 个语法点，每个语法点必须包含含义、接续、说明和例句，并拒绝遗留的「综合表达」占位项。`CI=1 npm run test:e2e -- --workers=5` 共 43 项全部通过；提交 `0c905b8d` 并推送 GitHub；Vercel production 部署 `dpl_9uxfzBCFsMSaELVkgn1PCgV6AKRn` 已 READY，主域名已更新。

**Vercel Git 自动部署连接（2026-09-08）**：通过 `npx vercel git connect https://github.com/timhaiz/japanese-syntax-coach.git --non-interactive` 将项目连接到 GitHub 仓库，命令返回 `Connected`。随后推送提交 `5bfa0e49`，Vercel 自动生成 production 部署 `dpl_FmjkQ9rEfs1nqLUfTLonqRWpKt2D`，状态 `READY`，确认自动部署链路已生效。

**生产浏览器冒烟检查（2026-09-08）**：在已登录的 Chrome 生产标签页打开主域名，页面正常渲染“句型教练／标准日本语”，显示当前课程和云端进度状态（当前标签显示第 2 课、15%）。这证明生产页面与登录态可读取；本次推送自动部署 `dpl_BTUFeH39JsZipnioq11CzTehwcXr` 已 READY。Chrome/Safari 双设备一致性和手机离线安装仍需实际设备配合确认。

**PWA 资源回归测试（2026-09-08）**：新增 `tests/e2e/pwa.spec.ts`，自动检查 manifest 的 standalone 配置、品牌图标和 Service Worker 安装/fetch 代码均可从应用提供。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（44/44）全部通过；提交 `e18bf8a9` 并推送 GitHub；Vercel production 部署 `dpl_DJZgJJYXEp7jFTuCbfTQRjfgPatz` 已 READY。真实手机安装与断网打开仍需设备验收。

**教材 PDF 抽取复核（2026-09-08）**：使用 `pdftotext` 检查用户提供的《新版中日交流标准日本語初級（上）》PDF；文件正文主要为扫描图像，文本层仅包含页面水印，无法安全地将自动抽取结果当作题库来源。系统已安装 `tesseract`（含 `chi_sim`、`jpn`），后续人工校对需按课次对扫描页 OCR 后再逐题确认，不能仅凭文本层宣布教材题目已完成。

**第 8 课授受语法补齐（2026-09-08）**：依据 OCR 复核发现课程讲解遗漏「N1 は 私に N2 を くれます」，但题库已有「小野さんは私にチョコレートをくれました」练习。已在 `lib/courses.ts` 增加「くれます」的视角、接续和易混淆说明，使课程讲解覆盖题库实际考查内容。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（44/44）全部通过；提交 `6ac47434` 并推送 GitHub；Vercel production 部署 `dpl_ApvRVwKTigno5gyr3qzVYp5zmpaA` 已 READY。

**整课续练游标修复（2026-09-08）**：修复未完成课程重新进入时总从第 1 题开始的问题。现在会根据已保存的 `lessonDone` 从下一题继续，避免重复题目和错误累计；已完成课程主动重练仍从第 1 题开始。新增 E2E 场景验证已有 3 题进度时显示 `4 / 20` 且不展示第一题。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（45/45）全部通过；提交 `9fee716b` 并推送 GitHub；Vercel production 部署 `dpl_EAEc9gCQhjK47uWQYFtjrVfMkjvo` 已 READY。

**云端正确率解锁边界修复（2026-09-08）**：修复 hydration 仅依据 `answered_count >= 20` 推导完成的问题。现在从云端进度推导解锁必须同时具备 `correct_count` 且正确率达到 90%；显式的 `completed_at/completedLessons` 记录继续作为已确认完成状态。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（45/45）全部通过；提交 `bcb25263` 并推送 GitHub；Vercel production 部署 `dpl_3F3DVb6dj8vmPNCFMWp93Gcivbxg` 已 READY。

**AI 批改请求超时保护（2026-09-08）**：为备用 `lib/ai.ts` 的 OpenAI-compatible Responses API 请求增加 8 秒超时，第三方接口无响应时及时回到规则兜底，避免 `/api/grade-answer` 长时间挂起。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（45/45）全部通过；提交 `298a0fb8` 并推送 GitHub；Vercel production 部署 `dpl_8qYQg6tUA5LPvCZVEgnCaHWvgn19` 已 READY。

**服务端判分一致性修复（2026-09-08）**：`/api/grade-answer` 现在支持 `acceptedAnswers`，并在规则层判定等价答案时跳过 AI 覆盖，确保确定性规则优先；新增 API 回归测试验证「ではありません／じゃありません」和漏标点均判定正确。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（46/46）全部通过；提交 `81eb3877` 并推送 GitHub；Vercel production 部署 `dpl_6iTfCPjrHCYzzTaF91estEZbTx5D` 已 READY。

**生产环境变量核对（2026-09-08）**：通过 `npx vercel env ls` 仅核对变量名称（未读取密钥值）。Production 已配置 `NEXT_PUBLIC_SUPABASE_URL`、`NEXT_PUBLIC_SUPABASE_ANON_KEY`、`OPENAI_API_KEY`、`OPENAI_BASE_URL`、`OPENAI_MODEL`，满足 Supabase 登录/同步和第三方 OpenAI-compatible AI 接口所需配置。

**个人中心注册信息补齐（2026-09-08）**：个人页新增真实 Supabase `auth.users.created_at` 注册日期显示；未登录时显示占位符，不伪造日期。根据每日任务已下线的产品决定，个人页不再展示无数据来源的积分。新增未登录个人页回归断言；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（46/46）全部通过；提交 `44317941` 并推送 GitHub；Vercel production 部署 `dpl_HDC8hUA93vqPZ8f3Z99zSW9hWLdU` 已 READY。

**Supabase 基线 schema 类型修正（2026-09-08）**：修正 `supabase/schema.sql` 中 `answer_attempts` 和 `review_items` 的 `exercise_id` 类型为 `text`，与稳定题目 ID（如 `L01-Q001`）及生产迁移一致，并注明生产环境应按序执行 migrations。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（46/46）全部通过；提交 `6bf6abbf` 并推送 GitHub。

**中后段教材 OCR 抽检（2026-09-08）**：对 PDF 第 180～240 页进行日中 OCR，确认扫描页中「てから」「ほうがいい」等中后段语法与课程/题库覆盖一致；本轮未发现可据此直接修复的遗漏，仍保留逐题人工校对待办。

**后段教材 OCR 抽检（2026-09-08）**：对 PDF 第 240～300 页进行日中 OCR，确认「たい／欲しい」「く／に なります」「Vたほうがいい」「Vたり」等后段语法已在课程与题库中覆盖；扫描 OCR 存在个别字符误识别，本轮未据此直接改写题目，逐题人工复核继续保留。

**手机窄屏回归护栏（2026-09-08）**：新增 PWA E2E 场景，将视口设为 390×844，验证首页 `scrollWidth` 不超过视口宽度，避免后续样式调整产生横向滚动。E2E 共 47 项全部通过。

**Service Worker 用户数据隔离（2026-09-08）**：发现原缓存策略会匹配所有同源 GET，存在缓存 `/api/study-state` 用户数据的风险。现已让 Service Worker 绕过 `/api/` 和 `/auth/` 路径，只缓存公共页面与静态资源；PWA 回归测试新增路径隔离断言。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（47/47）全部通过；提交 `60aa8732` 并推送 GitHub；Vercel production 部署 `dpl_9Aww7CsstKQ5zQP9TiFrxL48w8Bv` 已 READY。

**架构遗留回归护栏（2026-09-08）**：新增 `tests/e2e/architecture.spec.ts`，验证 `app/page.tsx` 不含硬编码题库或 `Math.random()`，题库文件存在，且已删除的 `app/api/update-daily/route.ts` 不会重新出现。修正空目录误报后，E2E 共 48 项全部通过；提交 `bfa496fc` 并推送 GitHub；Vercel production 部署 `dpl_8ENK1L6Cecqa47eSv9LZHLgMhgSc` 已 READY。

**第 19～24 课内容抽检执行记录（2026-09-08）**：继续依据教材语法页核对并补全课程说明：第 19 课 `Vないでください`、`Vなければなりません／ないといけません`、`Vなくてもいいです` 和疑问词主语的 `が`；第 20 课疑问词＋`か`、`みんなで`；第 21 课 `Vたことがあります`、`Vたり`、`Vた／Vないほうがいい`、`Vた後で`、`Vましょうか`；第 22 课普通体、`と思います`、`と言いました`、`けど`；第 23 课普通体修饰名词、疑问词＋普通体＋`か`、`かどうか`、`Vる／Vたとき`；第 24 课 `んです`、`どうやって`、`について`。在批量题库构建之后追加 12 道稳定题（`L19-Q021`～`Q022`、`L20-Q021`～`Q022`、`L21-Q021`～`Q022`、`L22-Q021`～`Q022`、`L23-Q021`～`Q022`、`L24-Q021`～`Q022`），每课仍保持选择→助词→翻译→问答顺序。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（41/41）通过；代码提交 `5d8901de`；Vercel production 部署 `dpl_2Tu9MBKB8DH43ifzYZst92T1oEz1` 已 READY，并已绑定主域名。第 1～24 课仍需人工逐题核对标准答案、可接受答案和提示，不能视为最终教材校对完成。

**题库质量回归加固（2026-09-08）**：对第 1～24 课执行静态审计，发现并修正第 3 课 3 道选择题缺少可见选项的问题；修正第 18 课重复的“把房间打扫干净”翻译题，并将重复的第 13 课课程语法项改为“何＋量词”问句、第 17 课重复的疑问词语法项改为“疑问词＋も＋否定”。回归测试新增选择题必须带 `A/B/C` 选项、答案必须对应选项及同题型题干唯一性护栏。静态审计结果无缺失选项、无重复题干；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（41/41）通过。代码提交 `35f99f50`；Vercel production 部署 `dpl_Fhe6nvsK76KMPJyFGC8vASLrm8LN` 已 READY，并已绑定主域名。第 1～24 课仍需人工逐题抽检教材答案和提示。

**第 24 课教材语法补漏（2026-09-08）**：通过教材 PDF OCR 复核第 24 课语法页，补充遗漏的副词「とうとう」（经过一段时间后终于发生），并新增选择题 `L24-Q023`。同时将「どうやって」与「について」拆分为独立课程语法点，明确其接续和与「どうして」的区别。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（41/41）通过；代码提交 `95b0fb00`；Vercel production 部署 `dpl_3rksJiHiDBrX78VJ5PLfzrExVfDY` 已 READY，并已绑定主域名。第 1～24 课仍需人工逐题抽检标准答案、可接受答案和提示。

**可接受答案判定（2026-09-08）**：为 `Question` 增加可选 `acceptedAnswers` 字段和统一 `isAnswerAccepted()` 判定函数，接入练习页面；第 1～3 课名词否定题加入教材常见的「じゃありません」表达，标点仍不影响判分。新增回归测试验证合理同义答案通过、语义相反答案拒绝。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（42/42）通过；代码提交 `f7328dce`；Vercel production 部署 `dpl_6W9xQNkrAiVYMsVqoyD7FosC5vNF` 已 READY，并已绑定主域名。第 1～24 课仍需继续人工逐题核对答案与提示。

**跨设备 hydration 门闩修复（2026-09-08）**：发现登录后 Supabase 用户元数据写回可能早于 `study-state` 持久化进度读取，存在新设备数据被旧快照覆盖的竞态。新增 `studyStateLoaded` 状态，登录/切换账号时先阻止写回，待云端学习状态请求完成（成功或失败）后再允许同步；未登录状态不受影响。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（42/42）通过；代码提交 `1e79ec30`；Vercel production 部署 `dpl_6eSXEATCHrxb3PLqQJPYcj5HN3Yn` 已 READY，并已绑定主域名。跨设备真实 Chrome/Safari 验收仍需使用真实账号执行。

**hydration 门闩部署记录（2026-09-08）**：上述同步竞态修复已部署到生产，部署 `dpl_6eSXEATCHrxb3PLqQJPYcj5HN3Yn` 状态 READY，主域名保持 `https://japanese-syntax-coach.vercel.app`。真实账号跨设备验收仍列为发布检查待办。

**错误标签精确化（2026-09-08）**：修复前端答题记录将所有错误统一保存为「句型顺序」的问题。现在助词题记录为「助词」，`ですか／ではありません` 的典型假名误写记录为「假名」，否定/进行/过去形式错误记录为「活用」，长度差异记录为「词汇」，其余才记录为「句型顺序」。规则解释仍会显示具体差异，错题练习和复习记录不受影响。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（42/42）通过；代码提交 `4a2e492e`；Vercel production 部署 `dpl_C8SmYbkRd6wdSndT8reK8QYKPSUH` 已 READY，并已绑定主域名。

**可接受答案规则扩展（2026-09-08）**：在已有显式 `acceptedAnswers` 之外，统一判定支持教材常见等价形式：「ではありません／ではありませんでした」对应「じゃありません／じゃありませんでした」，い形容词「くないです／くなかったです」对应「くありません／くありませんでした」。新增第 9 课形容词否定回归测试；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（42/42）通过；代码提交 `66627cd9`；Vercel production 部署 `dpl_5paH9tJgvaFmunTsEWAEMt6LZdUv` 已 READY，并已绑定主域名。第 1～24 课仍需人工抽检真实教材语境。

**第 23 课状态列举语法补漏（2026-09-08）**：依据教材 OCR 复核第 23 课，补充遗漏的「い形容词／な形容词／名词＋たり」状态列举句型（如「広かったり狭かったりです」），并新增选择题 `L23-Q023`。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（42/42）通过；代码提交 `b95dc0a9`；Vercel production 部署 `dpl_EkNuqW5TZK7MHyADYMXtvkfbGGvB` 已 READY，并已绑定主域名。第 1～24 课仍需人工逐题抽检标准答案、可接受答案和提示。

**生产只读健康检查（2026-09-08）**：访问生产主域名首页和登录页均返回 HTTP 200；未登录访问 `/api/study-state` 返回预期 HTTP 401；未登录提交 `/api/record-answer` 返回预期 HTTP 401；`/api/review` 使用 GET 返回 405（该接口仅提供 POST），未发现路由异常。首页响应包含“句型教练”和“标准日本语”标识。真实账号登录、跨设备数据和 Supabase 生产数据仍需用户设备验收。

**整课练习固定 20 题（2026-09-08）**：修复题库扩充后整课练习显示 22/23 题、进度门槛与产品要求不一致的问题。新增 `LESSON_QUESTION_LIMIT=20` 和核心题目切片；整课会话、课程进度百分比、完成解锁判断和课程按钮统一按 20 题计算，题库额外题保留给后续混练使用。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（42/42）通过；代码提交 `95bbe15f`；Vercel production 部署 `dpl_HAYhGMBKtNZm4Rop5maYmuzDtnK5` 已 READY，并已绑定主域名。

**AI 分析超时兜底（2026-09-08）**：为 `/api/analyze-answer` 的第三方 Responses API 请求增加 8 秒超时。接口超时、网络错误、非法 JSON 或上游错误时继续返回中文兜底说明，不阻塞答题结果；正常响应格式保持不变。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（42/42）通过；代码提交 `79fdcaa8`；Vercel production 部署 `dpl_Gq7PViXuYNAucpyC2sbqJM26aZ5y` 已 READY，并已绑定主域名。

**教材末段 OCR 抽检（2026-09-08）**：使用 Poppler/Tesseract 对 PDF 第 300～360 页进行日中 OCR，重点核对第 24 课及末段复习中的 `んです／のです`、`どうやって`、`とうとう`、`とき`、`たり` 等结构。OCR 结果与当前第 21～24 课课程说明及题库覆盖一致；扫描页存在字符误识别，未发现可据此安全修改的明确遗漏，因此本轮不改题库。第 1～24 课逐题人工核对标准答案、可接受答案和提示仍未完成，继续列为内容质量待办。

**填空题边界审计（2026-09-08）**：自动检查发现第 20 课 `趣味は写真を撮ることです` 和第 21 课 `荷物を持ちましょうか` 的空格位置会造成句尾重复。已分别修正为填入 `こと`、`ましょ` 的正确空格边界，并新增回归断言。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（49/49）通过；第 1～24 课整体仍需人工逐题校对。

**填空题完整句审计（2026-09-08）**：逐条将助词题空格替换为标准答案，发现并修正第 9 课 `おいしいい`、第 21 课 `持ちましょか`、第 22/24 课 `でしょうでしょう` 四处拼接错误；新增完整句重建回归测试。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（50/50）通过；人工逐题教材校对仍未完成。

**题库重复句尾回归护栏（2026-09-08）**：将所有课程助词题的答案自动回填到题干，新增检查以阻止 `ですです`、`でしょうでしょう`、`おいしいい` 等明显拼接错误重新进入题库。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（51/51）通过；人工逐题教材校对仍未完成。

**选择题答案映射审计（2026-09-08）**：逐课输出并核对全部选择题的“标准选项字母 → 日文选项内容”，确认每道题的答案字母均指向对应正确选项，未发现新的映射错误；该检查已由既有题库回归测试持续覆盖。人工教材语境校对仍需继续。

**生产发布健康检查（2026-09-08）**：Git 推送后 Vercel 自动生成最新 Production 部署并返回 `Ready`（最新预览域名 `japanese-syntax-coach-j6hznpd0l-timhai06.vercel.app`）。通过 Node fetch 检查主域名：`/`、`/login`、`/manifest.webmanifest`、`/sw.js` 返回 200；未登录访问 `/api/study-state` 返回 401，未登录访问仅 POST 的 `/api/record-answer` 返回 405，符合路由保护预期。真实账号登录、Chrome/Safari 跨设备同步和手机离线安装仍需设备验收。

**PWA 旧资源缓存修复（2026-09-08）**：生产浏览器冒烟发现旧客户端仍显示缺少选项的交互；确认最新部署 JavaScript 已包含题库选项后，将 Service Worker 缓存版本从 `v1` 提升为 `v2`，使已安装客户端在激活时删除旧壳资源。重新执行 TypeScript、Build、E2E（51/51）通过；Vercel Production 部署 `dpl_7onS5cJr8b7FpbWiSFG8NruaiQe3` 已 READY 并绑定主域名。仍需用户在真实设备确认 SW 激活后的选择题显示。

**生产选择题端到端验收（2026-09-08）**：使用全新无缓存 Playwright 浏览器访问生产主域名，预置第 1 课完成状态后进入第 2 课，点击整课练习；第一题实际渲染 3 个选项（A/B/C），文本输入框数量为 0，确认缓存版本升级后生产题型交互正确。

**AI 生产接口验收（2026-09-08）**：使用无个人信息的示例句调用生产 `/api/analyze-answer`，返回 HTTP 200，响应包含 `analysis`、`words`、`pitfalls`，且 `source` 为 `ai`（不是 fallback），确认 Production 的第三方 OpenAI-compatible 配置和 Responses 请求链路已生效；未读取或暴露密钥。

**选择题答案记录修复（2026-09-08）**：修复选择题提交时仅把 `A/B/C` 字母写入作答记录和 AI 分析的问题；现在统一使用对应的日文选项文本，规则判分、Supabase `answer_attempts` 和 AI 记忆分析看到的是同一份实际答案。新增架构回归断言；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（51/51）通过。Vercel Production 部署 `dpl_4a7z7PvFLvyaCuj8oJxijjXsLWPk` 已 READY，并已绑定主域名。

**选择题反馈精确化（2026-09-08）**：修复选择题错误反馈拿字母与日文句子比较、参考答案只显示 `A/B/C` 的问题。现在规则批改显示用户实际选择的日文句子和正确选项完整内容，错题提示更具体；新增架构回归断言。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（51/51）通过。Vercel Production 部署 `dpl_2N9qDNpQTukPSJGnenTY94fZcWEU` 已 READY，并已绑定主域名。

**题型指令文案修复（2026-09-08）**：练习页不再对所有题型统一显示“把下面的中文说成日语”。翻译题显示中文翻译指令，选择题显示选择日文句子，助词题显示选择助词，问答题显示回答提示；避免题型与操作方式不一致。新增架构回归断言；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（51/51）通过。Vercel Production 部署 `dpl_Du58jvfZSMjZYac8WqxjHPQwmojf` 已 READY，并已绑定主域名。

**错题本参考答案显示修复（2026-09-08）**：错题本列表现在与练习页一样，将选择题的字母答案解析为完整日文选项，避免用户只看到 `A/B/C` 而无法复习。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（51/51）通过。Vercel Production 部署 `dpl_65X8kSaRZwSqAwroYMrPXMJGmh2T` 已 READY，并已绑定主域名。

**题干重复审计护栏（2026-09-08）**：对第 1～24 课题干执行去标点、去空格后的跨题型重复检查，未发现同课重复题；新增 E2E 回归测试覆盖该规则。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（52/52）通过。

**题型选项数量护栏（2026-09-08）**：全量确认选择题和助词题均提供恰好 3 个 A/B/C 可见选项，并将该要求固化到题库回归测试；`npx tsc --noEmit`、`CI=1 npm run test:e2e -- --workers=5`（52/52）通过。

**固定 20 题顺序复核（2026-09-08）**：尝试为第 1～3 课增加更多选择/助词题时，回归验证发现新增题会挤出既有问答题并改变已保存的整课续练游标；已撤回该批扩充，保留当前稳定题序。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（52/52）通过，后续如需扩充应先设计不改变核心 20 题 ID/顺序的题库版本策略。

**生产反馈路径验收（2026-09-08）**：使用全新 Playwright 浏览器访问 Production，进入第 2 课第一题，确认题型指令显示“选择正确的日语句子”、A/B/C 三个选项正常渲染；选择错误项提交后，反馈同时显示完整的用户选句和正确日文句，并保留提示及 AI 分析按钮。

**已完成课程重练隔离（2026-09-08）**：修复重练已完成课程时旧 `lessonCorrect` 被继续累加、导致正确率虚高或错误改变解锁状态的问题。新增 `replayMode`：已完成课程重练只更新本次练习游标，不再修改整课完成统计；新增架构回归断言。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（52/52）通过。Vercel Production 部署 `dpl_DPvMUXsQERQ2ttbxMRA5BidgSqrY` 已 READY，并已绑定主域名。

**重练统计 E2E 验收（2026-09-08）**：新增高层测试：预置第 1 课 20/20 和已完成状态，重练第一题并答错，确认本地整课进度仍为 20，不会因重练污染原统计。全量 E2E 共 53/53 通过；Vercel Production 部署 `dpl_9qwbNq4oKuC1GMG1RxGeReYWrmCd` 已 READY，并已绑定主域名。

**AI 响应结构校验（2026-09-08）**：为 `/api/analyze-answer` 和 `lib/ai.ts` 增加运行时字段校验；非法 JSON、缺失字段或错误 verdict 不再标记为 AI 成功，而是回到明确兜底。新增架构回归测试；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（54/54）通过。Vercel Production 部署 `dpl_8SsKjS5Kpi5hT9gNLchXp9bVrcbU` 已 READY，并已绑定主域名。

**整课题量固定护栏（2026-09-08）**：新增回归测试，逐课确认 `questionsForLesson(...).slice(0,20)` 恰好包含 20 题，防止题库扩充或排序变化导致整课入口少题/超题。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（55/55）通过。

**课程语法关联审计（2026-09-08）**：对第 1～24 课语法点与题库提示/答案执行自动关联扫描，并人工复核扫描出的候选项。由于课程模式使用 `N/V/A` 等抽象符号，纯字符串匹配会产生误报；本轮未发现可安全据此修改的明确缺口，因此保持题库不变，继续以 OCR 和人工语境校对为最终依据。

**全局题目 ID 护栏（2026-09-08）**：新增回归测试，将 24 课全部题目合并后检查稳定 ID 全局唯一，确保错题本、云端 `answer_attempts` 和综合混练不会发生跨课串题。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（56/56）通过。

**AI 分析超时处理优化（2026-09-08）**：生产回归发现第三方 Responses 接口在冷启动时超过原 8 秒限制，导致可用接口被误判为 fallback。将 `/api/analyze-answer` 请求超时提高到 20 秒，并将超时与网络错误分开返回明确提示；本地 `npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（56/56）通过。生产重新部署后仍需再次验证 `source: "ai"`。

**部署限制记录（2026-09-08）**：提交 `a1945927` 已推送至 GitHub；手动 `vercel --prod --yes` 被 Vercel 免费额度 `api-deployments-free-per-day` 拒绝（当日部署次数超过 100），因此当前生产别名仍指向上一版本 `dpl_8SsKjS5Kpi5hT9gNLchXp9bVrcbU`。待额度恢复或升级后需重新部署并复测 AI 分析超时修复。

**AI 分析本地回归（2026-09-08）**：使用 Production 的 `OPENAI_BASE_URL`、模型和密钥注入本地 Next.js，调用 `/api/analyze-answer` 返回 200、`source: "ai"`，耗时约 9.7 秒，确认 20 秒超时足以覆盖当前第三方响应；密钥未写入仓库或日志。

**AI 非法 JSON 降级提示（2026-09-08）**：将 AI 正文解析失败从网络错误中独立出来，返回 `reason: "invalid-json"` 和可操作提示；规则批改仍不受影响。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（56/56）通过。生产部署受当日 Vercel 免费额度限制，尚未更新线上版本。

**AI 默认模型统一（2026-09-09）**：将 `/api/analyze-answer` 未设置 `OPENAI_MODEL` 时的默认值统一为 `gpt-5.4-mini`，与 `lib/ai.ts` 及产品约定一致。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（56/56）通过；待部署后验证生产环境变量实际模型。

**生产模型变量修正（2026-09-09）**：发现 Vercel Production 原变量为 `gpt-5.5`，已通过 Vercel CLI 删除并重新添加 `OPENAI_MODEL=gpt-5.4-mini`（按 Secret 保存，值未输出）。代码部署仍受 Vercel 免费部署额度限制，待下次发布后验证线上接口。

**题库答案格式审计（2026-09-09）**：对第 1～24 课全部题目执行静态格式检查：翻译题答案均含日文字符，助词题答案无异常长文本，未发现中文误作标准答案；现有 56 条 E2E 继续通过。再次尝试 Production 部署仍返回 `api-deployments-free-per-day`，线上验收保持待办。

**Production 自动部署与 AI 验收（2026-09-09）**：GitHub 自动部署已生成并切换主域名到提交 `0e8d2d31` 对应的 READY 部署 `dpl_A7Q4FAtiKCMePmSSD1CNxoPdySd7`（`japanese-syntax-coach-r72e9582m-timhai06.vercel.app`）。调用主域名 `/api/analyze-answer` 返回 HTTP 200、`source: "ai"`，确认线上 AI 分析链路已恢复；此前 CLI 部署额度限制不再阻塞该版本上线。

**Production 资源冒烟（2026-09-09）**：通过无状态 HTTP 检查主域名 `/`、`/login`、`/manifest.webmanifest`、`/sw.js` 均返回 200；未登录访问 `/api/study-state` 返回 401，空请求 `/api/record-answer` 返回 400（参数校验生效）。真实 Chrome/Safari 登录和手机安装验收因当前 Mac 锁定，待用户解锁设备后继续。

**计划状态整理（2026-09-09）**：依据现有实现与 56/56 E2E，将 M3 的规则判分、统一结果、错题闭环、独立 AI 分析及 M5 的首页/个人页状态展示标记为已完成；人工教材逐题校对和真实设备验收仍明确保留为未完成。

**Production 复测（2026-09-09）**：再次调用主域名 `/api/analyze-answer` 返回 200 且 `source: "ai"`；未登录 `/api/study-state` 返回 401，确认认证保护仍生效。浏览器自动化仍因 Mac 锁定无法进行，真实设备验收不变。

**Supabase 迁移结构复核（2026-09-09）**：复核 M4 学习记录迁移与整课正确率迁移：`lesson_progress.correct_count`、20 题完成门槛、复习间隔数组（0/1/3/7/14/30 天）、RLS 策略及 `record_learning_attempt` RPC 参数保持一致，未发现迁移顺序或约束冲突。真实账号数据读写仍需浏览器验收。

**Production AI 波动复测（2026-09-09）**：主域名 AI 分析连续复测 2 次返回 HTTP 200、`source: "ai"`（约 8.7 秒、5.2 秒）；此前单次 20 秒超时属于第三方瞬时波动，超时兜底仍按设计保留。

**设备验收阻塞审计（2026-09-09）**：连续多轮尝试通过 CUA 接管 Chrome/Safari，Mac 均处于锁定状态且无法自动解锁。生产 HTTP、代码检查和题库审计已完成；真实账号跨设备与手机安装验收必须由用户解锁设备后执行，本项目在该外部条件满足前保持未完成。

**手机 PWA 用户验收（2026-09-09）**：用户已在真实手机上完成 PWA 安装、打开和离线使用测试，并确认正常。该结果作为设备验收证据记录；本机 CUA 未连接手机，因此未重复操作或伪造截图。

**Chrome 生产会话检查（2026-09-09）**：设备已恢复可操作；现有 Chrome 生产标签页显示账号 `TIMHAI06` 已登录，首页能够读取当前课程与整体掌握度（当前课程第 24 课）。本轮仅确认登录会话和页面加载，未改写用户学习数据；Safari 同步及手机 PWA 安装仍未验证。

**设备清单复核（2026-09-09）**：当前 CUA 可接管的浏览器仅有 Chrome，系统未暴露 Safari 实例或手机设备；因此无法在本轮伪造 Safari/手机验收。Playwright 的窄屏与 PWA 资源测试已通过，但不替代真实安装测试，相关计划项继续保持未完成。

**最终本地回归（2026-09-09）**：在当前工作树重新运行 `npm run build` 与 `CI=1 npm run test:e2e -- --workers=5`，Build 成功，E2E 56/56 通过。Chrome 生产会话可用；Safari 与手机设备仍不可用，未将其结果误标为通过。

**最新提交自动部署（2026-09-09）**：GitHub 推送后的 Vercel Production 部署已生成并处于 READY，提交 `a7a9deff` 对应部署 `japanese-syntax-coach-qnybi6xig-timhai06.vercel.app`；确认文档更新已进入自动发布链路。真实 Safari/手机验收仍待设备提供。

**Safari Production 会话检查（2026-09-09）**：用户已打开 Safari，已通过系统脚本访问 Production 首页并确认页面资源正常；Safari 当前为未登录状态（显示“学习者”、第 1 课 0%），与 Chrome 中已登录的 `TIMHAI06` 会话不同。未复制或读取 Chrome 密码/会话，跨设备同步需用户在 Safari 手动登录同一邮箱后继续验证。

**Chrome/Safari 同账号同步验收（2026-09-09）**：用户在 Safari 登录同一账号后，Chrome 与 Safari 均显示 `TIMHAI06`、当前第 24 课、本课进度 0%、整体掌握 5%，课程标题和底部错题本入口一致。确认 Supabase 云端状态已跨浏览器恢复；手机 PWA 安装与离线验收仍未完成。

**当前课程跳转修复（2026-09-09）**：发现旧云端元数据可能残留第 24 课等未来课程完成标记，首页直接使用孤立标记计算 `nextLessonIndex`，会错误显示第 24 课。新增连续完成前缀归一化：只有从第 1 课开始连续完成的课程才能解锁后续课程；孤立未来标记不再影响当前课程、锁定状态或综合混练。新增 E2E 回归“未来课程陈旧标记不会跳到第 24 课”；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（57/57）通过。待自动部署后复测 Production。

**当前课程跳转 Production 部署（2026-09-09）**：提交 `d4dd2ff9` 已由 GitHub 自动触发 Vercel Production 部署 `japanese-syntax-coach-gh0une5bk-timhai06.vercel.app`，状态 READY。线上真实账号页面需刷新并重新完成云端 hydration 后验证；本地回归已覆盖陈旧未来课程标记场景。

**当前课程真实账号修复（2026-09-09）**：进一步确认旧 `completedLessons` 列表即使没有对应 `lessonDone/correct` 证据也会被信任，导致已登录用户显示第 24 课。现在完成标记必须同时满足实际答题数不少于 20 且正确率至少 90%，再按连续课程前缀解锁；新增云端脏标记回归测试。`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（58/58）通过，待自动部署后请刷新 Chrome/Safari 验证。

**当前课程修复部署完成（2026-09-09）**：提交 `180935e1` 已自动部署到 Vercel Production，部署 `japanese-syntax-coach-o01enjx1o-timhai06.vercel.app` 状态 READY。请用户刷新已登录浏览器并等待同步完成后确认当前课程显示第 1 课。

**当前课程计算二次修复（2026-09-09）**：真实 Safari 刷新仍显示第 24 课，确认还存在陈旧的 100% `lessonDone` 进度，而首页曾把“进度 < 100%”作为当前课程判断。现改为仅根据已验证完成课程列表选择当前课，且该列表要求 20 题＋90% 正确率证据。新增“陈旧 100% 进度但没有正确率证明”回归测试；`npx tsc --noEmit`、`npm run build`、`CI=1 npm run test:e2e -- --workers=5`（59/59）通过。待自动部署后重验。

**Service Worker 缓存升级（2026-09-09）**：为确保已打开的 Safari/Chrome 客户端不会继续使用旧壳资源，将 PWA 缓存从 `syntax-coach-shell-v2` 升级至 `v3` 并加回归断言。`npx tsc --noEmit`、`npm run build`、E2E 59/59 通过；待部署激活后重新加载真实会话验证当前课程。

**当前课程真实 Safari 验收（2026-09-09）**：通过带刷新查询参数的新导航打开 Production 后，Safari 同账号页面已显示第 1 课、按钮“开始第 1 课”、课程卡“自我介绍与判断句”，不再跳到第 24 课。第 1 课历史答题进度仍显示 100%，但未验证完成标记不再决定当前课程或解锁后续课程。当前课程问题已在真实会话中验证修复。

## 6. 测试护栏

每个里程碑开始前必须确认工作区干净；完成后必须运行：

```bash
npx tsc --noEmit
npm run build
npm run test:e2e       # M0 建立后启用
```

如果 `package.json` 没有对应脚本，不得假装测试通过；应先补脚本或在报告中明确标记“未执行”。

核心高层级测试场景：

1. 注册验证码确认或密码登录后显示正确邮箱。
2. 第 1 课完成整课 20 题且正确率达到 90% 后才解锁第 2 课；只打开课程页不能算完成。
3. 正确、漏标点、助词错误、假名错误分别得到预期结果。
4. 错题进入错题本，并可独立练习；答对后状态更新。
5. 首页“去完成/去复习”进入正确练习模式，练习达到上限后结束。
6. Chrome 与 Safari 使用同一账号时，课程进度和错题一致。
7. AI 超时、非法 JSON 或额度不足时，规则结果仍可正常使用。

## 7. Git 协作策略

- 一个功能一个小提交，提交前必须通过该阶段验收。
- 推荐提交格式：`feat: ...`、`fix: ...`、`test: ...`、`docs: ...`。
- 不提交 `.env*`、`.next/`、`node_modules/`、本地 OIDC token 和测试账号密钥。
- 发现方向错误时，先停止继续修改，使用 Git 回到最近一次通过检查的提交，再重新实现。
- 任何回滚或重置都必须确认目标 commit；不得对未确认的用户改动执行破坏性操作。
- 发布记录至少包含：commit、Vercel deployment、检查命令和结果。

## 8. 当前执行顺序

1. [x] 首页真实状态和入口文案整理。
2. [x] 跨设备解锁兼容和云端 hydration 保护。
3. [x] 建立第 1 课 E2E 回归测试。
4. [x] 将复习项目和每日任务迁移到 Supabase 表。
5. [x] 收敛题库规范化、题型交互和整课进度模型，修复剩余 E2E。
6. [ ] 对第 1～24 课进行人工逐题抽检（AI 辅助结构审计、题量扩充和 OCR 抽检已完成）。
7. [x] 按 PDF 结构扩充第 4～24 课核心语法与题库；人工逐题校对仍是后续内容质量任务。
8. [x] 生产发布检查和跨设备验收。

每完成一项，更新本文件的复选框、补充验收证据、Git commit 与部署状态，并提交 Git；未完成项不得标记为已完成。教材内容工作还必须记录已校对的课次和剩余课次。

### 已完成设备验收（2026-09-09）

1. Chrome 与 Safari 使用同一账号登录后，已确认同一云端课程状态；并在 Safari 真实会话中确认当前课程修复为第 1 课。
2. 用户已自行完成手机 PWA 安装和离线打开验收，并确认正常。
3. 因此生产发布检查和跨设备验收已标记完成；第 1～24 课人工逐题教材校对仍需按课次另行确认，不能用自动测试替代。

### M7.24 练习交互与解锁判定（2026-09-09）

- [x] 翻译题和问答题统一改为候选词块点击排序；选择题、助词题保留选项按钮。
- [x] 词块实例使用题目 ID + 序号生成稳定 ID，并按题目 ID 确定性排序，避免重复词块 key 冲突和刷新顺序变化。
- [x] 词块答案拼接后复用既有规则判分、错题记录、AI 分析和标点提示。
- [x] 课程详情显示已作答数、正确数和解锁所需的 20 题 / 90% 条件，区分“进度 100%”与“课程已解锁”。
- [ ] 仍需在真实登录会话中补做词块排序、漏标点和问答题回归验收，并发布到 Vercel。

**M7.24 验收记录（2026-09-09）**：`npx tsc --noEmit`、`npm run build`、题库/架构 E2E（43/43）和词块相关练习 E2E（3/3）通过；提交 `0349bad7`、`b886be61` 已推送 GitHub，Vercel 自动部署链路返回 200。课程详情已实测显示第一课 43 次作答、32 次正确（历史数据未达到 18/20 门槛），因此第二课保持锁定，原因可见且不再被“进度 100%”误导。

**M7.25 词块分词边界修复（2026-09-09）**：将多字符助词「から／まで」作为独立词块优先识别，避免被拆成「か／ら」或「ま／で」；架构回归增加分词边界护栏。`npx tsc --noEmit`、`npm run build`、题库 E2E（42/42）、架构 E2E（2/2）和 `git diff --check` 通过；提交 `ce3cf0ce`、`bffda618` 已推送 GitHub。

**M7.26 第 9 课教材抽检（2026-09-09）**：使用 Poppler/Tesseract 核对教材第 9 课语法页和练习页，确认「ちょうどいいです」与句尾「よ」为本课实际表达。已补充课程讲解、选择题和问答题（`L09-Q023`～`L09-Q024`），并增加回归测试；上述 42/42 题库测试、TypeScript 和 Build 全部通过。教材逐题可接受答案人工复核仍列为后续待办。

**M7.27 第 11 课教材抽检（2026-09-09）**：使用 Poppler/Tesseract 核对教材第 11 课语法页，确认「N は N が できます」是本课能力表达，区别于第 20 课的「Vることができます」。已补充课程讲解及 `L11-Q023`～`L11-Q024` 题目；TypeScript 与 42/42 题库回归测试通过。逐题可接受答案人工复核仍列为后续待办。

**M7.28 第 12 课教材抽检（2026-09-09）**：使用教材 OCR 核对「やっぱり」和句尾「が…」的表达及使用语境，确认当前课程原有比较句型之外缺少这两项词语讲解。已补充课程说明和 `L12-Q023`～`L12-Q024` 题目；TypeScript、Build、题库回归测试 43/43 全部通过。

**M7.29 第 13 课教材抽检（2026-09-09）**：使用教材 OCR 核对数量词、持续时间、期间次数、移动目的「词干 + に」、数量计价「で」和「どのぐらいかかりますか」。当前课程说明与题库已覆盖教材六项语法及「何 + 量词」提问，未发现可安全修改的遗漏；本轮保持代码不变，逐题可接受答案人工复核继续列为待办。

**M7.30 第 14 课教材抽检（2026-09-09）**：使用教材 OCR 核对 `て形` 连接、`てから`、`てくださいませんか`、移动经过点 `を`，以及表达及词语中的「それから」「なかなか」「そうして ください」「すみませんが」。已补充课程说明和 `L14-Q023`～`L14-Q026`；TypeScript、Build、题库回归测试 44/44 通过。

**M7.31 第 15 课教材抽检（2026-09-09）**：使用教材 OCR 核对 `Vています` 的进行与结果状态、`てもいいですか`、`てはいけません`、交通工具 `に乗ります`、`まだVていません`。当前课程说明与题库已覆盖本课语法，未发现需要安全修改的遗漏；本轮保持代码不变。

**M7.32 第 16 课教材抽检（2026-09-09）**：使用教材 OCR 核对形容词/名词中顿（`い形容词くて`、`な形容词／名词で`）、整体与部分的 `NはNが形容词`、`Vています` 的结果状态，以及连接词「そして」「でも」和表达「持っています／住んでいます」。当前 `lib/courses.ts` 已完整说明上述句型，`lib/question-bank.ts` 已提供 20 道基础题并补充 `L16-Q021`～`L16-Q022`，覆盖选择、助词、翻译、问答四类；未发现需要安全修改的遗漏，本轮保持代码不变。

**M7.33 第 17 课教材抽检（2026-09-09）**：使用教材 OCR 核对 `Nが欲しいです`、`NをVたいです`、`Vませんか／Vましょう`、疑问词＋`でも／も`、`時間＋中に`、`ぜひ` 及句尾「ね」。现有题库已覆盖前述核心结构；新增 `L17-Q025`（`いつでも` 泛指时间）和 `L17-Q026`（愿望句的「ね」与「そうですね」应答），课程说明同步补充两项，保持题型覆盖选择、助词、翻译、问答。

**M7.34 第 18 课教材抽检（2026-09-09）**：使用教材 OCR 核对 `い形容词くなります`、`Nをい形容词くします`、`な形容词／名词になります`，并检查表达及词语中的「まとめて」「NはNが似合います」「もうすぐ／すぐ」。新增 `L18-Q023`～`L18-Q025`，课程说明同步补充三项，覆盖集中处理、相称表达和时间副词；题库仍满足每课至少 20 题及四类题型。

**M7.35 第 19 课教材抽检（2026-09-09）**：使用教材 OCR 核对各类动词 `ない形`、`ないでください`、`なければなりません／ないといけません`、`なくてもいいです` 和疑问词主语 `が`，并检查表达及词语中的「やっと」「だいぶ」。新增 `L19-Q023`～`L19-Q024`，课程说明同步补充两个副词考点。

**M7.36 第 20 课教材抽检（2026-09-09）**：使用教材 OCR 核对 `V基本形ことができます`、`NはVことです`、`Vる前に`、疑问词＋`か`、`みんなで`，并检查会话中的「ごちそうします」「もちろんです」「いつか」。新增 `L20-Q023`～`L20-Q026`，课程说明同步补充请客、将来不确定时间和肯定应答表达。
