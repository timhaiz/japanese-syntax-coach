import {NextResponse} from 'next/server'
import {createMixedReviewSet} from '@/lib/review-set'

export async function POST(req:Request){
  const body=await req.json().catch(()=>({})) as {completedLessonIndexes?:unknown;limit?:unknown}
  if(!Array.isArray(body.completedLessonIndexes))return NextResponse.json({error:'completedLessonIndexes required'},{status:400})
  const indexes=body.completedLessonIndexes.filter((value):value is number=>Number.isInteger(value))
  const limit=typeof body.limit==='number'&&Number.isInteger(body.limit)?body.limit:20
  return NextResponse.json({questions:createMixedReviewSet(indexes,limit)})
}
