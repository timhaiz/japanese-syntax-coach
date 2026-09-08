import {questionsForLesson, type Question} from '@/lib/question-bank'

/**
 * Builds a deterministic mixed review set after each five completed lessons.
 * The caller passes zero-based lesson indexes, matching the client progress model.
 */
export function createMixedReviewSet(completedLessonIndexes:number[],limit=20):Question[]{
  const eligible=[...new Set(completedLessonIndexes.filter(index=>Number.isInteger(index)&&index>=0&&index<24))]
    .filter(index=>(index+1)%5===0)
    .sort((a,b)=>a-b)
  if(!eligible.length)return []
  const pool=eligible.flatMap(index=>questionsForLesson(index+1))
  if(!pool.length)return []
  const output:Question[]=[]
  const seen=new Set<string>()
  let cursor=0
  while(output.length<Math.max(1,Math.min(limit,pool.length))){
    const question=pool[cursor%pool.length]
    cursor+=1
    if(seen.has(question.id))continue
    seen.add(question.id)
    output.push(question)
  }
  return output
}
