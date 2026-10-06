import type { Metadata } from 'next'
import './subscription.css'
import './ios.css'
import { AppleSubscriptionControls } from '@/components/AppleSubscriptionControls'

export const metadata: Metadata = {
  title: '会员订阅 | 句型教练',
  description: '句型教练会员订阅、自动续期、取消和恢复购买说明。',
}

const plans = [
  {
    period: 'MONTHLY',
    name: '月度会员',
    price: '¥18',
    cadence: '每月自动续期',
    note: 'AI 判分 · 深度分析 · VOICEVOX 语音',
  },
  {
    period: 'YEARLY',
    name: '年度会员',
    price: '¥180',
    cadence: '每年自动续期',
    note: '相当于每月 15 元，自动续期',
  },
]

export default function SubscriptionPage() {
  return (
    <main className="subscription-page">
      <header className="subscription-header">
        <a className="subscription-logo" href="/" aria-label="句型教练首页">句型教练</a>
        <nav aria-label="主要导航">
          <a href="/">学习</a>
          <a href="/textbooks">教材</a>
          <a href="/privacy">隐私政策</a>
          <a href="/terms">用户协议</a>
        </nav>
      </header>

      <section className="subscription-hero" aria-labelledby="subscription-title">
        <p className="subscription-kicker">JAPANESE SYNTAX COACH</p>
        <h1 id="subscription-title">会员订阅<br />使用说明</h1>
        <p>会员可使用 AI 判分、AI 深度分析和 VOICEVOX 教材语音生成。订阅由 Apple 处理，取消和退款遵循 App Store 规则。</p>
      </section>

      <AppleSubscriptionControls />

      <section className="subscription-card subscription-plan-card" aria-labelledby="plan-heading">
        <div className="subscription-section-heading">
          <span>01</span>
          <div>
            <p>PLAN</p>
            <h2 id="plan-heading">会员方案</h2>
          </div>
        </div>
        <div className="subscription-plans">
          {plans.map((plan) => (
            <article className="subscription-plan" key={plan.period}>
              <p>{plan.period}</p>
              <h3>{plan.name}</h3>
              <strong>{plan.price}</strong>
              <span>{plan.cadence}</span>
              <small>{plan.note}</small>
            </article>
          ))}
        </div>
      </section>

      <section className="subscription-card" aria-labelledby="payment-heading">
        <div className="subscription-section-heading">
          <span>02</span>
          <div>
            <p>RECURRING PAYMENT</p>
            <h2 id="payment-heading">自动续期</h2>
          </div>
        </div>
        <div className="subscription-timeline">
          <div className="subscription-timeline-item">
            <b>购买当天</b>
            <p>购买完成后，会员功能会在服务端验证交易并开通。</p>
          </div>
          <div className="subscription-timeline-item">
            <b>续期日期</b>
            <p>月度方案每月续期，年度方案每年续期，具体日期由 Apple 账户决定。</p>
          </div>
          <div className="subscription-timeline-item">
            <b>续期前</b>
            <p>如需停止续费，请在 Apple 账户的订阅设置中提前取消。</p>
          </div>
        </div>
        <aside className="subscription-notice"><b>付款方式</b><p>付款、续费、退款和税费由 Apple 处理，应用不会保存你的银行卡信息。</p></aside>
      </section>

      <section className="subscription-card" aria-labelledby="cancel-heading">
        <div className="subscription-section-heading">
          <span>03</span>
          <div>
            <p>CANCEL OR END</p>
            <h2 id="cancel-heading">取消与到期</h2>
          </div>
        </div>
        <div className="subscription-cancel-grid">
          <div>
            <h3>取消方法</h3>
            <ol>
              <li><span>1</span><p>打开 iPhone 的“设置”，点击 Apple 账户。</p></li>
              <li><span>2</span><p>进入“订阅”，选择“句型教练”。</p></li>
              <li><span>3</span><p>点击“取消订阅”，按 Apple 页面提示完成操作。</p></li>
            </ol>
          </div>
          <div className="subscription-deadline">
            <p>IMPORTANT</p>
            <h3>取消后仍可使用<br />已付款的剩余周期。</h3>
            <span>删除 App 不会自动取消订阅。</span>
          </div>
        </div>
      </section>

      <section className="subscription-card subscription-terms" aria-labelledby="terms-heading">
        <div className="subscription-section-heading">
          <span>04</span>
          <div>
            <p>TERMS</p>
            <h2 id="terms-heading">订阅规则</h2>
          </div>
        </div>
        <ul>
          <li>会员权益持续到当前 Apple 账单周期结束。</li>
          <li>取消后不会再产生下一周期的自动扣款。</li>
          <li>退款由 Apple 按 App Store 规则处理。</li>
          <li>恢复购买会重新验证 Apple 交易，并将会员状态同步到当前账号。</li>
          <li>自定义教材及其语音只对上传者账号可见。</li>
        </ul>
      </section>

      <section className="subscription-help">
        <p>NEED HELP?</p>
        <h2>需要帮助？</h2>
        <a href="/">返回学习页面 <span>→</span></a>
      </section>

      <footer className="subscription-footer">© 句型教练</footer>
    </main>
  )
}
