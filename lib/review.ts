export const REVIEW_INTERVALS=[0,1,3,7,14,30]
export function nextReview(reps:number,correct:boolean,now=new Date()){
 const nextReps=correct?Math.min(reps+1,REVIEW_INTERVALS.length-1):0
 const days=REVIEW_INTERVALS[nextReps]
 const due=new Date(now); due.setDate(due.getDate()+days)
 return {reps:nextReps,intervalDays:days,dueAt:due.toISOString()}
}
