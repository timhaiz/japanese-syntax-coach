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
    <section><h2>2. 账号注销</h2><p>你可以随时自行注销账号，不需要联系客服：</p><ul className="legal-list"><li>网页：在「我的」页面选择「注销账号」。</li><li>iOS 应用：在「账户」页选择「删除账号」，并在确认弹窗中确认。</li></ul><p>注销后，账号及其关联的云端学习数据、会员状态与账号数据会被永久删除，且无法恢复。在 iOS 应用中注销时，本机的离线答案、缓存进度与待同步购买记录也会一并清除。订阅的退订与退款由 Apple 处理，见下一节。</p></section>
    <section><h2>3. 订阅与购买</h2><ul className="legal-list"><li>iOS 应用的订阅通过 Apple App Store 完成，价格与周期以 App Store 展示为准。</li><li>恢复购买：在应用内「账户 → 订阅与购买」中点「恢复购买」。</li><li>购买记录同步：购买完成后，应用会把签名交易交给服务器确认。服务器确认之前，购买记录会保留在本机并自动重试，不会丢失。</li><li>会员状态以服务器确认的结果为准。</li></ul><p>取消订阅请参考 <a href="https://support.apple.com/zh-cn/118428" target="_blank" rel="noreferrer">Apple 官方说明</a>，申请退款请参考 <a href="https://www.apple.com/cn/shop/goto/help/sales_refunds" target="_blank" rel="noreferrer">Apple 销售与退款说明</a>。</p></section>
    <section><h2>4. 常见问题</h2><ul className="legal-list"><li><b>收不到验证码或重置密码邮件</b>：先检查垃圾邮件并确认邮箱拼写；仍未收到请发邮件给我们。</li><li><b>学习进度没有同步</b>：请确认登录的是同一个账号。断网时的答题会暂存在本机，联网后会自动重放。</li><li><b>会员状态没有更新</b>：先在「账户 → 订阅与购买」点一次「恢复购买」，仍未生效请联系我们。</li><li><b>答题判分和网站不一致</b>：网站端的判分规则是唯一权威来源，如有差异请把题目编号发给我们。</li></ul></section>
    <section><h2>5. 隐私与条款</h2><p>我们如何处理你的信息，请阅读<Link href="/privacy">隐私政策</Link>；使用规则请阅读<Link href="/terms">用户协议</Link>。</p></section>
    <p className="legal-links"><Link href="/privacy">隐私政策</Link> · <Link href="/terms">用户协议</Link> · <Link href="/login">登录 / 注册</Link></p>
  </main>
}
