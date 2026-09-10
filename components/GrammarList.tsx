'use client'

type Grammar = {
  pattern: string
  meaning: string
  connection: string
  explanation: string
  example: string
  responses?: string[]
  pitfalls?: string[]
}

export function GrammarList({ grammar }: { grammar: Grammar[] }) {
  return <div className="grammar-list">{grammar.map((g, i) => <div className="grammar" key={i}><span>0{i + 1}</span><div><b>{g.pattern}</b><p>{g.meaning}</p><small>接续：{g.connection}</small><small>说明：{g.explanation}</small><small>例句：{g.example}</small>{g.responses?.map(response => <small className="grammar-extra" key={response}>应答：{response}</small>)}{g.pitfalls?.map(pitfall => <small className="grammar-extra" key={pitfall}>易错：{pitfall}</small>)}</div><button type="button" aria-label={`朗读句型 ${g.pattern}`} title="朗读例句" onClick={() => speechSynthesis?.speak(new SpeechSynthesisUtterance(g.example))}>🔊</button></div>)}</div>
}
