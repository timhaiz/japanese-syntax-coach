import {test,expect} from '@playwright/test'
import {createMixedReviewSet,prioritizeReviewSet} from '../../lib/review-set'
import {nextReviewByVerdict} from '../../lib/review'

test('不同判定结果使用不同复习间隔',()=>{
 const now=new Date('2026-09-13T00:00:00Z')
 expect(nextReviewByVerdict(0,'correct',now).intervalDays).toBe(1)
 expect(nextReviewByVerdict(0,'mostly_correct',now).intervalDays).toBe(0)
 expect(nextReviewByVerdict(1,'mostly_correct',now).intervalDays).toBe(1)
 expect(nextReviewByVerdict(1,'needs_fix',now).intervalDays).toBe(0)
 expect(nextReviewByVerdict(1,'incorrect',now).intervalDays).toBe(0)
})

test('第 5、10、15、20 课完成后生成稳定混合复习集合',()=>{
  const set=createMixedReviewSet([0,1,2,3,4,9,14,19],20)
  expect(set).toHaveLength(20)
  expect(new Set(set.map(question=>question.id)).size).toBe(20)
  expect(set.every(question=>[5,10,15,20].includes(question.lessonId))).toBeTruthy()
  expect(set.map(question=>question.id)).toEqual(createMixedReviewSet([19,14,9,4,0,0],20).map(question=>question.id))
})

test('未完成五课时不生成混合复习集合',()=>{
  expect(createMixedReviewSet([0,1,2,3])).toEqual([])
})

test('到期题优先，其次按掌握度排序',()=>{
 const questions=createMixedReviewSet([4],4)
 const sorted=prioritizeReviewSet(questions,{助词:20,活用:80},[questions[2].id])
 expect(sorted[0].id).toBe(questions[2].id)
})
