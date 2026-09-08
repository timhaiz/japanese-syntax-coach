import {test,expect} from '@playwright/test'
import {questionsForLesson} from '../../lib/question-bank'

test.describe('第 1～24 课题库回归检查',()=>{
  for(const lessonId of [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24]){
    test(`第 ${lessonId} 课题目字段完整且 ID 稳定`,()=>{
      const questions=questionsForLesson(lessonId)
      expect(questions.length).toBeGreaterThanOrEqual(20)
      expect(new Set(questions.map(question=>question.id)).size).toBe(questions.length)
      for(const question of questions){
        expect(question.id).toMatch(new RegExp(`^L${String(lessonId).padStart(2,'0')}-Q\\d{3}$`))
        expect(question.lessonId).toBe(lessonId)
        expect(question.prompt.length).toBeGreaterThan(0)
        expect(question.answer.length).toBeGreaterThan(0)
        expect(question.hint.length).toBeGreaterThan(0)
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
})
