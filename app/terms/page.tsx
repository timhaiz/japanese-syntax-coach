import type { Metadata } from 'next'
import Link from 'next/link'

export const metadata: Metadata = {
  title: '用户协议｜句型教练',
  description: '句型教练用户协议',
}

export default function TermsPage() {
  return <main className="legal-page">
    <Link href="/" className="legal-back">‹ 返回首页</Link>
    <p className="eyebrow">TERMS OF USE</p>
    <h1>用户协议</h1>
    <p className="legal-updated">最后更新：2026 年 10 月 5 日</p>
    <section><h2>1. 服务内容</h2><p>句型教练提供日语句型学习、练习、错题复习、学习记录同步和部分会员功能。服务内容可能因版本、设备、地区或订阅状态而调整。</p></section>
    <section><h2>2. 账号责任</h2><p>你应妥善保管登录凭据，不得转让、出租或共享账号。发现异常登录时，请及时联系我们。</p></section>
    <section><h2>3. 用户上传内容</h2><p>你只能上传拥有合法使用权的教材或学习资料。你应确保上传内容不侵犯他人版权、商标、隐私或其他权利。我们可以删除违法、侵权或影响服务安全的内容。</p></section>
    <section><h2>4. 会员与数字服务</h2><p>会员可使用 AI 判分、AI 深度分析和自定义教材的 VOICEVOX 语音生成。当前提供月度会员 18 元、年度会员 180 元，最终扣款金额以 Apple App Store 购买页面显示为准。若通过 Apple App Store 订阅，付款、续期、退款和取消规则以 Apple 的条款及 App Store 页面为准。删除应用不会自动取消订阅。</p></section>
    <section><h2>5. 合理使用</h2><p>不得滥用接口、批量制造无意义任务、绕过会员限制、攻击服务或尝试访问其他用户的数据。违反本条时，我们可以暂停或终止账号。</p></section>
    <section><h2>6. 免责声明</h2><p>学习内容用于辅助练习，不构成考试、升学、翻译或专业判断保证。因网络、设备、第三方服务或不可抗力造成的中断，我们会在合理范围内恢复服务。</p></section>
    <section><h2>7. 协议变更与终止</h2><p>我们会在协议发生重大变化时更新页面。你可以随时注销账号；注销后，账号及关联数据将按隐私政策处理。</p></section>
    <p className="legal-links"><Link href="/privacy">查看隐私政策</Link> · <Link href="/login">登录 / 注册</Link></p>
  </main>
}
