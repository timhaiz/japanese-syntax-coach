import {test,expect} from '@playwright/test'
import {isAnswerAccepted,questionsForLesson} from '../../lib/question-bank'
import {courses} from '../../lib/courses'

test.describe('第 1～24 课题库回归检查',()=>{
  for(const lessonId of [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24]){
    test(`第 ${lessonId} 课题目字段完整且 ID 稳定`,()=>{
      const questions=questionsForLesson(lessonId)
      expect(questions.length).toBeGreaterThanOrEqual(20)
      expect(new Set(questions.map(question=>question.id)).size).toBe(questions.length)
      expect(new Set(questions.map(question=>`${question.type}:${question.prompt}`)).size).toBe(questions.length)
      for(const question of questions){
        expect(question.id).toMatch(new RegExp(`^L${String(lessonId).padStart(2,'0')}-Q\\d{3}$`))
        expect(question.lessonId).toBe(lessonId)
        expect(question.prompt.length).toBeGreaterThan(0)
        expect(question.answer.length).toBeGreaterThan(0)
        expect(question.hint.length).toBeGreaterThan(0)
        if(question.type==='选择'){
          expect(question.options,'选择题必须提供可见选项').toBeDefined()
          expect(question.options!.length).toBe(3)
          expect(question.options!.every(option=>/^[A-Z]：/.test(option))).toBeTruthy()
          expect(question.options!.some(option=>option.startsWith(`${question.answer}：`))).toBeTruthy()
        }
        if(question.type==='助词'){
          expect(question.options,'助词题必须提供 A/B/C 选项').toBeDefined()
          expect(question.options!.length).toBe(3)
        }
        if(question.options){
          expect(question.options.length).toBeGreaterThanOrEqual(2)
          const answerInOptions=question.options.some(option=>option.startsWith(`${question.answer}：`)||option.endsWith(`：${question.answer}`))
          expect(answerInOptions).toBeTruthy()
        }
      }
    })
  }

  test('题型顺序为选择、助词、翻译、问答',()=>{
    const order={选择:0,助词:1,翻译:2,问答:3} as const
    for(const lessonId of [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24]){
      const values=questionsForLesson(lessonId).map(question=>order[question.type])
      expect(values).toEqual([...values].sort((a,b)=>a-b))
    }
  })

  test('每课都包含选择、助词、翻译和问答四类练习',()=>{
    for(const lessonId of [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24]){
      const types=new Set(questionsForLesson(lessonId).map(question=>question.type))
      expect([...types]).toEqual(expect.arrayContaining(['选择','助词','翻译','问答']))
    }
  })

  test('整课核心练习每课固定 20 题',()=>{
    for(const lessonId of Array.from({length:24},(_,index)=>index+1)){
      expect(questionsForLesson(lessonId).slice(0,20)).toHaveLength(20)
    }
  })

  test('24 课题目 ID 在全局范围内唯一',()=>{
    const all=Array.from({length:24},(_,index)=>questionsForLesson(index+1)).flat()
    expect(new Set(all.map(question=>question.id)).size).toBe(all.length)
  })

  test('每课课程页都有具体语法说明，不保留占位语法',()=>{
    expect(courses).toHaveLength(24)
    for(const lesson of courses){
      expect(lesson.title.length).toBeGreaterThan(0)
      expect(lesson.goal.length).toBeGreaterThan(0)
      expect(lesson.grammar.length).toBeGreaterThanOrEqual(3)
      for(const grammar of lesson.grammar){
        expect(grammar.pattern).not.toBe('综合表达')
        expect(grammar.meaning.length).toBeGreaterThan(0)
        expect(grammar.connection.length).toBeGreaterThan(0)
        expect(grammar.explanation.length).toBeGreaterThan(0)
        expect(grammar.example.length).toBeGreaterThan(0)
      }
    }
  })

  test('教材常见的じゃありません表达可作为可接受答案',()=>{
    const question=questionsForLesson(1).find(item=>item.id==='L01-Q002')!
    expect(isAnswerAccepted(question,'私は先生じゃありません。')).toBeTruthy()
    expect(isAnswerAccepted(question,'私は先生です。')).toBeFalsy()
    const adjective=questionsForLesson(9).find(item=>item.id==='L09-Q006')!
    expect(isAnswerAccepted(adjective,'このりんごは甘くありません。')).toBeTruthy()
  })

  test('第 1 课题目只覆盖教材的判断、应答和名词所属',()=>{
    const questions=questionsForLesson(1)
    expect(questions.find(item=>item.id==='L01-Q003')?.prompt).toBe('李さんはJC企画___社員です。')
    expect(questions.find(item=>item.id==='L01-Q007')?.prompt).toBe('北京旅行社は中国___企業です。')
    expect(questions.find(item=>item.id==='L01-Q016')?.answer).toBe('はい、小野です。')
    expect(questions.find(item=>item.id==='L01-Q017')?.answer).toBe('分かりません。')
    expect(questions.some(item=>/これ|それ|あれ|何ですか/.test(item.prompt))).toBeFalsy()
  })

  test('第 2 课核心 20 题覆盖教材的指示、疑问和选择表达',()=>{
    const core=questionsForLesson(2).slice(0,20)
    expect(core.find(item=>item.id==='L02-Q014')?.answer).toBe('あの人はだれですか。')
    expect(core.find(item=>item.id==='L02-Q019')?.answer).toBe('森さんのかばんはどれですか。')
    expect(core.find(item=>item.id==='L02-Q020')?.answer).toBe('小野さんの机はどの机ですか。')
  })

  test('第 3 课核心 20 题覆盖也、选择疑问和价格问句',()=>{
    const core=questionsForLesson(3).slice(0,20)
    expect(core.find(item=>item.id==='L03-Q005')?.answer).toBe('あそこもJC企画のビルです。')
    expect(core.find(item=>item.id==='L03-Q017')?.answer).toBe('かばん売り場は1階ですか、2階ですか。')
    expect(core.find(item=>item.id==='L03-Q020')?.answer).toBe('その車はいくらですか。')
  })

  test('第 4 课核心 20 题覆盖确认句和疑问词全面否定',()=>{
    const core=questionsForLesson(4).slice(0,20)
    expect(core.find(item=>item.id==='L04-Q018')?.answer).toBe('あそこに犬がいますね。')
    expect(core.find(item=>item.id==='L04-Q019')?.answer).toBe('教室にだれもいません。')
    expect(core.find(item=>item.id==='L04-Q020')?.answer).toBe('何もありません。')
  })

  test('第 5 课核心 20 题覆盖ごろ和时间对比',()=>{
    const core=questionsForLesson(5).slice(0,20)
    expect(core.find(item=>item.id==='L05-Q010')?.answer).toBe('私は昨日12時半ごろ寝ました。')
    expect(core.find(item=>item.id==='L05-Q018')?.answer).toContain('小野さんは今日は休みます。')
  })

  test('第 7 课核心 20 题覆盖宾语、场所、选择和请求',()=>{
    const core=questionsForLesson(7).slice(0,20)
    expect(core.some(item=>item.answer==='この本をください。')).toBeTruthy()
    expect(core.some(item=>item.answer==='パンかお粥を食べます。')).toBeTruthy()
    expect(core.some(item=>item.answer==='一緒に勉強しましょう。')).toBeTruthy()
  })

  test('第 8 课核心 20 题覆盖授受、会面以及もう／よ',()=>{
    const core=questionsForLesson(8).slice(0,20)
    expect(core.some(item=>item.answer==='私はもう昼ご飯を食べました。')).toBeTruthy()
    expect(core.some(item=>item.answer==='もう帰りましたよ。')).toBeTruthy()
    expect(core.some(item=>item.answer==='小野さんは私にチョコレートをくれました。')).toBeTruthy()
  })

  test('第 9 课覆盖ちょうどいい和句尾よ',()=>{
    const questions=questionsForLesson(9)
    expect(questions.some(item=>item.options?.some(option=>option.includes('この浴衣はちょうどいいです。')))).toBeTruthy()
    expect(questions.some(item=>item.answer==='はい、とてもおいしいですよ。')).toBeTruthy()
    expect(courses.find(item=>item.id===9)?.grammar.map(item=>item.pattern)).toEqual(expect.arrayContaining(['ちょうど いいです。','句尾 よ']))
  })

  test('填空题空格边界不会重复题干中的句尾',()=>{
    const nominalized=questionsForLesson(20).find(item=>item.id==='L20-Q007')!
    expect(nominalized.prompt).toBe('趣味は写真を撮る___です。')
    expect(nominalized.answer).toBe('こと')
    const offer=questionsForLesson(21).find(item=>item.id==='L21-Q022')!
    expect(offer.prompt).toBe('荷物を持ち___か。')
    expect(offer.answer).toBe('ましょう')
  })

  test('填空题替换后形成完整日文句子',()=>{
    const checks:[number,string,string,string][]=[
      [9,'L09-Q022','これはおいし___料理です。','これはおいしい料理です。'],
      [21,'L21-Q022','荷物を持ち___か。','荷物を持ちましょうか。'],
      [22,'L22-Q007','明日は晴れる___。','明日は晴れるでしょう。'],
      [24,'L24-Q007','明日は晴れる___。','明日は晴れるでしょう。']
    ]
    for(const [lesson,id,prompt,expected] of checks){
      const question=questionsForLesson(lesson).find(item=>item.id===id)!
      expect(question.prompt).toBe(prompt)
      expect(question.prompt.replace('___',question.answer)).toBe(expected)
    }
  })

  test('所有助词题替换答案后不产生明显重复句尾',()=>{
    for(const lessonId of Array.from({length:24},(_,index)=>index+1)){
      for(const question of questionsForLesson(lessonId).filter(item=>item.type==='助词')){
        const sentence=question.prompt.replace('___',question.answer)
        expect(sentence).not.toMatch(/ですです|ますます|でしょうでしょう|ましたました|ませんません|おいしいい|ましょか/)
      }
    }
  })

  test('每课题干去标点后仍保持跨题型唯一',()=>{
    for(const lessonId of Array.from({length:24},(_,index)=>index+1)){
      const seen=new Set<string>()
      for(const question of questionsForLesson(lessonId)){
        const normalized=question.prompt.replace(/[“”"。！？!?，,、：:（）()\s]/g,'')
        expect(seen.has(normalized),`${question.id} 与同课题目重复`).toBeFalsy()
        seen.add(normalized)
      }
    }
  })
})
