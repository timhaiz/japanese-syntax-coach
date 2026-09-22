import type { Metadata } from 'next'
import './subscription.css'

export const metadata: Metadata = {
  title: 'Fitness+ サブスクリプションについて | NIIX',
  description: 'Fitness+ サブスクリプションの定期支払い、解約、終了条件についてご案内します。',
}

const plans = [
  {
    period: 'Monthly',
    name: '月額プラン',
    price: '¥3,900',
    cadence: '毎月',
    note: '税込・1か月ごとの自動更新',
  },
  {
    period: 'Yearly',
    name: '年額プラン',
    price: '¥40,900',
    cadence: '毎年',
    note: '税込・1年ごとの自動更新',
  },
]

export default function SubscriptionPage() {
  return (
    <main className="subscription-page">
      <header className="subscription-header">
        <a className="subscription-logo" href="https://niix.jp/" aria-label="NIIX ホーム">NIIX</a>
        <nav aria-label="メインナビゲーション">
          <a href="https://niix.jp/lanno/">LANNOデジタルミラー</a>
          <a href="https://niix.jp/shop/">STORE</a>
          <a href="https://niix.jp/account-jp-2">アカウント</a>
          <a href="https://niix.jp/sk/#popup-menu-anchor">LANNO登録</a>
          <a href="https://niix.jp/linkdirect/">LINK</a>
        </nav>
      </header>

      <section className="subscription-hero" aria-labelledby="subscription-title">
        <p className="subscription-kicker">Fitness + Subscription</p>
        <h1 id="subscription-title">サブスクリプション<br />ご利用ガイド</h1>
        <p>定期支払いのタイミングと、解約・終了に関する大切なご案内です。</p>
      </section>

      <section className="subscription-card subscription-plan-card" aria-labelledby="plan-heading">
        <div className="subscription-section-heading">
          <span>01</span>
          <div>
            <p>PLAN</p>
            <h2 id="plan-heading">ご利用プラン</h2>
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
            <h2 id="payment-heading">定期支払いについて</h2>
          </div>
        </div>
        <div className="subscription-timeline">
          <div className="subscription-timeline-item">
            <b>お申し込み日</b>
            <p>初回の利用料金をお支払いいただき、すぐにFitness+をご利用いただけます。</p>
          </div>
          <div className="subscription-timeline-item">
            <b>更新日</b>
            <p>お申し込み日と同じ日付に、選択したプランの料金が自動で請求されます。月額は毎月、年額は毎年更新です。</p>
          </div>
          <div className="subscription-timeline-item">
            <b>更新日前</b>
            <p>解約手続きが完了していない場合、次回の利用期間分が自動的に更新・請求されます。</p>
          </div>
        </div>
        <aside className="subscription-notice"><b>お支払い方法</b><p>お申し込み時に登録したお支払い方法へ、定期的に自動請求されます。支払い方法の変更はアカウントページから行えます。</p></aside>
      </section>

      <section className="subscription-card" aria-labelledby="cancel-heading">
        <div className="subscription-section-heading">
          <span>03</span>
          <div>
            <p>CANCEL OR END</p>
            <h2 id="cancel-heading">解約・終了について</h2>
          </div>
        </div>
        <div className="subscription-cancel-grid">
          <div>
            <h3>解約方法</h3>
            <ol>
              <li><span>1</span><p><a href="https://niix.jp/account-jp-2">アカウント</a>にログインします。</p></li>
              <li><span>2</span><p>「サブスクリプション」から対象のFitness+プランを選択します。</p></li>
              <li><span>3</span><p>「解約する」を選び、画面の案内に従って手続きを完了します。</p></li>
            </ol>
          </div>
          <div className="subscription-deadline">
            <p>IMPORTANT</p>
            <h3>次回更新日の前日までに<br />お手続きください。</h3>
            <span>期限を過ぎた場合、次回分の定期支払いが発生します。</span>
          </div>
        </div>
      </section>

      <section className="subscription-card subscription-terms" aria-labelledby="terms-heading">
        <div className="subscription-section-heading">
          <span>04</span>
          <div>
            <p>TERMS</p>
            <h2 id="terms-heading">解約・終了の条件</h2>
          </div>
        </div>
        <ul>
          <li>解約後も、すでにお支払い済みの利用期間の終了日まではFitness+をご利用いただけます。</li>
          <li>解約手続き後は、次回以降の自動更新および定期支払いは行われません。</li>
          <li>利用期間の途中で解約した場合でも、日割りでの返金はありません。</li>
          <li>お支払いが完了しない場合、Fitness+の利用を停止することがあります。お支払い方法をご確認のうえ、アカウントページから更新してください。</li>
          <li>サービス内容・料金・提供条件を変更または終了する場合は、事前にお知らせします。</li>
        </ul>
      </section>

      <section className="subscription-help">
        <p>NEED HELP?</p>
        <h2>ご不明な点がありますか？</h2>
        <a href="https://niix.jp/account-jp-2">アカウントページを開く <span>→</span></a>
      </section>

      <footer className="subscription-footer">© NIIX. Fitness+ subscription guide.</footer>
    </main>
  )
}
