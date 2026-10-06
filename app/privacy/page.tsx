import type { Metadata } from 'next'
import Link from 'next/link'

export const metadata: Metadata = {
  title: '隐私政策｜句型教练',
  description: '句型教练隐私政策',
}

export default function PrivacyPage() {
  return <main className="legal-page">
    <Link href="/" className="legal-back">‹ 返回首页</Link>
    <p className="eyebrow">PRIVACY POLICY</p>
    <h1>隐私政策</h1>
    <p className="legal-updated">最后更新：2026 年 10 月 5 日</p>
    <section><h2>1. 我们收集的信息</h2><p>注册时，我们会处理邮箱地址和 Supabase 账号标识。使用学习功能时，会保存课程进度、答题记录、错题和复习安排。使用自定义教材语音功能时，会处理你主动上传的教材内容及其生成的音频。</p></section>
    <section><h2>2. 使用目的</h2><p>这些信息用于登录认证、同步学习进度、提供错题复习、生成教材语音、处理会员订阅和维护服务安全。我们不会出售个人信息，也不会将用户上传的教材用于公开展示。</p></section>
    <section><h2>3. 第三方服务</h2><p>本服务可能使用 Supabase 提供认证和数据库服务，使用 VOICEVOX Engine 生成日语语音，并在启用相关功能时使用 AI 服务处理答题分析。各服务只接收完成对应功能所需的信息。</p></section>
    <section><h2>4. 保存与安全</h2><p>用户上传的教材和语音按账号隔离保存。我们会采取访问控制、服务端鉴权和传输加密等措施，但任何互联网服务都无法保证绝对安全。</p></section>
    <section><h2>5. 你的权利</h2><p>你可以访问、修改或删除账号信息，也可以在“我的”页面申请注销账号。注销后，账号及其关联的云端学习数据会被删除；法律要求保留的信息除外。</p></section>
    <section><h2>6. 儿童使用</h2><p>本服务面向能够独立同意相关条款的用户。未成年人应在监护人同意和陪同下使用。</p></section>
    <section><h2>7. 联系我们</h2><p>如需查询、更正或删除个人信息，请通过应用内账号支持渠道联系我们。</p></section>
    <p className="legal-links"><Link href="/terms">查看用户协议</Link> · <Link href="/login">登录 / 注册</Link></p>
  </main>
}
