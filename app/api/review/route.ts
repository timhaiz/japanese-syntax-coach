import {NextResponse} from 'next/server'
import {nextReviewByVerdict,ReviewVerdict} from '@/lib/review'
export async function POST(req:Request){const b=await req.json().catch(()=>({}));if(!b.userId)return NextResponse.json({error:'userId required'},{status:400});const verdict:ReviewVerdict=['correct','mostly_correct','needs_fix','incorrect'].includes(b.verdict)?b.verdict:(b.correct?'correct':'incorrect');const review=nextReviewByVerdict(Number(b.reps||0),verdict);return NextResponse.json({userId:b.userId,lessonId:b.lessonId,exerciseId:b.exerciseId,verdict,...review})}
