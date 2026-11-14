import type { Metadata } from 'next'
import Link from 'next/link'

export const metadata: Metadata = {
  title: '支持与帮助｜句型教练',
  description: '句型教练的支持渠道、账号注销方式与常见问题',
}

const SUPPORT_EMAIL = 'service@niixmiro.com'

export default function SupportPage() {
  return <main className="legal-page">
    <Link href="/" className="legal-back">‹ 返回首页</Link>
    <p className="eyebrow">SUPPORT</p>
    <h1>支持与帮助</h1>
    <p className="legal-updated">最后更新：2026 年 10 月 31 日</p>
    <section><h2>1. 联系我们</h2><p>遇到问题、想反馈建议，或需要查询、更正、删除你的个人信息，都可以发邮件给我们。</p><div className="legal-contact"><a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a><span>点击直接发邮件</span></div><p className="legal-gap">请在邮件中写明你的账号邮箱、使用的是网页还是 iOS 应用，以及具体问题。我们通常会在 2 个工作日内回复。请不要在邮件中发送密码或验证码。</p></section>
    <section><h2>2. 账号注销</h2><p>你可以在 iOS 应用的「账户 → 删除账号」或网页端的个人中心发起账号注销，也可以发送邮件至 {SUPPORT_EMAIL} 申请删除账号及关联数据。删除账号不会自动取消 Apple 订阅，订阅的退订与退款由 Apple 处理，见下一节。</p></section>
    <section><h2>3. 订阅与购买</h2><ul className="legal-list"><li>iOS 应用的订阅通过 Apple App Store 完成，提供月度订阅（$0.99/月）与年度订阅（$6.59/年），价格与当地币种折算以 App Store 展示为准。</li><li>你可以在「账户 → 订阅与购买」中发起订阅、点击「恢复购买」或在 Apple 账户设置中管理订阅。</li><li>购买记录同步：购买完成后，应用会把签名交易交给服务器确认。应用会尝试保留待确认购买；同步受阻时，请保留当前设备并联系支持。</li><li>会员状态以服务器确认的结果为准。</li></ul><p>取消订阅请参考 <a href="https://support.apple.com/zh-cn/118428" target="_blank" rel="noreferrer">Apple 官方说明</a>，申请退款请参考 <a href="https://www.apple.com/cn/shop/goto/help/sales_refunds" target="_blank" rel="noreferrer">Apple 销售与退款说明</a>。</p></section>
    <section><h2>4. 常见问题</h2><ul className="legal-list"><li><b>收不到验证码或重置密码邮件</b>：先检查垃圾邮件并确认邮箱拼写；仍未收到请发邮件给我们。</li><li><b>学习进度没有同步</b>：请确认登录的是同一个账号。断网时的答题会暂存在本机，联网后会自动重放。</li><li><b>会员状态没有更新</b>：先在「账户 → 订阅与购买」点一次「恢复购买」或「刷新会员状态」；若仍未更新，请保留当前设备并联系我们。</li><li><b>答题判分和网站不一致</b>：网站端的判分规则是唯一权威来源，如有差异请把题目编号发给我们。</li></ul></section>
    <section><h2>5. 隐私与条款</h2><p>我们如何处理你的信息，请阅读<Link href="/privacy">隐私政策</Link>；使用规则请阅读<Link href="/terms">用户协议</Link>。</p></section>
    <p className="legal-links"><Link href="/privacy">隐私政策</Link> · <Link href="/terms">用户协议</Link> · <Link href="/login">登录 / 注册</Link></p>
  </main>
}
