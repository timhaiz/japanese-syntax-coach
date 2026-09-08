import {test,expect} from '@playwright/test'
import {createMixedReviewSet} from '../../lib/review-set'

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
