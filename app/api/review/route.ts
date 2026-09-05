import {NextResponse} from 'next/server'
import {nextReview} from '@/lib/review'
export async function POST(req:Request){const b=await req.json().catch(()=>({}));if(!b.userId)return NextResponse.json({error:'userId required'},{status:400});const review=nextReview(Number(b.reps||0),Boolean(b.correct));return NextResponse.json({userId:b.userId,lessonId:b.lessonId,exerciseId:b.exerciseId,...review})}
