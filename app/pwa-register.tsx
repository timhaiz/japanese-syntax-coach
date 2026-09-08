'use client'

import {useEffect} from 'react'

/** Registers the small offline cache used by the installable PWA. */
export default function PwaRegister(){
  useEffect(()=>{
    if(typeof window==='undefined'||!('serviceWorker' in navigator))return
    // Avoid caching development assets and hot-reload responses.
    if(process.env.NODE_ENV!=='production')return
    void navigator.serviceWorker.register('/sw.js').catch(()=>{
      // Offline support is progressive enhancement; app remains usable without it.
    })
  },[])
  return null
}
