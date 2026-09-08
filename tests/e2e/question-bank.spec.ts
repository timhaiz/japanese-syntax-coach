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
          expect(question.options!.length).toBeGreaterThanOrEqual(2)
          expect(question.options!.every(option=>/^[A-Z]：/.test(option))).toBeTruthy()
          expect(question.options!.some(option=>option.startsWith(`${question.answer}：`))).toBeTruthy()
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
})
