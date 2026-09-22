# TypeSafe Jev 快速开始指南

## 🎯 5 分钟快速开始

### 步骤 1: 获取 API Key（2 分钟）

1. 访问 https://typesafe.ai
2. 注册账号
3. 复制 API Key

### 步骤 2: 配置环境变量（1 分钟）

编辑 `.env.local` 文件：

```bash
# 添加这一行
TYPESAFE_API_KEY=your_api_key_here
```

### 步骤 3: 启动测试（2 分钟）

```bash
# 启动开发服务器
npm run dev

# 在另一个终端测试
curl -X POST http://localhost:3000/api/grade-answer \
  -H "Content-Type: application/json" \
  -d '{
    "answer": "これは私の本です",
    "standardAnswer": "これは私の本です。",
    "hint": "测试"
  }'
```

**期望结果**: 看到 `"source": "typesafe"` 表示成功！

## 🔍 验证清单

- [ ] API Key 配置正确
- [ ] 开发服务器运行正常
- [ ] 测试返回 `source: "typesafe"`
- [ ] 响应时间 < 500ms
- [ ] 判分结果合理

## 📊 观察指标

在浏览器开发者工具的 Network 标签中：

- **URL**: `/api/grade-answer`
- **Method**: POST
- **Time**: 应该在 100-300ms
- **Response**: 包含 `source: "typesafe"`

## 🎉 成功标志

当你看到这样的响应时，说明集成成功：

```json
{
  "verdict": "correct",
  "correctedAnswer": "これは私の本です。",
  "errorTags": [],
  "explanation": "句型结构正确，继续保持主动输出。",
  "confidence": 0.95,
  "qualityScore": 100,
  "source": "typesafe"
}
```

## ❓ 常见问题

**Q: 没有看到 `source: "typesafe"`？**

A: 检查：
1. `.env.local` 中的 API Key 是否正确
2. 重启开发服务器
3. 答案是否完全匹配（完全匹配会用 `source: "rule"`）

**Q: 响应时间还是很慢？**

A: 检查：
1. 网络连接
2. 是否真的进入 TypeSafe 路径（查看 `source` 字段）
3. TypeSafe API 是否正常

**Q: 判分结果不准确？**

A: 可以调整 `lib/typesafe-grading.ts` 中的评分标准。

## 🚀 下一步

集成成功后：

1. 在实际使用中观察判分效果
2. 收集用户反馈
3. 根据需要调整评分规则
4. 考虑关闭 OpenAI 降级以节省成本

## 📚 更多资源

- 详细报告: `TYPESAFE_IMPLEMENTATION_REPORT.md`
- 项目分析: `project_typesafe_analysis.md`
- TypeSafe 文档: https://docs.typesafe.ai
