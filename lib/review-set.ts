import {questionsForLesson, type Question} from '@/lib/question-bank'

/**
 * Builds a deterministic mixed review set after each five completed lessons.
 * The caller passes zero-based lesson indexes, matching the client progress model.
 */
export function createMixedReviewSet(
  completedLessonIndexes:number[],
  limit=20,
  getQuestions: (lessonId:number)=>Question[]=questionsForLesson,
  lessonCount=24,
  checkpointInterval=5,
):Question[]{
  const eligible=[...new Set(completedLessonIndexes.filter(index=>Number.isInteger(index)&&index>=0&&index<lessonCount))]
    .filter(index=>checkpointInterval > 0 && (index+1)%checkpointInterval===0)
    .sort((a,b)=>a-b)
  if(!eligible.length)return []
  const pool=eligible.flatMap(index=>getQuestions(index+1))
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

export function prioritizeReviewSet(questions:Question[], mastery:Record<string,number>={}, dueIds:string[]=[]):Question[]{
 const due=new Set(dueIds)
 return [...questions].sort((a,b)=>{
  const dueScore=(due.has(b.id)?100:0)-(due.has(a.id)?100:0)
  if(dueScore)return dueScore
  const score=(q:Question)=>{const hits=Object.entries(mastery).filter(([tag])=>q.hint.includes(tag)||q.prompt.includes(tag));return hits.length?Math.min(...hits.map(([,value])=>value)):50}
  const aScore=score(a); const bScore=score(b)
  return aScore-bScore
 })
}
