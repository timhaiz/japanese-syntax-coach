# 句型教练

手机优先的《标准日本语》句型训练 PWA 原型。

## 本地运行

```bash
npm install
npm run dev
```

打开 http://localhost:3000。

当前已包含首页、课程地图、第 1 课句型卡、中文→日语练习、即时规则批改、错写提示、浏览器朗读和 PWA manifest。`/api/grade-answer` 是后续接入 Supabase 登录/同步与 AI Provider Adapter 的服务端入口。

课程内容应使用自有或获授权的整理内容，不直接复制教材受版权保护的完整文本、插图或音频。
