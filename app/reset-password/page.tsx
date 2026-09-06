'use client'
import {useEffect,useState} from 'react'
import {getSupabaseBrowser} from '@/lib/supabase'
import '../auth.css'

export default function ResetPassword(){
 const [password,setPassword]=useState('')
 const [confirmPassword,setConfirmPassword]=useState('')
 const [ready,setReady]=useState(false)
 const [busy,setBusy]=useState(false)
 const [error,setError]=useState('')
 useEffect(()=>{const supabase=getSupabaseBrowser();if(!supabase){setError('尚未配置 Supabase。');return}supabase.auth.getUser().then(({data})=>{if(!data.user)setError('设置密码链接无效或已过期，请重新发送。');else setReady(true)})},[])
 const submit=async()=>{setError('');if(password.length<6){setError('密码至少需要 6 位。');return}if(password!==confirmPassword){setError('两次输入的密码不一致。');return}const supabase=getSupabaseBrowser();if(!supabase){setError('尚未配置 Supabase。');return}setBusy(true);const {error:authError}=await supabase.auth.updateUser({password});setBusy(false);if(authError){setError('设置密码失败，请重新发送邮件后再试。');return}location.href='/'}
 return <main className="auth"><div className="auth-card"><div className="brand"><span className="brand-mark">文</span><div><strong>句型教练</strong><small>设置密码</small></div></div><h1>设置新密码</h1><p className="muted">设置完成后，请使用邮箱和新密码登录。</p>{ready&&<><input value={password} onChange={e=>setPassword(e.target.value)} placeholder="新密码（至少 6 位）" type="password" autoComplete="new-password"/><input value={confirmPassword} onChange={e=>setConfirmPassword(e.target.value)} placeholder="再次输入新密码" type="password" autoComplete="new-password"/><button className="primary wide" onClick={submit} disabled={busy}>{busy?'保存中…':'保存密码并继续 →'}</button></>}{error&&<p className="error">{error}</p>}<a href="/login">返回登录</a></div></main>
}
