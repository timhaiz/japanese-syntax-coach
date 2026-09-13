export const REVIEW_INTERVALS=[0,1,3,7,14,30]
export type ReviewVerdict='correct'|'mostly_correct'|'needs_fix'|'incorrect'
export const VERDICT_INTERVALS:Record<ReviewVerdict,number[]>={
 correct:REVIEW_INTERVALS,
 mostly_correct:[0,1,2,4,7,14],
 needs_fix:[0,0,1,3,7,14],
 incorrect:[0,0,1,3,7,14],
}
export function nextReviewByVerdict(reps:number,verdict:ReviewVerdict,now=new Date()){
 const schedule=VERDICT_INTERVALS[verdict]
 const nextReps=verdict==='correct'?Math.min(reps+1, schedule.length-1):Math.min(Math.max(reps,0), schedule.length-1)
 const days=schedule[nextReps]
 const due=new Date(now); due.setDate(due.getDate()+days)
 return {reps:nextReps,intervalDays:days,dueAt:due.toISOString()}
}
export function nextReview(reps:number,correct:boolean,now=new Date()){
 return nextReviewByVerdict(reps,correct?'correct':'incorrect',now)
}
