# TODO List

## P0：生产验收（需人工验证）
- [ ] 用真实账号验证登录、刷新、退出、账号切换
- [ ] 验证 Chrome/Safari/手机端进度隔离
- [ ] 验证 AI 降级场景（额度不足、401/429、非法 JSON、超时）
- [ ] 确认 Supabase 生产迁移已全部执行

## P1：内容质量（需人工核对）
- [ ] 逐题核对第 1～24 课标准答案
- [ ] 核对可接受答案
- [ ] 核对候选词切分和提示
- [ ] 补充真实用户回归用例

## P2：代码与体验
- [x] 抽离 AnswerOptions 组件
- [x] 抽离 PracticeFeedback 组件
- [x] 修复 E2E 旧断言
- [x] 统一设计 token
- [x] 完善加载态与错误态
- [x] 补充汉字假名显示
- [x] 代码重构优化 - 第一阶段
  - [x] 创建 storage-utils.ts 统一 localStorage 管理
  - [x] 创建 useAuthSync.ts 管理认证和同步
  - [x] 创建 useStudyState.ts 管理云端学习状态
  - [x] 创建 useLocalStorageSync.ts 管理本地存储同步
  - [x] 创建 grading-utils.ts 统一判分逻辑
  - [x] 创建 types.ts 统一类型定义
  - [x] 修复类型导入问题
  - [x] 构建验证通过
- [x] 代码重构优化 - 第二阶段（进行中）
  - [x] 创建 useLocalProgressLoader.ts 加载本地进度
  - [x] 创建 useGrading.ts 统一答题判分逻辑
  - [ ] 应用新 hooks 到 app/page.tsx（待实施）
  - [ ] 简化状态管理（减少 useState 数量）
  - [ ] 测试重构后的功能

## 当前正在执行
- 代码质量分析和重构
