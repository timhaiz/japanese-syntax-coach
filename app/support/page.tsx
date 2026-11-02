import type { Metadata } from 'next'
import Link from 'next/link'

export const metadata: Metadata = {
  title: '支持与帮助｜句型教练',
  description: '句型教练的支持联系方式及相关政策',
}

const SUPPORT_EMAIL = 'service@niixmiro.com'

export default function SupportPage() {
  return <main className="legal-page">
    <Link href="/" className="legal-back">‹ 返回首页</Link>
    <p className="eyebrow">SUPPORT</p>
    <h1>支持与帮助</h1>
    <section>
      <h2>联系我们</h2>
      <p>如需帮助或反馈建议，请通过以下邮箱联系我们。</p>
      <div className="legal-contact">
        <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>
      </div>
    </section>
    <section>
      <h2>隐私与条款</h2>
      <p>请参阅<Link href="/privacy">隐私政策</Link>与<Link href="/terms">用户协议</Link>。</p>
    </section>
    <p className="legal-links"><Link href="/privacy">隐私政策</Link> · <Link href="/terms">用户协议</Link></p>
  </main>
}
